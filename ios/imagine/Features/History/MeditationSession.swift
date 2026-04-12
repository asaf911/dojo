//
//  MeditationSession.swift
//  Dojo
//
//  Rich data model for comprehensive session history storage.
//  Designed for UI display, AI querying, and future Firebase sync.
//

import Foundation

// MARK: - Session Type

enum MeditationSessionType: String, Codable, CaseIterable {
    case guided       // Regular guided practice from library
    case custom       // Custom timer meditation
    case aiGenerated  // AI-generated meditation
}

// MARK: - Session Source

enum MeditationSessionSource: String, Codable, CaseIterable {
    case dojo         // From Dojo library
    case explore      // From Explore section
    case path         // From Path journey
    case aiChat       // Created via AI chat
    case timer        // Created via timer screen
    case deeplink     // Started via deep link
    case unknown
}

// MARK: - Session Outcome

enum SessionOutcome: String, Codable {
    case completed     // Finished normally (100%)
    case almostDone    // Reached 95%+ but not 100%
    case partial       // Partial completion (75%+)
    case abandoned     // Stopped early (<75%)
}

// MARK: - Heart Rate Nadir (Session Minimum)

struct NadirContent: Codable, Equatable {
    let contentType: String
    let practiceId: String?
    let practiceTitle: String
    let cueId: String?
    let cueName: String?
}

struct HeartRateNadir: Codable, Equatable {
    let bpm: Double
    let minuteOffset: Double
    let timestamp: Date?
    let contentAtTime: NadirContent?
}

/// Stored record of the lowest heart rate recorded during any session (all-time).
/// Used for awareness and quick lookup without scanning full history.
struct AllTimeLowestNadir: Codable, Equatable {
    let bpm: Double
    let sessionId: UUID
    let date: Date
    let sessionTitle: String
    let minuteOffset: Double
}

// MARK: - Heart Rate Data

struct SessionHeartRateData: Codable, Equatable {
    let startBPM: Double?         // Average of first 3 readings
    let endBPM: Double?           // Average of last 3 readings
    let averageBPM: Double?       // Overall average
    let minBPM: Double?           // Minimum recorded
    let maxBPM: Double?           // Maximum recorded
    let changePercent: Double?    // (end - start) / start * 100
    let readingCount: Int         // Number of HR readings
    let source: String?           // "watch" or "airpods"
    let samples: [HeartRateSamplePoint]  // Individual sample points for graphing and AI analysis
    let nadir: HeartRateNadir?    // Lowest BPM during session with metadata
    
    var hasValidData: Bool {
        startBPM != nil && endBPM != nil && readingCount > 0
    }
    
    var bpmReduction: Double? {
        guard let start = startBPM, let end = endBPM, start > 0 else { return nil }
        return start - end
    }
    
    var bpmReductionPercent: Double? {
        guard let start = startBPM, let end = endBPM, start > 0 else { return nil }
        return ((start - end) / start) * 100
    }
    
    init(
        startBPM: Double? = nil,
        endBPM: Double? = nil,
        averageBPM: Double? = nil,
        minBPM: Double? = nil,
        maxBPM: Double? = nil,
        changePercent: Double? = nil,
        readingCount: Int = 0,
        source: String? = nil,
        samples: [HeartRateSamplePoint] = [],
        nadir: HeartRateNadir? = nil
    ) {
        self.startBPM = startBPM
        self.endBPM = endBPM
        self.averageBPM = averageBPM
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        self.changePercent = changePercent
        self.readingCount = readingCount
        self.source = source
        self.samples = samples
        self.nadir = nadir
    }
    
