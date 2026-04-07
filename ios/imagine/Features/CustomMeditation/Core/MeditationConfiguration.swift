//
//  MeditationConfiguration.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-03-01
//

import Foundation

struct MeditationConfiguration: Codable, Identifiable {
    var id: UUID = UUID()
    var duration: Int = 5 // Duration in minutes
    var backgroundSound: BackgroundSound = BackgroundSound(id: "None", name: "None", url: "")
    var cueSettings: [CueSetting] = []
    var title: String? = nil
    var binauralBeat: BinauralBeat? = nil

    enum CodingKeys: String, CodingKey {
        case id, duration, backgroundSound, cueSettings, title, binauralBeat
        case timerDuration // For backward compatibility
    }

    init(id: UUID = UUID(),
         duration: Int = 5,
         backgroundSound: BackgroundSound = BackgroundSound(id: "None", name: "None", url: ""),
         cueSettings: [CueSetting] = [],
         title: String? = nil,
         binauralBeat: BinauralBeat? = nil) {
        self.id = id
        self.duration = duration
        self.backgroundSound = backgroundSound
        self.cueSettings = cueSettings
        self.title = title
        self.binauralBeat = binauralBeat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        
        // Try new key first, then fall back to old key for backward compatibility
        if let newDuration = try container.decodeIfPresent(Int.self, forKey: .duration) {
            duration = newDuration
        } else {
            duration = try container.decodeIfPresent(Int.self, forKey: .timerDuration) ?? 5
        }
        
        backgroundSound = try container.decodeIfPresent(BackgroundSound.self, forKey: .backgroundSound) ?? BackgroundSound(id: "None", name: "None", url: "")
        cueSettings = try container.decodeIfPresent([CueSetting].self, forKey: .cueSettings) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title)
        binauralBeat = try container.decodeIfPresent(BinauralBeat.self, forKey: .binauralBeat)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(duration, forKey: .duration)
        try container.encode(backgroundSound, forKey: .backgroundSound)
        try container.encode(cueSettings, forKey: .cueSettings)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(binauralBeat, forKey: .binauralBeat)
    }
}

// MARK: - Deep Link Convenience Initializer and Dynamic Mappings

extension MeditationConfiguration {
    /// Initialize a MeditationConfiguration from URL query items using abbreviated keys.
    /// Expected keys:
    ///   - "dur" : duration (in minutes, Int)
    ///   - "bs"  : background sound ID (e.g., "B4")
    ///   - "bb"  : binaural beat ID (e.g., "BB1")
    ///   - "cu"  : cues in the format "<ID>:<trigger>", where trigger is "S" for start, "E" for end, or a numeric value (e.g., "7") for a specific minute.
    init?(queryItems: [URLQueryItem]) {
        // Log the incoming query items for debugging
        logger.eventMessage("MeditationConfiguration: Initializing from query items: \(queryItems)")
        
        // Ensure duration parameter is present and valid.
        guard let durValue = queryItems.first(where: { $0.name == "dur" })?.value,
              let duration = Int(durValue)
        else {
            logger.errorMessage("MeditationConfiguration: Failed to parse duration parameter from query items")
            return nil
        }
        logger.eventMessage("MeditationConfiguration: Duration parsed: \(duration)")
        self.duration = duration
        
        // Get background sound using dynamic lookup.
        let bsID = queryItems.first(where: { $0.name == "bs" })?.value ?? "None"
        self.backgroundSound = MeditationConfiguration.backgroundSound(forID: bsID)
        logger.eventMessage("MeditationConfiguration: Background sound parsed: \(backgroundSound.name) (ID: \(backgroundSound.id))")
        
        // Parse cues.
        if let cuValue = queryItems.first(where: { $0.name == "cu" })?.value {
            // Additional decoding step to handle double-encoded values.
            let decodedValue = cuValue.removingPercentEncoding ?? cuValue
            let finalValue = decodedValue.removingPercentEncoding ?? decodedValue
            let cueComponents = finalValue.split(separator: ",").map { String($0) }
            logger.eventMessage("MeditationConfiguration: Parsed cue components: \(cueComponents)")
            self.cueSettings = cueComponents.compactMap { MeditationConfiguration.cueSetting(from: $0) }
            logger.eventMessage("MeditationConfiguration: Created \(self.cueSettings.count) cue settings")
        } else {
            logger.eventMessage("MeditationConfiguration: No cues found in query items")
            self.cueSettings = []
        }
        // Parse binaural beat using dynamic lookup.
        let bbID = queryItems.first(where: { $0.name == "bb" })?.value ?? "None"
        self.binauralBeat = bbID == "None" ? nil : MeditationConfiguration.binauralBeat(forID: bbID)
        logger.eventMessage("MeditationConfiguration: Binaural beat parsed: \(binauralBeat?.name ?? "None") (ID: \(bbID))")
        self.title = nil
        self.id = UUID()
    }
    
    /// Dynamically looks up a BinauralBeat from CatalogsManager by matching its id.
    static func binauralBeat(forID id: String) -> BinauralBeat? {
        CatalogsManager.shared.beats.first(where: { $0.id == id })
    }

    /// Dynamically looks up a BackgroundSound from BackgroundSoundManager by matching its id.
    static func backgroundSound(forID id: String) -> BackgroundSound {
        if let sound = CatalogsManager.shared.sounds.first(where: { $0.id == id }) {
            return sound
        }
        return BackgroundSound(id: "None", name: "None", url: "")
    }
    
    /// Dynamically creates a CueSetting by looking up a Cue from CueManager by matching its id.
    static func cueSetting(from cueString: String) -> CueSetting? {
        let parts = cueString.split(separator: ":")
        guard let idPart = parts.first else { return nil }
        var cueID = String(idPart)
        if cueID == "SI" { cueID = "INT_GEN_1" }  // Migration: old Settling In → Introduction
        guard let cue = CatalogsManager.shared.cues.first(where: { $0.id == cueID }) else { return nil }
        
        var triggerType: CueTriggerType = .minute
        var minute: Int? = 1
        if parts.count > 1 {
            let triggerString = String(parts[1])
            if triggerString.uppercased() == "S" {
                triggerType = .start
                minute = nil
            } else if triggerString.uppercased() == "E" {
                triggerType = .end
                minute = nil
            } else if triggerString.hasPrefix("s"), let sec = Int(triggerString.dropFirst()) {
                triggerType = .second
                minute = sec
            } else if let minValue = Int(triggerString) {
                triggerType = .minute
                minute = minValue
            }
        }
        return CueSetting(triggerType: triggerType, minute: minute, cue: cue)
    }

    /// Converts to TimerSessionConfig with cue URLs resolved for the given voice.
    func toTimerSessionConfig(voiceId: String, isDeepLinked: Bool = true, description: String? = nil) -> TimerSessionConfig {
        let resolvedCueSettings = cueSettings.map { cs in
            let resolvedCue = Cue(
                id: cs.cue.id,
                name: cs.cue.name,
                url: cs.cue.url(forVoice: voiceId)
            )
            return CueSetting(id: cs.id, triggerType: cs.triggerType, minute: cs.minute, cue: resolvedCue)
        }
        return TimerSessionConfig(
            minutes: duration,
            backgroundSound: backgroundSound,
            binauralBeat: binauralBeat ?? BinauralBeat(id: "None", name: "None", url: "", description: nil),
            cueSettings: resolvedCueSettings,
            isDeepLinked: isDeepLinked,
            title: title,
            description: description
        )
    }
}
