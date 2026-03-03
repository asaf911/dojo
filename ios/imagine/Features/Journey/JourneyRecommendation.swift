//
//  JourneyRecommendation.swift
//  imagine
//
//  Created by Cursor on 1/14/26.
//
//  Defines the recommendation types that can be shown to users
//  based on their current journey phase.
//

import Foundation

// MARK: - Journey Recommendation

/// Represents a recommendation to show the user based on their journey phase.
/// Each case contains the data needed to display the recommendation in the AI chat.
enum JourneyRecommendation {
    
    /// Path step recommendation - shown during the Path phase
    /// - Parameters:
    ///   - step: The PathStep to recommend
    ///   - message: The Sensei message introducing the step
    ///   - welcomeGreeting: Optional personalized welcome (only for first step)
    case path(step: PathStep, message: String, welcomeGreeting: String?)
    
    /// Daily routine recommendation - shown after Path completion
    /// - Parameters:
    ///   - session: The AudioFile to recommend (time-based routine)
    ///   - message: The contextual message based on time of day
    ///   - timeOfDay: The current time period (morning, noon, evening, night)
    case dailyRoutine(session: AudioFile, message: String, timeOfDay: String)
    
    /// Custom AI meditation recommendation (future implementation)
    /// - Parameters:
    ///   - meditation: The AI-generated meditation response
    ///   - message: The personalized message
    case custom(meditation: AITimerResponse, message: String)
    
    // MARK: - Properties
    
    /// The journey phase this recommendation belongs to
    var phase: JourneyPhase {
        switch self {
        case .path: return .path
        case .dailyRoutine: return .dailyRoutines
        case .custom: return .customization
        }
    }
    
    /// Unique identifier for the recommended content
    var contentId: String {
        switch self {
        case .path(let step, _, _):
            return step.id
        case .dailyRoutine(let session, _, _):
            return session.id
        case .custom(let meditation, _):
            return meditation.meditationConfiguration.id.uuidString
        }
    }
    
    /// Title of the recommended content
    var contentTitle: String {
        switch self {
        case .path(let step, _, _):
            return step.title
        case .dailyRoutine(let session, _, _):
            return session.title
        case .custom(let meditation, _):
            return meditation.meditationConfiguration.title ?? "Custom Meditation"
        }
    }
    
    /// The message to display with the recommendation
    var displayMessage: String {
        switch self {
        case .path(_, let message, _):
            return message
        case .dailyRoutine(_, let message, _):
            return message
        case .custom(_, let message):
            return message
        }
    }
    
    /// Content type for analytics
    var contentType: String {
        switch self {
        case .path: return "path_step"
        case .dailyRoutine: return "daily_routine"
        case .custom: return "custom_meditation"
        }
    }
}