    /// Create from PracticeBPMTracker results
    /// Uses bestFirstThreeAverage/bestLastThreeAverage which return locked final values when available
    static func fromTracker() -> SessionHeartRateData? {
        let tracker = PracticeBPMTracker.shared
        let first = tracker.bestFirstThreeAverage  // Uses locked value if available
        let last = tracker.bestLastThreeAverage    // Uses locked value if available
        let minBPMVal = tracker.bestMinBPM
        let maxBPMVal = tracker.bestMaxBPM
        
        print("🧠 AI_DEBUG HISTORY fromTracker: hasLocked=\(tracker.hasLockedResults) first=\(Int(first)) last=\(Int(last)) avg=\(Int(tracker.bestOverallAverage)) min=\(Int(minBPMVal))")
        
        guard first > 0 || last > 0 else {
            print("🧠 AI_DEBUG HISTORY fromTracker: returning nil - no valid HR data")
            return nil
        }
        
        let change: Double? = {
            guard first > 0, last > 0 else { return nil }
            return ((last - first) / first) * 100
        }()
        
        let samples = tracker.graphSamples
        
        // Build nadir when we have min BPM and valid data
        let nadir: HeartRateNadir? = {
            guard minBPMVal > 0 else { return nil }
            let minuteOffset = tracker.bestNadirMinuteOffset
            let timestamp = tracker.nadirTimestamp
            
            let contentAtTime: NadirContent? = {
                if let context = SessionContextManager.shared.currentContext {
                    let cueId: String?
                    let cueName: String?
                    if context.contentType == .customMeditation,
                       let cueInfo = CuePlaybackManager.shared.getCurrentCueInfo() {
                        cueId = cueInfo.id
                        cueName = nil  // Cue name lookup would require CatalogsManager
                    } else {
                        cueId = nil
                        cueName = nil
                    }
                    return NadirContent(
                        contentType: context.contentType.rawValue,
                        practiceId: context.practiceId,
                        practiceTitle: context.practiceTitle,
                        cueId: cueId,
                        cueName: cueName
                    )
                }
                return nil
            }()
            
            return HeartRateNadir(
                bpm: minBPMVal,
                minuteOffset: minuteOffset,
                timestamp: timestamp,
                contentAtTime: contentAtTime
            )
        }()
        
        let result = SessionHeartRateData(
            startBPM: first > 0 ? first : nil,
            endBPM: last > 0 ? last : nil,
            averageBPM: tracker.bestOverallAverage > 0 ? tracker.bestOverallAverage : nil,
            minBPM: minBPMVal > 0 ? minBPMVal : nil,
            maxBPM: maxBPMVal > 0 ? maxBPMVal : nil,
            changePercent: change,
            readingCount: tracker.hasLockedResults ? tracker.finalSampleCount : tracker.sampleCount,
            source: nil, // Could be determined from connectivity state
            samples: samples,
            nadir: nadir
        )
        print("🧠 AI_DEBUG HISTORY fromTracker: created SessionHeartRateData start=\(Int(result.startBPM ?? 0)) end=\(Int(result.endBPM ?? 0)) min=\(Int(result.minBPM ?? 0)) nadir=\(nadir != nil) samples=\(samples.count)")
        return result
    }
}

// MARK: - Custom Configuration Data

struct SessionCustomConfig: Codable, Equatable {
    let backgroundSoundId: String?
    let backgroundSoundName: String?
    let binauralBeatId: String?
    let binauralBeatName: String?
    let cueIds: [String]
    let cueNames: [String]
    /// Practice length in minutes (`TimerSessionConfig.minutes`), not wall-clock timer length.
    let practiceDurationMinutes: Int?
    /// Wall-clock session length when intro/tail extend past practice (`TimerSessionConfig.playbackDurationSeconds`).
    let playbackDurationSeconds: Int?
    /// JSON-encoded `[CueSetting]` from the player at session end (triggers, URLs, fractional metadata).
    let cueSettingsSnapshot: Data?

    init(
        backgroundSoundId: String? = nil,
        backgroundSoundName: String? = nil,
        binauralBeatId: String? = nil,
        binauralBeatName: String? = nil,
        cueIds: [String] = [],
        cueNames: [String] = [],
        practiceDurationMinutes: Int? = nil,
        playbackDurationSeconds: Int? = nil,
        cueSettingsSnapshot: Data? = nil
    ) {
        self.backgroundSoundId = backgroundSoundId
        self.backgroundSoundName = backgroundSoundName
        self.binauralBeatId = binauralBeatId
        self.binauralBeatName = binauralBeatName
        self.cueIds = cueIds
        self.cueNames = cueNames
        self.practiceDurationMinutes = practiceDurationMinutes
        self.playbackDurationSeconds = playbackDurationSeconds
        self.cueSettingsSnapshot = cueSettingsSnapshot
    }

    /// Encodes playback timeline for history replay (fractional / AI expanded cues).
    static func encodeCueSettingsSnapshot(_ settings: [CueSetting]) -> Data? {
        try? JSONEncoder().encode(settings)
    }

    /// Decodes snapshot written at session complete; nil if missing or corrupt.
    func decodeCueSettingsSnapshot() -> [CueSetting]? {
        guard let cueSettingsSnapshot else { return nil }
        return try? JSONDecoder().decode([CueSetting].self, from: cueSettingsSnapshot)
    }
}

// MARK: - Session Context

struct SessionContext: Codable, Equatable {
    let timeOfDay: String?        // "morning", "afternoon", "evening", "night"
    let dayOfWeek: Int?           // 1 = Sunday, 7 = Saturday
    let watchConnected: Bool
    let airpodsConnected: Bool
    
    init(
        timeOfDay: String? = nil,
        dayOfWeek: Int? = nil,
        watchConnected: Bool = false,
        airpodsConnected: Bool = false
    ) {
        self.timeOfDay = timeOfDay
        self.dayOfWeek = dayOfWeek
        self.watchConnected = watchConnected
        self.airpodsConnected = airpodsConnected
    }
    
