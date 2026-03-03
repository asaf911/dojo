//
//  CustomMeditationConfig.swift
//  Dojo
//
//  Configuration model for custom meditations.
//  Includes deeplink URL generation for reproducing the exact meditation.
//

import Foundation

// MARK: - Audio Layer Config

/// Configuration for an audio layer (background sound or binaural beat).
struct AudioLayerConfig: Codable, Equatable {
    let id: String
    let name: String
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Cue Config

/// Configuration for a meditation cue.
struct CueConfig: Codable, Equatable {
    let id: String
    let name: String
    let triggerType: String  // "start", "minute", "end"
    let triggerMinute: Int?  // For minute-based cues
    
    init(id: String, name: String, triggerType: String, triggerMinute: Int? = nil) {
        self.id = id
        self.name = name
        self.triggerType = triggerType
        self.triggerMinute = triggerMinute
    }
}

// MARK: - Custom Meditation Config

/// Complete configuration for a custom meditation session.
/// Tracks duration, audio layers, cues, and generates deeplink URL for reproduction.
struct CustomMeditationConfig: Codable, Equatable {
    let durationMinutes: Int
    let backgroundSound: AudioLayerConfig?
    let binauralBeat: AudioLayerConfig?
    let cues: [CueConfig]
    
    // MARK: - Initialization
    
    init(
        durationMinutes: Int,
        backgroundSound: AudioLayerConfig? = nil,
        binauralBeat: AudioLayerConfig? = nil,
        cues: [CueConfig] = []
    ) {
        self.durationMinutes = durationMinutes
        self.backgroundSound = backgroundSound
        self.binauralBeat = binauralBeat
        self.cues = cues
    }
    
    /// Create from TimerSessionConfig
    init(from timerConfig: TimerSessionConfig) {
        self.durationMinutes = timerConfig.minutes
        
        // Background sound
        if timerConfig.backgroundSound.name != "None" && !timerConfig.backgroundSound.url.isEmpty {
            self.backgroundSound = AudioLayerConfig(
                id: timerConfig.backgroundSound.id,
                name: timerConfig.backgroundSound.name
            )
        } else {
            self.backgroundSound = nil
        }
        
        // Binaural beat
        if timerConfig.binauralBeat.name != "None" && !timerConfig.binauralBeat.url.isEmpty {
            self.binauralBeat = AudioLayerConfig(
                id: timerConfig.binauralBeat.id,
                name: timerConfig.binauralBeat.name
            )
        } else {
            self.binauralBeat = nil
        }
        
        // Cues
        self.cues = timerConfig.cueSettings.map { setting in
            CueConfig(
                id: setting.cue.id,
                name: setting.cue.name,
                triggerType: setting.triggerType.rawValue,
                triggerMinute: setting.minute
            )
        }
    }
    
    // MARK: - Computed Properties
    
    /// Comma-separated list of cue names for analytics
    var cueNamesString: String {
        cues.map { $0.name }.joined(separator: ",")
    }
    
    /// Number of cues
    var cueCount: Int {
        cues.count
    }
    
    /// Check if specific cue types are present
    var hasBodyScan: Bool {
        cues.contains { $0.id.hasPrefix("BS") }
    }
    
    var hasMantra: Bool {
        cues.contains { $0.id == "MA" }
    }
    
    var hasVisualization: Bool {
        cues.contains { $0.id == "VC" }
    }
    
    var hasOpenHeart: Bool {
        cues.contains { $0.id == "OH" }
    }
    
    var hasRetrospection: Bool {
        cues.contains { $0.id == "RT" }
    }
    
    // MARK: - Deeplink URL Generation
    
    /// Generate a deeplink URL that can recreate this exact meditation configuration.
    /// Format: dojo://create?d=10&bg=rain&bb=alpha&cues=bs,bell
    func generateDeeplinkURL() -> String {
        var components = URLComponents()
        components.scheme = "dojo"
        components.host = "create"
        
        var queryItems: [URLQueryItem] = []
        
        // Duration
        queryItems.append(URLQueryItem(name: "d", value: String(durationMinutes)))
        
        // Background sound
        if let bg = backgroundSound {
            queryItems.append(URLQueryItem(name: "bg", value: bg.id.lowercased()))
        }
        
        // Binaural beat
        if let bb = binauralBeat {
            queryItems.append(URLQueryItem(name: "bb", value: bb.id.lowercased()))
        }
        
        // Cues (comma-separated IDs)
        if !cues.isEmpty {
            let cueIds = cues.map { $0.id.lowercased() }.joined(separator: ",")
            queryItems.append(URLQueryItem(name: "cues", value: cueIds))
            
            // Include trigger times for minute-based cues
            let minuteCues = cues.compactMap { cue -> String? in
                guard cue.triggerType == "minute", let minute = cue.triggerMinute else { return nil }
                return "\(cue.id.lowercased()):\(minute)"
            }
            if !minuteCues.isEmpty {
                queryItems.append(URLQueryItem(name: "cue_times", value: minuteCues.joined(separator: ",")))
            }
        }
        
        components.queryItems = queryItems
        return components.url?.absoluteString ?? "dojo://create?d=\(durationMinutes)"
    }
    
    // MARK: - Analytics Dictionary
    
    /// Convert to dictionary for analytics parameters
    func toAnalyticsParameters() -> [String: Any] {
        var params: [String: Any] = [
            "config_duration_minutes": durationMinutes,
            "config_cue_count": cueCount,
            "config_deeplink_url": generateDeeplinkURL()
        ]
        
        if let bg = backgroundSound {
            params["config_background_sound"] = bg.name
        }
        
        if let bb = binauralBeat {
            params["config_binaural_beat"] = bb.name
        }
        
        if !cues.isEmpty {
            params["config_cue_names"] = cueNamesString
        }
        
        return params
    }
}
