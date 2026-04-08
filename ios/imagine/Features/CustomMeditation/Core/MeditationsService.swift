//
//  MeditationsService.swift
//  imagine
//
//  POST /meditations (manual + AI paths) — creates meditation package from structured selections or free-text prompts.
//  QA: Filter console logs by "[Server][Meditations]" or "[Server][Meditations-AI]" to trace server communication.
//

import Foundation

// MARK: - Response Models (server JSON)

/// Server response for POST /meditations
struct MeditationPackage: Codable {
    let id: String
    let title: String?
    let duration: Int
    let description: String?
    let backgroundSound: MeditationAsset
    let binauralBeat: MeditationAsset?
    let cues: [MeditationCue]
}

/// Asset with id, name, url (background sound or binaural beat)
struct MeditationAsset: Codable {
    let id: String
    let name: String
    let url: String
    let description: String?
}

/// Cue with trigger (start | end | minute | second via server string)
struct MeditationCue: Codable {
    let id: String
    let name: String
    let url: String
    let trigger: CueTrigger
    let parallelSfx: ParallelSfxCue?

    init(
        id: String,
        name: String,
        url: String,
        trigger: CueTrigger,
        parallelSfx: ParallelSfxCue? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.trigger = trigger
        self.parallelSfx = parallelSfx
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url, trigger, parallelSfx
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        trigger = try container.decode(CueTrigger.self, forKey: .trigger)
        parallelSfx = try container.decodeIfPresent(ParallelSfxCue.self, forKey: .parallelSfx)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(trigger, forKey: .trigger)
        try container.encodeIfPresent(parallelSfx, forKey: .parallelSfx)
    }
}

/// Server returns trigger as "start" | "end" | number | "s{seconds}"
enum CueTrigger: Codable {
    case start
    case end
    case minute(Int)
    case second(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            switch s {
            case "start": self = .start
            case "end": self = .end
            default:
                if s.hasPrefix("s"), let n = Int(s.dropFirst()) {
                    self = .second(n)
                } else if let n = Int(s) {
                    self = .minute(n)
                } else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid trigger string: \(s)"
                    )
                }
            }
        } else if let n = try? container.decode(Int.self) {
            self = .minute(n)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Trigger must be string or number"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .start: try container.encode("start")
        case .end: try container.encode("end")
        case .minute(let m): try container.encode(m)
        case .second(let s): try container.encode("s\(s)")
        }
    }
}

// MARK: - Conversion to TimerSessionConfig

extension MeditationPackage {
    /// Converts server response to TimerSessionConfig for navigation to player.
    func toTimerSessionConfig(isDeepLinked: Bool = false) -> TimerSessionConfig {
        let backgroundSound = BackgroundSound(
            id: backgroundSound.id,
            name: backgroundSound.name,
            url: backgroundSound.url
        )
        let binauralBeat: BinauralBeat
        if let bb = self.binauralBeat {
            binauralBeat = BinauralBeat(
                id: bb.id,
                name: bb.name,
                url: bb.url,
                description: bb.description
            )
        } else {
            binauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
        }
        let cueSettings = cues.map { mc -> CueSetting in
            let cue = Cue(id: mc.id, name: mc.name, url: mc.url, parallelSfx: mc.parallelSfx)
            switch mc.trigger {
            case .start:
                return CueSetting(triggerType: .start, minute: nil, cue: cue)
            case .end:
                return CueSetting(triggerType: .end, minute: nil, cue: cue)
            case .minute(let m):
                return CueSetting(triggerType: .minute, minute: m, cue: cue)
            case .second(let s):
                return CueSetting(triggerType: .second, minute: s, cue: cue)
            }
        }
        return TimerSessionConfig(
            minutes: duration,
            backgroundSound: backgroundSound,
            binauralBeat: binauralBeat,
            cueSettings: cueSettings,
            isDeepLinked: isDeepLinked,
            title: title,
            description: description
        )
    }
}

// MARK: - Request Models

private struct PostMeditationsRequestBody: Encodable {
    let type: String = "manual"
    let voiceId: String?
    let duration: Int
    let backgroundSoundId: String
    let binauralBeatId: String?
    let cues: [CueRequestItem]
}

private struct CueRequestItem: Encodable {
    let id: String
    let trigger: CueTriggerValue
    let durationMinutes: Int?
}

