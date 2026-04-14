//
//  PortableTimerDeepLinkPlan.swift
//  Dojo
//
//  Portable timer payload for OneLink URLs (`dlv=2`):
//  - **Preferred:** `pz=<zlib+base64url>` on the **query string** — survives OneLink / HTTP redirects that strip
//    the URL **fragment** (`#…`), which broke earlier `pf=z1` + fragment-only shares.
//  - **Fallback:** `pf=z1` + URL **fragment** `#<zlib+base64url>` — older shares only.
//  - **Legacy:** query `plan=<raw base64url JSON>` (not zlib).
//

import Compression
import Foundation

// MARK: - Zlib (fragment transport keeps query short and link-friendly)

private enum PlanZlibCodec {
    static func compress(_ source: Data) throws -> Data {
        // zlib output is usually smaller than JSON; reserve headroom for edge cases (no public encode_bound in Swift).
        let bound = Swift.max(source.count * 2 + 128, 512)
        var buffer = Data(count: bound)
        let written = buffer.withUnsafeMutableBytes { dstPtr in
            source.withUnsafeBytes { srcPtr in
                compression_encode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!, bound,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!, source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else {
            throw NSError(domain: "PlanZlibCodec", code: 2, userInfo: [NSLocalizedDescriptionKey: "compression_encode_buffer failed"])
        }
        return buffer.prefix(Int(written))
    }

    static func decompress(_ compressed: Data, maxOutputBytes: Int = 4 * 1024 * 1024) throws -> Data {
        var buffer = Data(count: maxOutputBytes)
        let written = buffer.withUnsafeMutableBytes { dstPtr in
            compressed.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!, maxOutputBytes,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else {
            throw NSError(domain: "PlanZlibCodec", code: 3, userInfo: [NSLocalizedDescriptionKey: "compression_decode_buffer failed"])
        }
        return buffer.prefix(Int(written))
    }
}

// MARK: - Payload (JSON)

struct PortableTimerDeepLinkPlanV1: Codable, Equatable {
    /// Schema version; bump when breaking JSON shape.
    var v: Int
    /// Total playback seconds when session includes intro prelude; mirrors `MeditationPackage.playbackDurationSec`.
    var playbackDurationSec: Int?
    var items: [Item]

    struct Item: Codable, Equatable {
        var atSec: Int
        var clipId: String
        var name: String
        var url: String
        var parallel: Parallel?

        struct Parallel: Codable, Equatable {
            var clipId: String
            var url: String
            var text: String?
        }
    }
}

// MARK: - Base64URL JSON codec

enum PortableTimerDeepLinkCodec {
    static let currentSchemaVersion = 1

    static func encodePlanToBase64URL(_ plan: PortableTimerDeepLinkPlanV1) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(plan)
        return data.base64URLEncodedString()
    }

    static func decodePlan(fromBase64URL string: String) throws -> PortableTimerDeepLinkPlanV1 {
        guard let data = Data(base64URLEncoded: string) else {
            throw NSError(domain: "PortableTimerDeepLink", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid base64url plan"])
        }
        return try JSONDecoder().decode(PortableTimerDeepLinkPlanV1.self, from: data)
    }

    /// Zlib-compressed JSON in base64url, for URL **`pz` query** or legacy **fragment** (see `pf=z1`).
    static func encodePlanToZlibFragmentBase64URL(_ plan: PortableTimerDeepLinkPlanV1) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(plan)
        let compressed = try PlanZlibCodec.compress(json)
        return compressed.base64URLEncodedString()
    }

    static func decodePlanFromZlibFragmentBase64URL(_ string: String) throws -> PortableTimerDeepLinkPlanV1 {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let compressed = Data(base64URLEncoded: trimmed) else {
            throw NSError(domain: "PortableTimerDeepLink", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid base64url fragment"])
        }
        let json = try PlanZlibCodec.decompress(compressed)
        return try JSONDecoder().decode(PortableTimerDeepLinkPlanV1.self, from: json)
    }

    /// Applies the same percent-decoding passes used for `cu=` deep links.
    static func percentDecodePlanQueryValue(_ raw: String) -> String {
        let once = raw.removingPercentEncoding ?? raw
        return once.removingPercentEncoding ?? once
    }

    /// Re-applies percent-decoding until stable (handles double-encoded `pz=` / redirect layers).
    static func normalizeEncodedPlanToken(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<6 {
            let next = percentDecodePlanQueryValue(s)
            if next == s { break }
            s = next
        }
        return s
    }

    /// Decodes zlib+base64url portable plan from raw `pz` / `#fragment` payload.
    static func decodeZlibPortablePlan(_ raw: String) -> Result<PortableTimerDeepLinkPlanV1, Error> {
        let normalized = normalizeEncodedPlanToken(raw)
        do {
            return .success(try decodePlanFromZlibFragmentBase64URL(normalized))
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - OneLink / AppsFlyer URL helpers

enum TimerDeepLinkURLHelpers {
    /// Reads `pz=` from `URLComponents` first; falls back to regex on `absoluteString` when the query is huge
    /// or intermediaries produce a URL that still contains `pz=` but drops structured query parsing.
    static func rawPZParameter(from url: URL) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = items.first(where: { $0.name == "pz" })?.value {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return v }
        }
        let abs = url.absoluteString
        guard let re = try? NSRegularExpression(pattern: #"[?&]pz=([^&]+)"#, options: []),
              let m = re.firstMatch(in: abs, options: [], range: NSRange(location: 0, length: (abs as NSString).length)),
              m.numberOfRanges > 1,
              let range = Range(m.range(at: 1), in: abs) else {
            return nil
        }
        return String(abs[range])
    }
}

// MARK: - Build plan from runtime types

extension PortableTimerDeepLinkPlanV1 {
    /// Builds a portable document from a timer session (share sheet / editor).
    init(timerConfig: TimerSessionConfig) {
        let endSeconds = timerConfig.playbackDurationSeconds ?? (timerConfig.minutes * 60)
        self.v = PortableTimerDeepLinkCodec.currentSchemaVersion
        self.playbackDurationSec = timerConfig.playbackDurationSeconds
        let mapped = timerConfig.cueSettings.map { setting in
            Item(
                atSec: Self.atSec(for: setting, sessionEndSeconds: endSeconds),
                clipId: setting.cue.id,
                name: setting.cue.name,
                url: setting.cue.url,
                parallel: setting.cue.parallelSfx.map { p in
                    Item.Parallel(clipId: p.id, url: p.url, text: p.name)
                }
            )
        }
        self.items = Self.sortedPlanItems(mapped)
    }

    /// Builds from a server `MeditationPackage` (POST /meditations).
    /// - Important: Applies the same `INT_FRAC` intro-prefix shift as `MeditationConfiguration.makeTimerSessionConfig`
    ///   so `atSec` values are **wall-clock session seconds**. Raw package minute triggers are practice-relative;
    ///   without this shift, deep-linked playback schedules every module’s clips too early and only the first
    ///   clip overlaps real session time.
    init(package: MeditationPackage) {
        self.v = PortableTimerDeepLinkCodec.currentSchemaVersion
        let playback = package.playbackDurationSec ?? Self.fallbackPlaybackSeconds(for: package)
        self.playbackDurationSec = playback

        let shiftedCueSettings = package
            .toTimerSessionConfig(isDeepLinked: false)
            .cueSettings
            .applyingIntroPrefixIfNeeded(practiceMinutes: package.duration)

        let mapped = shiftedCueSettings.map { setting in
            Item(
                atSec: Self.atSec(for: setting, sessionEndSeconds: playback),
                clipId: setting.cue.id,
                name: setting.cue.name,
                url: setting.cue.url,
                parallel: setting.cue.parallelSfx.map { p in
                    Item.Parallel(clipId: p.id, url: p.url, text: p.name)
                }
            )
        }
        self.items = Self.sortedPlanItems(mapped)
    }

    func toTimerSessionConfig(
        durationMinutes: Int,
        backgroundSound: BackgroundSound,
        binauralBeat: BinauralBeat,
        title: String?,
        description: String?
    ) -> TimerSessionConfig {
        var assignedStartAtZero = false
        let orderedItems = Self.sortedPlanItems(items)
        let cueSettings: [CueSetting] = orderedItems.map { item in
            let parallel = item.parallel.map { ParallelSfxCue(id: $0.clipId, name: $0.text ?? $0.clipId, url: $0.url) }
            let cue = Cue(id: item.clipId, name: item.name, url: item.url, parallelSfx: parallel)
            if item.atSec == 0, !assignedStartAtZero {
                assignedStartAtZero = true
                return CueSetting(triggerType: .start, minute: nil, cue: cue)
            }
            return CueSetting(triggerType: .second, minute: item.atSec, cue: cue)
        }
        return TimerSessionConfig(
            minutes: durationMinutes,
            playbackDurationSeconds: playbackDurationSec,
            backgroundSound: backgroundSound,
            binauralBeat: binauralBeat,
            cueSettings: cueSettings,
            isDeepLinked: true,
            title: title,
            description: description
        )
    }

    private static func atSec(for setting: CueSetting, sessionEndSeconds: Int) -> Int {
        switch setting.triggerType {
        case .start:
            return 0
        case .end:
            return max(0, sessionEndSeconds - 1)
        case .minute:
            return (setting.minute ?? 0) * 60
        case .second:
            return setting.minute ?? 0
        }
    }

    /// Stable order so the first `atSec == 0` row is deterministic (typically intro) when decoding to `.start`.
    private static func sortedPlanItems(_ items: [Item]) -> [Item] {
        items.sorted {
            if $0.atSec != $1.atSec { return $0.atSec < $1.atSec }
            return $0.clipId < $1.clipId
        }
    }

    /// Matches `MeditationConfiguration.makeTimerSessionConfig` when the server omits `playbackDurationSec`.
    private static func fallbackPlaybackSeconds(for package: MeditationPackage) -> Int {
        let hasIntroFrac = package.cues.contains { cue in
            guard cue.id == "INT_FRAC" else { return false }
            if case .start = cue.trigger { return true }
            return false
        }
        if hasIntroFrac {
            return IntroPrefixTimeline.playbackSeconds(practiceMinutes: package.duration, hasIntroFrac: true)
        }
        return package.duration * 60
    }
}

// MARK: - OneLink query assembly

enum TimerOneLinkShareURLBuilder {
    /// Builds a OneLink URL with `dlv=2`, `pf=z1`, and zlib+JSON in the **`pz` query** (survives redirects; fragment-only links often broke).
    static func timerShareURL(
        baseURL: String = Config.oneLinkBaseURL,
        durationMinutes: Int,
        backgroundSoundId: String,
        binauralBeatId: String,
        plan: PortableTimerDeepLinkPlanV1,
        campaign: String,
        afSub1: String
    ) throws -> URL {
        let zlibPayload = try PortableTimerDeepLinkCodec.encodePlanToZlibFragmentBase64URL(plan)
        var components = URLComponents(string: baseURL)
        // `pz` must survive OneLink → app opens; fragment is often dropped on redirect.
        components?.queryItems = [
            URLQueryItem(name: "dlv", value: "2"),
            URLQueryItem(name: "dur", value: "\(durationMinutes)"),
            URLQueryItem(name: "bs", value: backgroundSoundId),
            URLQueryItem(name: "bb", value: binauralBeatId),
            URLQueryItem(name: "pf", value: "z1"),
            URLQueryItem(name: "pz", value: zlibPayload),
            URLQueryItem(name: "c", value: campaign),
            URLQueryItem(name: "af_sub1", value: afSub1),
        ]
        // Fragment omitted: OneLink / universal-link redirects often drop `#…`, which broke fractional shares.
        guard let url = components?.url else {
            throw NSError(domain: "TimerOneLinkShareURLBuilder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid OneLink URL"])
        }
        return url
    }

    /// Preferred share URL for timer sessions; falls back to abbreviated `cu` when plan encoding fails or there are no cues.
    static func makeTimerShareURL(timerConfig: TimerSessionConfig, campaign: String, afSub1: String) -> URL? {
        if !timerConfig.cueSettings.isEmpty {
            do {
                let plan = PortableTimerDeepLinkPlanV1(timerConfig: timerConfig)
                return try timerShareURL(
                    durationMinutes: timerConfig.minutes,
                    backgroundSoundId: timerConfig.backgroundSound.id,
                    binauralBeatId: timerConfig.binauralBeat.id,
                    plan: plan,
                    campaign: campaign,
                    afSub1: afSub1
                )
            } catch {
                logger.errorMessage("TimerOneLinkShareURLBuilder: portable plan encode failed: \(error.localizedDescription)")
            }
        }
        return legacyAbbreviatedTimerShareURL(
            durationMinutes: timerConfig.minutes,
            backgroundSoundId: timerConfig.backgroundSound.id,
            binauralBeatId: timerConfig.binauralBeat.id,
            cueSettings: timerConfig.cueSettings,
            campaign: campaign,
            afSub1: afSub1
        )
    }

    /// Legacy `dur`/`bs`/`bb`/`cu` link (catalog-resolvable cue ids only).
    private static func legacyAbbreviatedTimerShareURL(
        durationMinutes: Int,
        backgroundSoundId: String,
        binauralBeatId: String,
        cueSettings: [CueSetting],
        campaign: String,
        afSub1: String
    ) -> URL? {
        let baseURL = Config.oneLinkBaseURL
        var components = URLComponents(string: baseURL)
        let cuRawValue = cueSettings.compactMap { cueSetting -> String? in
            let id = cueSetting.cue.id
            let trigger: String
            switch cueSetting.triggerType {
            case .start: trigger = "S"
            case .end: trigger = "E"
            case .minute: trigger = "\(cueSetting.minute ?? 0)"
            case .second: trigger = "s\(cueSetting.minute ?? 0)"
            }
            return "\(id):\(trigger)"
        }.joined(separator: ",")
        components?.queryItems = [
            URLQueryItem(name: "dur", value: "\(durationMinutes)"),
            URLQueryItem(name: "bs", value: backgroundSoundId),
            URLQueryItem(name: "bb", value: binauralBeatId),
            URLQueryItem(name: "cu", value: cuRawValue),
            URLQueryItem(name: "c", value: campaign),
            URLQueryItem(name: "af_sub1", value: afSub1),
        ]
        return components?.url
    }
}

// MARK: - Data base64url

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    fileprivate init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: padding)
        }
        self.init(base64Encoded: base64)
    }
}
