//
//  SessionAnalyticsModels.swift
//  Dojo
//
//  Core enums for the unified meditation analytics system.
//  These define the three-dimensional tracking: WHERE, WHAT, and WHO.
//

import Foundation

// MARK: - Entry Point (WHERE)

/// Where the user initiated the meditation session from.
/// This tracks the screen/feature where the user tapped to start.
enum SessionEntryPoint: String, Codable, CaseIterable {
    case aiChat = "ai_chat"                     // Started from AI/Dojo chat screen
    case pathScreen = "path_screen"             // Started from Path tab/journey view
    case exploreScreen = "explore_screen"       // Started from Explore/library
    case createScreen = "create_screen"         // Started from Create (meditation customization) screen
    case postPracticeRec = "post_practice_rec"  // Started from post-practice recommendation
    case deepLink = "deep_link"                 // Started from external link
    case notification = "notification"          // Started from push notification
    case unknown = "unknown"                    // Fallback for edge cases
}

// MARK: - Content Type (WHAT)

/// What type of meditation content is being played.
enum SessionContentType: String, Codable, CaseIterable {
    case preRecorded = "pre_recorded"           // Library meditation (AudioFile-based)
    case pathStep = "path_step"                 // Learning Path step (lesson or practice)
    case customMeditation = "custom_meditation" // Customized meditation with selected parameters
}

// MARK: - Content Origin (WHO)

/// Who selected or created the meditation content.
enum SessionContentOrigin: String, Codable, CaseIterable {
    case userSelected = "user_selected"         // User browsed and picked, OR built from scratch
    case aiRecommended = "ai_recommended"       // AI suggested existing content, OR generated config
}

// MARK: - AI Customization Level (MODIFICATION)

/// Level of AI involvement and whether user modified the AI's suggestion.
enum AICustomizationLevel: String, Codable, CaseIterable {
    case none = "none"           // No AI involvement at all
    case suggested = "suggested" // AI created/recommended, user accepted as-is
    case modified = "modified"   // AI created initial version, user made changes before playing
}

// MARK: - Session Outcome

/// Final outcome of the meditation session.
enum SessionOutcomeType: String, Codable, CaseIterable {
    case completed = "completed"   // Finished 100%
    case partial = "partial"       // Finished 75%+ but not 100%
    case abandoned = "abandoned"   // Stopped early (<75%)
    
    /// Determine outcome from progress percentage
    static func from(progressPercent: Int) -> SessionOutcomeType {
        if progressPercent >= 100 {
            return .completed
        } else if progressPercent >= 75 {
            return .partial
        } else {
            return .abandoned
        }
    }
}

// MARK: - Session Event Types

/// Unified session event names for analytics.
enum SessionEventType: String {
    case sessionStart = "session_start"
    case sessionProgress = "session_progress"
    case sessionComplete = "session_complete"
    case sessionAborted = "session_aborted"
    case sessionRated = "session_rated"
}

// MARK: - Recommendation Position

/// Position of the recommendation when multiple options are shown by the Sensei.
/// Tracks whether user selected the primary or secondary suggestion.
enum RecommendationPosition: String, Codable, CaseIterable {
    case primary = "primary"       // Main/featured recommendation (shown first)
    case secondary = "secondary"   // Alternative option (shown second)
    case single = "single"         // Only one option shown (no dual recommendation)
    case none = "none"             // Not from a recommendation (user browsed/selected directly)
}

// MARK: - Recommendation Trigger (WHY)

/// Why the recommendation was shown — distinguishes automatic timely suggestions
/// from post-practice follow-ups and journey transitions.
enum RecommendationTrigger: String, Codable, CaseIterable {
    case timely = "timely"                 // Automatic time-slot recommendation (morning/noon/evening/night)
    case postPractice = "post_practice"    // User said "Yes" to the post-session prompt
    case transition = "transition"         // Journey phase transition (e.g. path complete → daily routines)
    case none = "none"                     // Not from a recommendation (user browsed, typed prompt, etc.)
}

// MARK: - Progress Milestones

/// Standard progress milestones that trigger session_progress events.
enum ProgressMilestone: Int, CaseIterable {
    case twentyFive = 25
    case fifty = 50
    case seventyFive = 75
    case ninetyFive = 95
}