/// Trigger for manual meditation request: "start" | "end" | minute number
enum CueTriggerValue: Encodable {
    case start
    case end
    case minute(Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .start: try container.encode("start")
        case .end: try container.encode("end")
        case .minute(let m): try container.encode(m)
        }
    }
}

/// Conversation history item for AI path
struct ConversationHistoryItem: Encodable {
    let role: String
    let content: String
}

private struct PostMeditationsAIRequestBody: Encodable {
    let type: String = "ai"
    let voiceId: String?
    let prompt: String
    let conversationHistory: [ConversationHistoryItem]
    let maxDuration: Int?
}

// MARK: - Service (struct of closures)

struct MeditationsService {
    /// Create a meditation via POST /meditations (manual path).
    /// Throws on network or decode error; caller handles offline fallback.
    /// - Parameter triggerContext: Optional identifier for QA tracing (e.g. "TimerCreationView|Create tapped").
    var createMeditationManual: (
        _ duration: Int,
        _ backgroundSoundId: String,
        _ binauralBeatId: String?,
        _ cues: [(id: String, trigger: CueTriggerValue, durationMinutes: Int?)],
        _ triggerContext: String?
    ) async throws -> MeditationPackage

    /// Create a meditation via POST /meditations (AI path).
    /// Throws on network or decode error; caller handles offline fallback.
    /// - Parameter triggerContext: Optional identifier for QA tracing (e.g. "AIRequestManager|generateMeditation").
    var createMeditationAI: (
        _ prompt: String,
        _ conversationHistory: [ConversationHistoryItem],
        _ maxDuration: Int?,
        _ triggerContext: String?
    ) async throws -> MeditationPackage
}

// MARK: - Convenience: Create from CueSettings (caller-facing API)

extension MeditationsService {
    /// Create a meditation from app CueSettings. Converts to request format internally.
    /// - Parameter triggerContext: Optional identifier for QA tracing (e.g. "TimerCreationView|Create tapped").
    func createMeditationManual(
        duration: Int,
        backgroundSoundId: String,
        binauralBeatId: String?,
        cueSettings: [CueSetting],
        triggerContext: String? = nil
    ) async throws -> MeditationPackage {
        let cues = cueSettings.map { cs -> (id: String, trigger: CueTriggerValue, durationMinutes: Int?) in
            let trigger: CueTriggerValue
            switch cs.triggerType {
            case .start: trigger = .start
            case .end: trigger = .end
            case .minute: trigger = .minute(cs.minute ?? 1)
            case .second: trigger = .start
            }
            return (cs.cue.id, trigger, cs.fractionalDuration)
        }
        return try await createMeditationManual(duration, backgroundSoundId, binauralBeatId, cues, triggerContext)
    }
}

// MARK: - Live

