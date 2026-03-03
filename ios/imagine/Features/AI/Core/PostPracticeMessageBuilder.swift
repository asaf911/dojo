import Foundation

// MARK: - Session Type

/// Represents the type of meditation session with associated context
enum PostSessionType {
    /// Pre-recorded Explore meditation
    case explore(file: AudioFile)
    /// Path step meditation (structured learning)
    case path(stepId: String, step: PathStep?, nextStep: PathStep?, isPathComplete: Bool)
    /// Custom/Timer meditation (AI-generated)
    case custom(title: String?, description: String?)
    
    /// Returns a display title for the session if available
    var displayTitle: String? {
        switch self {
        case .explore(let file):
            return file.title
        case .path(_, let step, _, _):
            return step?.title
        case .custom(let title, _):
            return title
        }
    }
}

// MARK: - Input Models

struct PostPracticeMessageInput {
    let sessionId: String
    let firstName: String?
    let durationMinutes: Int?
    let streak: StreakManager.StreakDisplayData
    let heartRate: HeartRateContext?
    let heartRateSamples: [HeartRateSamplePoint]?
    let createdAt: TimeInterval
    let sessionType: PostSessionType
}

struct HeartRateContext {
    enum Quality {
        case valid(start: Int, end: Int, changePercent: Double)  // 2+ samples - can show graph
        case minimal(avgBPM: Int)                                 // 1 sample - show average only
        case partial                                              // Data exists but unusable
        case none
    }

    let quality: Quality
    
    /// Creates HeartRateContext from HeartRateResults
    static func from(_ results: HeartRateResults) -> HeartRateContext? {
        let hrEnabled = SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false)
        guard hrEnabled else { return nil }
        
        // 2+ samples: can compute start/end and show graph
        if results.hasValidData {
            let start = Int(round(results.firstThreeAverage))
            let end = Int(round(results.lastThreeAverage))
            let pct = results.heartRateChange
            return HeartRateContext(quality: .valid(start: start, end: end, changePercent: pct))
        }
        
        // 1 sample: show average BPM (no graph)
        if results.hasMinimalData {
            let avg = Int(round(results.firstThreeAverage))
            return HeartRateContext(quality: .minimal(avgBPM: avg))
        }
        
        if results.hasAnyData {
            return HeartRateContext(quality: .partial)
        }
        
        return HeartRateContext(quality: .none)
    }
    
    /// Extracts heart rate samples from HeartRateResults if valid for graphing
    static func samplesFrom(_ results: HeartRateResults) -> [HeartRateSamplePoint]? {
        let hrEnabled = SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false)
        guard hrEnabled else { return nil }
        
        // Need at least 2 samples to draw a graph line
        guard results.samples.count >= 2 else { return nil }
        return results.samples
    }
}

struct PostPracticePolishContext {
    let firstName: String?
    let durationMinutes: Int?
    let streak: Int
    let longestStreak: Int
    let isNewRecord: Bool
    let heartRateStartBPM: Int?
    let heartRateEndBPM: Int?
    let heartRateChangePercent: Double?
    
    // Session type context for personalized polish
    let sessionContext: SessionContext?
    
    /// Context about the meditation session type
    enum SessionContext {
        case path(stepTitle: String?, stepOrder: Int?, isPathComplete: Bool)
        case explore(meditationTitle: String?)
        case custom(title: String?)
    }
}

// MARK: - Builder

enum PostPracticeMessageBuilder {
    
    /// Builds a structured post-practice report with separate content sections
    static func buildReport(from input: PostPracticeMessageInput) -> (report: PostPracticeReport, polishContext: PostPracticePolishContext) {
        // Build each section separately for flexible display
        let completionPraise = buildCompletionPraise(
            sessionType: input.sessionType,
            firstName: input.firstName,
            durationMinutes: input.durationMinutes
        )
        
        let streakMessage = buildStreakMessage(from: input.streak)
        
        let (hrStart, hrEnd, hrChange, heartRateMessage) = buildHeartRateMessage(from: input.heartRate)
        
        // Extract Path-specific metadata
        let (completedPathStepId, nextPathStepId, isPathComplete) = extractPathMetadata(from: input.sessionType)

        let metadata = PostPracticeReport.Metadata(
            durationMinutes: input.durationMinutes,
            userFirstName: input.firstName,
            currentStreak: input.streak.currentStreak,
            longestStreak: input.streak.longestStreak,
            isNewRecord: input.streak.isNewRecord,
            heartRateSamples: input.heartRateSamples,
            heartRateStartBPM: hrStart,
            heartRateEndBPM: hrEnd,
            heartRateChangePercent: hrChange,
            expectsPolish: true,  // Always polish all sessions
            completedPathStepId: completedPathStepId,
            nextPathStepId: nextPathStepId,
            isPathComplete: isPathComplete
        )

        let report = PostPracticeReport(
            sessionId: input.sessionId,
            createdAt: input.createdAt,
            status: .readyFallback,
            bubbleId: nil,
            completionPraise: completionPraise,
            streakMessage: streakMessage,
            heartRateMessage: heartRateMessage,
            metadata: metadata
        )

        // Build session context for polish
        let sessionContext = buildSessionContext(from: input.sessionType)
        
        // Always create polish context for AI enhancement
        let polishContext = PostPracticePolishContext(
            firstName: input.firstName,
            durationMinutes: input.durationMinutes,
            streak: input.streak.currentStreak,
            longestStreak: input.streak.longestStreak,
            isNewRecord: input.streak.isNewRecord,
            heartRateStartBPM: hrStart,
            heartRateEndBPM: hrEnd,
            heartRateChangePercent: hrChange,
            sessionContext: sessionContext
        )

        return (report, polishContext)
    }
    
