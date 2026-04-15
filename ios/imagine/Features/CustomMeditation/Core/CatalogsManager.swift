//
//  CatalogsManager.swift
//  imagine
//
//  Fetches aggregated meditation catalogs from GET /catalogs server endpoint.
//
//  QA: Filter console logs by "[Server][Catalogs]" to trace server communication.
//

import Foundation

private let kCatalogsServerTag = "[Server][Catalogs]"

/// Server response format for GET /catalogs
private struct CatalogsResponse: Codable {
    let backgroundSounds: [BackgroundSoundItem]
    let binauralBeats: [BinauralBeatItem]
    let cues: [CueItem]
    let bodyScanDurations: [String: Int]
    let voices: [VoiceItem]?

    struct BackgroundSoundItem: Codable {
        let id: String
        let name: String
        let url: String
    }

    struct BinauralBeatItem: Codable {
        let id: String
        let name: String
        let url: String
        let description: String?
    }

    struct CueItem: Codable {
        let id: String
        let name: String
        let url: String
        let urlsByVoice: [String: String]?
    }

    struct VoiceItem: Codable {
        let id: String
        let name: String
    }
}

final class CatalogsManager: ObservableObject {
    static let shared = CatalogsManager()

    @Published private(set) var sounds: [BackgroundSound] = []
    @Published private(set) var beats: [BinauralBeat] = []
    @Published private(set) var cues: [Cue] = []
    @Published private(set) var voices: [VoiceItem] = []
    private(set) var bodyScanDurations: [String: Int] = [:]

    struct VoiceItem: Identifiable {
        let id: String
        let name: String
    }

    private init() {
        loadCachedCatalogs()
    }

    /// Fetch catalogs from GET /catalogs. On success, updates all properties and caches locally.
    /// On failure (e.g. offline), attempts to load from cache. Completion reports whether fresh data was fetched.
    /// - Parameter triggerContext: Optional identifier for QA tracing (e.g. "TimerCreationView|onAppear preload").
    func fetchCatalogs(triggerContext: String? = nil, completion: ((Bool) -> Void)? = nil) {
        let trigger = triggerContext ?? "unknown"
        guard ConnectivityHelper.isConnectedToInternet() else {
            print("\(kCatalogsServerTag) fetchCatalogs: offline trigger=\(trigger) - using cache")
            loadCachedCatalogs()
            completion?(false)
            return
        }

        let url = Config.catalogsURL
        var request = URLRequest(url: url)
        request.setValue(trigger, forHTTPHeaderField: "X-Trigger")
        print("\(kCatalogsServerTag) fetchCatalogs: start trigger=\(trigger) server=\(Config.serverLabel) url=\(url.host ?? "server")/getCatalogs")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { completion?(false); return }
            if let httpResponse = response as? HTTPURLResponse {
                print("\(kCatalogsServerTag) fetchCatalogs: response trigger=\(trigger) status=\(httpResponse.statusCode)")
            }
            if let error = error {
                print("\(kCatalogsServerTag) fetchCatalogs: failure trigger=\(trigger) error=\(error.localizedDescription)")
                logger.errorMessage("CatalogsManager: Network error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.loadCachedCatalogs() }
                completion?(false)
                return
            }
            guard let data = data else {
                print("\(kCatalogsServerTag) fetchCatalogs: failure trigger=\(trigger) - no data received")
                DispatchQueue.main.async { self.loadCachedCatalogs() }
                completion?(false)
                return
            }
            do {
                let decoded = try JSONDecoder().decode(CatalogsResponse.self, from: data)
                let sounds = decoded.backgroundSounds.map { BackgroundSound(id: $0.id, name: $0.name, url: $0.url) }
                let beats = decoded.binauralBeats.map { BinauralBeat(id: $0.id, name: $0.name, url: $0.url, description: $0.description) }
                let cues = Self.normalizedCatalogCues(
                    decoded.cues.map { Cue(id: $0.id, name: $0.name, url: $0.url, urlsByVoice: $0.urlsByVoice) }
                )
                let voices = (decoded.voices ?? []).map { VoiceItem(id: $0.id, name: $0.name) }
                DispatchQueue.main.async {
                    self.sounds = sounds
                    self.beats = beats
                    self.cues = cues
                    self.voices = voices
                    self.bodyScanDurations = decoded.bodyScanDurations
                    self.cacheCatalogs(data: data)
                    print("\(kCatalogsServerTag) fetchCatalogs: success trigger=\(trigger) server=\(Config.serverLabel) sounds=\(sounds.count) beats=\(beats.count) cues=\(cues.count) voices=\(voices.count)")
                    logger.eventMessage("CatalogsManager: Loaded \(sounds.count) sounds, \(beats.count) beats, \(cues.count) cues")
                }
                completion?(true)
            } catch {
                print("\(kCatalogsServerTag) fetchCatalogs: failure trigger=\(trigger) decode error - \(error.localizedDescription)")
                logger.errorMessage("CatalogsManager: Decode error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.loadCachedCatalogs() }
                completion?(false)
            }
        }.resume()
    }

    private func cacheCatalogs(data: Data) {
        let url = localCacheURL()
        do {
            try data.write(to: url)
            print("\(kCatalogsServerTag) cacheCatalogs: saved to disk (\(data.count) bytes)")
        } catch {
            print("\(kCatalogsServerTag) cacheCatalogs: failed to save - \(error.localizedDescription)")
            logger.errorMessage("CatalogsManager: Failed to cache: \(error.localizedDescription)")
        }
    }

    private func loadCachedCatalogs() {
        let url = localCacheURL()
        guard let data = try? Data(contentsOf: url) else {
            print("\(kCatalogsServerTag) loadCachedCatalogs: cache miss - no cached data")
            return
        }
        do {
            let decoded = try JSONDecoder().decode(CatalogsResponse.self, from: data)
            sounds = decoded.backgroundSounds.map { BackgroundSound(id: $0.id, name: $0.name, url: $0.url) }
            beats = decoded.binauralBeats.map { BinauralBeat(id: $0.id, name: $0.name, url: $0.url, description: $0.description) }
            cues = Self.normalizedCatalogCues(
                decoded.cues.map { Cue(id: $0.id, name: $0.name, url: $0.url, urlsByVoice: $0.urlsByVoice) }
            )
            voices = (decoded.voices ?? []).map { VoiceItem(id: $0.id, name: $0.name) }
            bodyScanDurations = decoded.bodyScanDurations
            print("\(kCatalogsServerTag) loadCachedCatalogs: loaded from cache - sounds=\(sounds.count) beats=\(beats.count) cues=\(cues.count) voices=\(voices.count)")
            logger.eventMessage("CatalogsManager: Loaded cached catalog with \(sounds.count) sounds, \(beats.count) beats, \(cues.count) cues")
        } catch {
            print("\(kCatalogsServerTag) loadCachedCatalogs: failed to decode cache - \(error.localizedDescription)")
            logger.errorMessage("CatalogsManager: Failed to load cache: \(error.localizedDescription)")
        }
    }

    private func localCacheURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalogs_cache.json")
    }