extension MeditationsService {
    static let live = MeditationsService(
        createMeditationManual: { duration, backgroundSoundId, binauralBeatId, cues, triggerContext in
            let tag = "[Server][Meditations]"
            let trigger = triggerContext ?? "unknown"
            let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
            print("\(tag) createMeditationManual: start trigger=\(trigger) server=\(Config.serverLabel) duration=\(duration) cueCount=\(cues.count) bs=\(backgroundSoundId) bb=\(binauralBeatId ?? "None") voiceId=\(voiceId)")
            var request = URLRequest(url: Config.meditationsURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(trigger, forHTTPHeaderField: "X-Trigger")
            let body = PostMeditationsRequestBody(
                voiceId: voiceId,
                duration: duration,
                backgroundSoundId: backgroundSoundId,
                binauralBeatId: binauralBeatId,
                cues: cues.map { CueRequestItem(id: $0.id, trigger: $0.trigger, durationMinutes: $0.durationMinutes) }
            )
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("\(tag) createMeditationManual: failure trigger=\(trigger) - invalid response type")
                throw NSError(domain: "MeditationsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            if http.statusCode != 200 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                print("\(tag) createMeditationManual: failure trigger=\(trigger) status=\(http.statusCode) body=\(String(bodyStr.prefix(200)))")
                throw NSError(domain: "MeditationsService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"])
            }
            do {
                let package = try JSONDecoder().decode(MeditationPackage.self, from: data)
                let cuePaths = package.cues.map { "\($0.id)=\($0.url.split(separator: "/").last.map(String.init) ?? $0.url)" }.joined(separator: " ")
                print("\(tag) createMeditationManual: success trigger=\(trigger) server=\(Config.serverLabel) id=\(package.id) duration=\(package.duration) title=\(package.title ?? "nil") voiceId=\(voiceId) cues=[\(cuePaths)]")
                return package
            } catch {
                print("\(tag) createMeditationManual: failure trigger=\(trigger) decode error - \(error.localizedDescription)")
                throw error
            }
        },
        createMeditationAI: { prompt, conversationHistory, maxDuration, triggerContext in
            let tag = "[Server][Meditations-AI]"
            let trigger = triggerContext ?? "unknown"
            let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
            print("\(tag) createMeditationAI: start trigger=\(trigger) server=\(Config.serverLabel) promptLen=\(prompt.count) historyLen=\(conversationHistory.count) maxDuration=\(maxDuration?.description ?? "nil") voiceId=\(voiceId)")
            var request = URLRequest(url: Config.meditationsURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(trigger, forHTTPHeaderField: "X-Trigger")
            let body = PostMeditationsAIRequestBody(
                voiceId: voiceId,
                prompt: prompt,
                conversationHistory: conversationHistory,
                maxDuration: maxDuration
            )
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("\(tag) createMeditationAI: failure trigger=\(trigger) - invalid response type")
                throw NSError(domain: "MeditationsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            if http.statusCode != 200 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                print("\(tag) createMeditationAI: failure trigger=\(trigger) status=\(http.statusCode) error=\(String(bodyStr.prefix(200)))")
                throw NSError(domain: "MeditationsService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"])
            }
            do {
                let package = try JSONDecoder().decode(MeditationPackage.self, from: data)
                let cuePaths = package.cues.map { "\($0.id)=\($0.url.split(separator: "/").last.map(String.init) ?? $0.url)" }.joined(separator: " ")
                print("\(tag) createMeditationAI: success trigger=\(trigger) server=\(Config.serverLabel) id=\(package.id) duration=\(package.duration) title=\(package.title ?? "nil") voiceId=\(voiceId) cues=[\(cuePaths)]")
                return package
            } catch {
                print("\(tag) createMeditationAI: failure trigger=\(trigger) decode error - \(error.localizedDescription)")
                throw error
            }
        }
    )
}

// MARK: - Shared (production)

extension MeditationsService {
    static var shared: MeditationsService { .live }
}

// MARK: - Preview

extension MeditationsService {
    static let preview = MeditationsService(
        createMeditationManual: { duration, backgroundSoundId, binauralBeatId, cues, _ in
            try await Task.sleep(nanoseconds: 300_000_000)
            return MeditationPackage(
                id: "preview-\(UUID().uuidString.prefix(8))",
                title: nil,
                duration: duration,
                description: nil,
                backgroundSound: MeditationAsset(id: backgroundSoundId, name: "Preview Sound", url: "gs://preview", description: nil),
                binauralBeat: binauralBeatId.map { MeditationAsset(id: $0, name: "Preview Beat", url: "gs://preview", description: nil) },
                cues: cues.map { c in
                    let trigger: CueTrigger
                    switch c.trigger {
                    case .start: trigger = .start
                    case .end: trigger = .end
                    case .minute(let m): trigger = .minute(m)
                    }
                    return MeditationCue(id: c.id, name: "Preview Cue", url: "gs://preview", trigger: trigger)
                }
            )
        },
        createMeditationAI: { _, _, _, _ in
            try await Task.sleep(nanoseconds: 500_000_000)
            return MeditationPackage(
                id: "preview-ai-\(UUID().uuidString.prefix(8))",
                title: "Preview AI Meditation",
                duration: 10,
                description: "Preview meditation from AI path.",
                backgroundSound: MeditationAsset(id: "SP", name: "Preview Sound", url: "gs://preview", description: nil),
                binauralBeat: MeditationAsset(id: "BB10", name: "Preview Beat", url: "gs://preview", description: nil),
                cues: [
                    MeditationCue(id: "INT_GEN_1", name: "General Introduction", url: "gs://preview", trigger: .start),
                    MeditationCue(id: "PB_FRAC", name: "Perfect Breath", url: "gs://preview", trigger: .minute(1), parallelSfx: nil),
                    MeditationCue(id: "BS_FRAC_UP", name: "Body Scan Up", url: "gs://preview", trigger: .minute(2)),
                    MeditationCue(id: "IM_FRAC", name: "I AM Mantra", url: "gs://preview", trigger: .minute(3)),
                    MeditationCue(id: "GB", name: "Gentle Bell", url: "gs://preview", trigger: .end),
                ]
            )
        }
    )
}