    /// Extracts Path-specific metadata from session type
    private static func extractPathMetadata(from sessionType: PostSessionType) -> (completedStepId: String?, nextStepId: String?, isComplete: Bool) {
        switch sessionType {
        case .path(let stepId, _, let nextStep, let isPathComplete):
            return (stepId, nextStep?.id, isPathComplete)
        case .explore, .custom:
            return (nil, nil, false)
        }
    }
    
    /// Builds session context for polish service
    private static func buildSessionContext(from sessionType: PostSessionType) -> PostPracticePolishContext.SessionContext? {
        switch sessionType {
        case .path(_, let step, _, let isPathComplete):
            return .path(stepTitle: step?.title, stepOrder: step?.order, isPathComplete: isPathComplete)
        case .explore(let file):
            return .explore(meditationTitle: file.title)
        case .custom(let title, _):
            return .custom(title: title)
        }
    }
    
    // MARK: - Section Builders

    /// Builds the completion praise message based on session type
    /// SHORT messages only (~40-50 chars max)
    private static func buildCompletionPraise(sessionType: PostSessionType, firstName: String?, durationMinutes: Int?) -> String {
        // Handle Path completion specially
        if case .path(_, let step, _, let isPathComplete) = sessionType {
            return buildPathCompletionPraise(step: step, firstName: firstName, isPathComplete: isPathComplete)
        }
        
        let title = sessionType.displayTitle

        // Keep messages SHORT (~40 chars)
        if let name = firstName, let sessionTitle = title {
            return "\(name), \"\(sessionTitle)\" done."
        } else if let sessionTitle = title {
            return "\"\(sessionTitle)\" complete."
        } else if let name = firstName {
            return "\(name), nice practice."
        } else {
            return "Nice practice."
        }
    }
    
    /// Builds Path-specific completion praise with step information
    /// SHORT messages only (~40-50 chars max)
    private static func buildPathCompletionPraise(step: PathStep?, firstName: String?, isPathComplete: Bool) -> String {
        // Path complete - celebration (warm but concise)
        if isPathComplete {
            if let name = firstName {
                return "\(name), you've completed the Path — well done."
            }
            return "You've completed the Path — well done."
        }
        
        // Regular step completion
        guard let step = step else {
            return firstName != nil ? "\(firstName!), step done." : "Step done."
        }
        
        if let name = firstName {
            return "\(name), Step \(step.order) done."
        }
        return "Step \(step.order): \(step.title) done."
    }

    /// Builds the streak information message
    /// ~40-50 chars, include "streak" word for clarity
    private static func buildStreakMessage(from streak: StreakManager.StreakDisplayData) -> String {
        let current = streak.currentStreak
        let longest = streak.longestStreak
        let daysToRecord = max(0, longest - current)

        if streak.isNewRecord {
            return "🔥 New record! \(current) day streak."
        }
        if daysToRecord == 0 {
            return "🔥 \(current) day streak — matches your best!"
        }
        if daysToRecord == 1 {
            return "🔥 \(current) day streak — 1 more beats your record!"
        }
        if current == 1 {
            return "🔥 Day 1 of your streak — keep going!"
        }
        return "🔥 \(current) day streak — \(daysToRecord) more to beat your record."
    }

    /// Builds the heart rate analysis message (shown after graph)
    /// ~40-50 chars, sound human and warm
    /// Returns: (startBPM, endBPM, changePercent, message)
    private static func buildHeartRateMessage(from context: HeartRateContext?) -> (start: Int?, end: Int?, change: Double?, message: String?) {
        guard let context else {
            return (nil, nil, nil, nil)
        }

        switch context.quality {
        case .none:
            return (nil, nil, nil, "❤️ HR data unavailable.")
        case .partial:
            return (nil, nil, nil, "❤️ Not enough HR samples collected.")
        case .minimal(let avgBPM):
            // Single reading - show as average, no change percent
            return (avgBPM, avgBPM, 0, "❤️ Average HR: \(avgBPM) BPM during session.")
        case .valid(let start, let end, let change):
            let message = buildValidHeartRateAnalysis(start: start, end: end, change: change)
            return (start, end, change, message)
        }
    }

    /// Builds the heart rate analysis text for valid data
    /// ~40-50 chars, sound human and warm
    private static func buildValidHeartRateAnalysis(start: Int, end: Int, change: Double) -> String {
        let startSafe = max(0, start)
        let endSafe = max(0, end)
        guard startSafe > 0, endSafe > 0 else {
            return "❤️ HR data unavailable."
        }

        let absolute = abs(change)

        if absolute < 3.0 {
            return "❤️ HR stayed steady around \(startSafe) BPM."
        }

        if change < 0 {
            if absolute >= 10.0 {
                return "❤️ HR dropped from \(startSafe) to \(endSafe). Nice!"
            }
            return "❤️ HR eased from \(startSafe) to \(endSafe) BPM."
        }

        return "❤️ HR rose from \(startSafe) to \(endSafe) BPM."
    }
}