    /// Drops legacy `BS_FRAC`, strips deprecated monolithic `PB1`–`PB5`, ensures one fractional Perfect Breath cue (`PB_FRAC`)
    /// and body scan up/down cues exist (stale server/cache safe).
    private static func normalizedCatalogCues(_ cues: [Cue]) -> [Cue] {
        let upId = "BS_FRAC_UP"
        let downId = "BS_FRAC_DOWN"
        let legacyId = "BS_FRAC"
        let deprecatedMonolithicPerfectBreath: Set<String> = ["PB1", "PB2", "PB3", "PB4", "PB5"]
        let pbFracId = "PB_FRAC"
        let legacy = cues.first { $0.id == legacyId }
        let placeholderPath = "modules/body_scan_fractional/asaf/BS_SYS_000_INTRO_SHORT_ASAF.mp3"
        let fallbackUrl = Config.contentStoragePath + placeholderPath
        let perfectBreathPlaceholderPath = "modules/perfect_breath_fractional/asaf/PBV_OPEN_000_INTRO_ASAF.mp3"
        let perfectBreathFallbackUrl = Config.contentStoragePath + perfectBreathPlaceholderPath

        /// Retired from catalog + Timer Create picker (GB remains for optional closing bell).
        let retiredMonolithicCueIds: Set<String> = ["OH", "VC", "RT"]

        var out: [Cue] = []
        out.reserveCapacity(cues.count + 4)
        for c in cues
            where c.id != legacyId
            && !deprecatedMonolithicPerfectBreath.contains(c.id)
            && !retiredMonolithicCueIds.contains(c.id)
        {
            if c.id == upId {
                out.append(Cue(id: c.id, name: "Body Scan Up", url: c.url, urlsByVoice: c.urlsByVoice))
            } else if c.id == downId {
                out.append(Cue(id: c.id, name: "Body Scan Down", url: c.url, urlsByVoice: c.urlsByVoice))
            } else {
                out.append(c)
            }
        }

        let templateUrl: String = {
            if let leg = legacy, !leg.url.isEmpty { return leg.url }
            return fallbackUrl
        }()
        let templateVoices = legacy?.urlsByVoice

        if !out.contains(where: { $0.id == upId }) {
            out.append(Cue(id: upId, name: "Body Scan Up", url: templateUrl, urlsByVoice: templateVoices))
        }
        if !out.contains(where: { $0.id == downId }) {
            out.append(Cue(id: downId, name: "Body Scan Down", url: templateUrl, urlsByVoice: templateVoices))
        }

        if let existing = out.first(where: { $0.id == pbFracId }) {
            if existing.name != "Perfect Breath" {
                if let idx = out.firstIndex(where: { $0.id == pbFracId }) {
                    out[idx] = Cue(
                        id: pbFracId,
                        name: "Perfect Breath",
                        url: existing.url.isEmpty ? perfectBreathFallbackUrl : existing.url,
                        urlsByVoice: existing.urlsByVoice
                    )
                }
            }
        } else {
            out.append(Cue(id: pbFracId, name: "Perfect Breath", url: perfectBreathFallbackUrl))
        }

        return out
    }

    /// Clears the catalogs cache file and in-memory state. Fresh data will be fetched on next fetchCatalogs.
    func clearCache() {
        let url = localCacheURL()
        try? FileManager.default.removeItem(at: url)
        sounds = []
        beats = []
        cues = []
        voices = []
        bodyScanDurations = [:]
        print("\(kCatalogsServerTag) clearCache: catalogs cache cleared")
        logger.eventMessage("CatalogsManager: Cache cleared. Fresh data will be fetched on next load.")
    }
}