    /// Create from current device state
    static func current() -> SessionContext {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String = {
            switch hour {
            case 5..<12: return "morning"
            case 12..<17: return "afternoon"
            case 17..<21: return "evening"
            default: return "night"
            }
        }()
        
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        
        return SessionContext(
            timeOfDay: timeOfDay,
            dayOfWeek: dayOfWeek,
            watchConnected: PhoneConnectivityManager.shared.isWatchConnected,
            airpodsConnected: false // Could check AVAudioSession route
        )
    }
}

// MARK: - Main Session Model

struct MeditationSession: Codable, Identifiable, Equatable {
    // MARK: - Core Identity
    let id: UUID
    let createdAt: Date
    
    // MARK: - Session Classification
    let sessionType: MeditationSessionType
    let source: MeditationSessionSource
    
    // MARK: - Content Information
    let title: String
    let description: String?
    let practiceId: String?
    let category: String?
    let tags: [String]
    
    // MARK: - Duration Data
    let plannedDurationSeconds: Int
    let actualDurationSeconds: Int
    let completionRate: Double      // 0.0 - 1.0
    let outcome: SessionOutcome
    
    // MARK: - Heart Rate (mutable for late updates)
    var heartRate: SessionHeartRateData?
    
    // MARK: - Custom Configuration
    let customConfig: SessionCustomConfig?
    
    // MARK: - Context
    let context: SessionContext?
    
    // MARK: - Extensible Metadata
    /// Future-proof storage for additional data without model changes
    var metadata: [String: String]
    
    // MARK: - Computed Properties
    
    var hasHeartRateData: Bool {
        heartRate?.hasValidData ?? false
    }
    
    var durationMinutes: Int {
        actualDurationSeconds / 60
    }
    
    var isCompleted: Bool {
        outcome == .completed || outcome == .almostDone
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: createdAt)
    }
    
    var formattedDuration: String {
        let minutes = actualDurationSeconds / 60
        if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(actualDurationSeconds)s"
        }
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sessionType: MeditationSessionType,
        source: MeditationSessionSource,
        title: String,
        description: String? = nil,
        practiceId: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        plannedDurationSeconds: Int,
        actualDurationSeconds: Int,
        completionRate: Double = 1.0,
        outcome: SessionOutcome = .completed,
        heartRate: SessionHeartRateData? = nil,
        customConfig: SessionCustomConfig? = nil,
        context: SessionContext? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sessionType = sessionType
        self.source = source
        self.title = title
        self.description = description
        self.practiceId = practiceId
        self.category = category
        self.tags = tags
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.completionRate = completionRate
        self.outcome = outcome
        self.heartRate = heartRate
        self.customConfig = customConfig
        self.context = context
        self.metadata = metadata
    }
    
    // MARK: - Migration from Legacy SessionRecord
    
    init(from legacy: SessionRecord) {
        self.id = legacy.id
        self.createdAt = legacy.completedAt
        self.sessionType = legacy.sessionType == .practice ? .guided : .custom
        self.source = legacy.sessionType == .practice ? .explore : .timer
        self.title = legacy.title
        self.description = legacy.description
        self.practiceId = legacy.practiceId
        self.category = nil
        self.tags = []
        self.plannedDurationSeconds = legacy.durationSeconds
        self.actualDurationSeconds = legacy.durationSeconds
        self.completionRate = 1.0
        self.outcome = .completed
        
        if legacy.hasHeartRateData {
            self.heartRate = SessionHeartRateData(
                startBPM: legacy.startBPM.map { Double($0) },
                endBPM: legacy.endBPM.map { Double($0) },
                readingCount: 0
            )
        } else {
            self.heartRate = nil
        }
        
        self.customConfig = nil
        self.context = nil
        self.metadata = [:]
    }
}

// MARK: - Summary for AI Context

extension MeditationSession {
    /// Generate a concise summary string suitable for AI context
    func aiSummary() -> String {
        var parts: [String] = []
        
        parts.append("[\(formattedDate)]")
        parts.append(title)
        parts.append("(\(formattedDuration))")
        
        if let hr = heartRate, hr.hasValidData {
            if let start = hr.startBPM, let end = hr.endBPM {
                let change = end - start
                let sign = change >= 0 ? "+" : ""
                parts.append("HR: \(Int(start))->\(Int(end)) (\(sign)\(Int(change)))")
            }
            if let nadir = hr.nadir {
                parts.append("Lowest: \(Int(nadir.bpm)) bpm at \(String(format: "%.1f", nadir.minuteOffset)) min")
            }
        }
        
        if !tags.isEmpty {
            parts.append("tags: \(tags.joined(separator: ","))")
        }
        
        return parts.joined(separator: " ")
    }
}

