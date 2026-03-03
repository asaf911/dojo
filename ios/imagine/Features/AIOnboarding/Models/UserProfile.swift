//
//  UserProfile.swift
//  Dojo
//
//  Stores user profile data collected during AI onboarding and updated over time.
//  Used for personalization of AI-generated meditations.
//

// ⚠️ DEPRECATED: AIOnboarding feature disabled as of January 2026
// This file is preserved for potential future reuse.
// The flow is disabled via hasPendingSteps() always returning false in SenseiOnboardingState.
// Do not add new functionality - this code path is no longer active.

import Foundation

struct UserProfile: Codable {
    
    // MARK: - Identity
    var firstName: String?
    var userId: String?
    
    // MARK: - Meditation Goals (from AI onboarding step 2)
    var goals: [ProfileGoal] = []
    
    // MARK: - Emotional Baseline (from AI onboarding step 3)
    var currentState: [ProfileEmotionalState] = []
    
    // MARK: - Experience Level (from AI onboarding step 5)
    var experienceBackground: [ProfileExperienceType] = []
    var experienceLevel: ProfileExperienceLevel = .unknown
    
    // MARK: - Preferences (from AI onboarding step 6)
    var guidanceStyle: ProfileGuidanceStyle?
    
    // MARK: - Metadata
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var onboardingCompletedAt: Date?
    var onboardingCompletionPercentage: Int = 0
    var firstMeditationGeneratedAt: Date?
    
    // MARK: - Computed Properties
    
    var hasCompletedOnboarding: Bool {
        onboardingCompletedAt != nil
    }
    
    var isEmpty: Bool {
        goals.isEmpty && currentState.isEmpty && experienceBackground.isEmpty && guidanceStyle == nil
    }
    
    /// True if onboarding is complete and first meditation hasn't been generated yet
    var isFirstMeditationPending: Bool {
        hasCompletedOnboarding && firstMeditationGeneratedAt == nil
    }
}

// MARK: - Enums for Type-Safe Values (prefixed with Profile to avoid conflicts)

enum ProfileGoal: String, Codable, CaseIterable {
    case reduceStress = "Reduce stress"
    case sleepBetter = "Sleep better"
    case improveFocus = "Improve focus"
    case boostMood = "Boost mood"
    case spiritualGrowth = "Spiritual growth"
    case buildConsistency = "Build consistency"
    
    var displayName: String { rawValue }
}

enum ProfileEmotionalState: String, Codable, CaseIterable {
    case stressed = "Stressed"
    case tiredOrLow = "Tired or low"
    case distracted = "Distracted"
    case angryOrTense = "Angry or tense"
    case neutral = "Neutral"
    case calmOrEnergized = "Calm or energized"
    
    var displayName: String { rawValue }
}

enum ProfileExperienceType: String, Codable, CaseIterable {
    case calmOrHeadspace = "Calm or Headspace"
    case otherApps = "Other apps"
    case youtubeOrSpotify = "YouTube or Spotify"
    case onMyOwn = "On my own"
    case workshopsAndRetreats = "Workshops and retreats"
    case completelyNew = "I'm completely new"
    
    var displayName: String { rawValue }
}

enum ProfileExperienceLevel: String, Codable {
    case beginner
    case casual
    case intermediate
    case experienced
    case unknown
}

enum ProfileGuidanceStyle: String, Codable, CaseIterable {
    case calmAndSoft = "Calm & soft"
    case directAndClear = "Direct & clear"
    case scientific = "Scientific"
    case spiritual = "Spiritual"
    
    var displayName: String { rawValue }
}

// MARK: - AI Context Generation

extension UserProfile {
    
    /// Builds context for the AI API (invisible to user)
    /// - Parameter userPrompt: Optional user prompt to check if duration is already specified
    func buildContextForAI(userPrompt: String? = nil) -> String {
        guard !isEmpty else { return "" }
        
        var lines: [String] = ["[User Profile]"]
        
        // Goals
        if !goals.isEmpty {
            lines.append("Goals: \(goals.map { $0.displayName }.joined(separator: ", "))")
        }
        
        // Current emotional state
        if !currentState.isEmpty {
            lines.append("Current state: \(currentState.map { $0.displayName }.joined(separator: ", "))")
        }
        
        // Experience
        if !experienceBackground.isEmpty {
            lines.append("Experience: \(experienceBackground.map { $0.displayName }.joined(separator: ", "))")
        }
        
        // Experience level guidance
        switch experienceLevel {
        case .beginner:
            lines.append("Note: User is new to meditation - use simple language, more guidance, shorter silences")
        case .experienced:
            lines.append("Note: Experienced practitioner - comfortable with longer silences, subtle cues")
        case .intermediate, .casual:
            lines.append("Note: Has some experience - familiar with guided format")
        case .unknown:
            break
        }
        
        // Guidance style
        if let style = guidanceStyle {
            lines.append("Preferred style: \(style.displayName)")
        }
        
        // First meditation flag - only suggest duration if user didn't specify one
        let hasDurationSpecified = userPrompt.map { Self.containsDurationSpecification($0) } ?? false
        if !hasDurationSpecified {
            lines.append("Note: This is the user's first meditation. If no duration is specified, consider 5 minutes as a gentle starting point.")
        } else {
            lines.append("Note: This is the user's first meditation.")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Checks if the user prompt contains duration specification
    private static func containsDurationSpecification(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased()
        
        // Check for common duration patterns: "X minute(s)", "X min", "Xm", "X-minute"
        let durationPatterns = [
            try? NSRegularExpression(pattern: #"\b\d+\s*(minute|minutes|min|m)\b"#, options: .caseInsensitive),
            try? NSRegularExpression(pattern: #"\b\d+[- ]minute"#, options: .caseInsensitive)
        ]
        
        for pattern in durationPatterns.compactMap({ $0 }) {
            let range = NSRange(location: 0, length: (lowercased as NSString).length)
            if pattern.firstMatch(in: lowercased, options: [], range: range) != nil {
                return true
            }
        }
        
        return false
    }
    
    /// Logs the profile for debugging
    func logProfile(prefix: String = "") {
        let goalsStr = goals.map { $0.rawValue }.joined(separator: ", ")
        let stateStr = currentState.map { $0.rawValue }.joined(separator: ", ")
        let expStr = experienceBackground.map { $0.rawValue }.joined(separator: ", ")
        let styleStr = guidanceStyle?.rawValue ?? "nil"
        
        logger.aiChat("🧠 AI_DEBUG \(prefix)USER_PROFILE goals=[\(goalsStr)] state=[\(stateStr)] exp=[\(expStr)] level=\(experienceLevel.rawValue) style=\(styleStr) completion=\(onboardingCompletionPercentage)%")
    }
}
