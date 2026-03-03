//
//  DualRecommendationModels.swift
//  imagine
//
//  Created for Dual Recommendation System
//
//  Data models for the dual recommendation system that displays
//  both primary and secondary session options in the AI chat.
//

import Foundation

// MARK: - Recommendation Type

/// The type of session being recommended
enum RecommendationType: Equatable {
    case path(PathStep)
    case explore(AudioFile)
    case custom(AITimerResponse)
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .path: return "Path Step"
        case .explore: return "Daily Routine"
        case .custom: return "Custom"
        }
    }
    
    /// Analytics type identifier
    var analyticsType: String {
        switch self {
        case .path: return "path_step"
        case .explore: return "daily_routine"
        case .custom: return "custom_meditation"
        }
    }
    
    // MARK: - Equatable
    
    static func == (lhs: RecommendationType, rhs: RecommendationType) -> Bool {
        switch (lhs, rhs) {
        case (.path(let l), .path(let r)): return l.id == r.id
        case (.explore(let l), .explore(let r)): return l.id == r.id
        case (.custom(let l), .custom(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - Recommendation Item

/// A single recommendation with its intro message
struct RecommendationItem: Equatable {
    let type: RecommendationType
    let introMessage: String
    /// Optional greeting shown before all other text (bold purple style on first welcome)
    let welcomeGreeting: String?
    /// When true, the greeting is the first-ever welcome (bold purple style).
    /// When false, it's a timely greeting (regular sensei text style).
    let isFirstWelcome: Bool
    /// Optional contextual message shown after the welcome greeting and before the intro.
    /// Only present on the very first recommendation; explains *why* this meditation
    /// was chosen, referencing the user's hurdle in natural language.
    let contextMessage: String?
    
    init(
        type: RecommendationType,
        introMessage: String,
        welcomeGreeting: String? = nil,
        isFirstWelcome: Bool = false,
        contextMessage: String? = nil
    ) {
        self.type = type
        self.introMessage = introMessage
        self.welcomeGreeting = welcomeGreeting
        self.isFirstWelcome = isFirstWelcome
        self.contextMessage = contextMessage
    }
    
    // MARK: - Convenience Accessors
    
    /// Get the PathStep if this is a path recommendation
    var pathStep: PathStep? {
        if case .path(let step) = type { return step }
        return nil
    }
    
    /// Get the AudioFile if this is an explore recommendation
    var audioFile: AudioFile? {
        if case .explore(let file) = type { return file }
        return nil
    }
    
    /// Get the AITimerResponse if this is a custom recommendation
    var customMeditation: AITimerResponse? {
        if case .custom(let meditation) = type { return meditation }
        return nil
    }
    
    /// Check if this is a path recommendation
    var isPath: Bool {
        if case .path = type { return true }
        return false
    }
    
    /// Check if this is an explore recommendation
    var isExplore: Bool {
        if case .explore = type { return true }
        return false
    }
    
    /// Check if this is a custom recommendation
    var isCustom: Bool {
        if case .custom = type { return true }
        return false
    }
    
    /// Content ID for analytics
    var contentId: String {
        switch type {
        case .path(let step): return step.id
        case .explore(let file): return file.id
        case .custom(let meditation): return meditation.meditationConfiguration.id.uuidString
        }
    }
    
    /// Content title for display
    var contentTitle: String {
        switch type {
        case .path(let step): return step.title
        case .explore(let file): return file.title
        case .custom(let meditation): return meditation.meditationConfiguration.title ?? "Custom Meditation"
        }
    }
}

// MARK: - Routine Progress

/// Progress through daily routines (for UI display and unlock logic)
struct RoutineProgress: Equatable, Codable {
    let completed: Int
    let required: Int  // Always 3
    
    /// Check if user is one routine away from unlock
    var isLastRoutineBeforeUnlock: Bool {
        completed == required - 1  // 2 of 3
    }
    
    /// Check if customization is unlocked
    var isCustomizationUnlocked: Bool {
        completed >= required
    }
    
    /// Progress text for display
    var progressText: String {
        "\(completed)/\(required) routines"
    }
    
    /// Progress percentage (0.0 to 1.0)
    var progressPercentage: Double {
        guard required > 0 else { return 0 }
        return min(1.0, Double(completed) / Double(required))
    }
}

// MARK: - Dual Recommendation

/// The combined result with primary and optional secondary recommendation
struct DualRecommendation: Equatable {
    let primary: RecommendationItem
    let secondary: RecommendationItem?
    /// The two-state mode that determined role assignment for this recommendation.
    let userMode: UserMode
    /// Retained for analytics event tagging. Not used for recommendation logic.
    let currentPhase: JourneyPhase
    let routineProgress: RoutineProgress?
    
    /// Whether we have both recommendations
    var hasBothOptions: Bool {
        secondary != nil
    }
    
    /// Convenience: primary content ID for analytics
    var primaryContentId: String {
        primary.contentId
    }
    
    /// Convenience: secondary content ID for analytics (or "none")
    var secondaryContentId: String {
        secondary?.contentId ?? "none"
    }
}

// MARK: - Codable Conformance

// DualRecommendation needs Codable for persistence in ChatMessage
extension DualRecommendation: Codable {
    enum CodingKeys: String, CodingKey {
        case primary, secondary, userMode, currentPhase, routineProgress
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try container.decode(RecommendationItem.self, forKey: .primary)
        secondary = try container.decodeIfPresent(RecommendationItem.self, forKey: .secondary)
        // Decode userMode with a fallback for records persisted before this field existed.
        // Old records had no userMode; infer it from the phase they stored.
        if let mode = try? container.decode(UserMode.self, forKey: .userMode) {
            userMode = mode
        } else {
            let phase = (try? container.decode(JourneyPhase.self, forKey: .currentPhase)) ?? .path
            userMode = UserMode.from(phase: phase) ?? .learn
        }
        currentPhase = try container.decode(JourneyPhase.self, forKey: .currentPhase)
        routineProgress = try container.decodeIfPresent(RoutineProgress.self, forKey: .routineProgress)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primary, forKey: .primary)
        try container.encodeIfPresent(secondary, forKey: .secondary)
        try container.encode(userMode, forKey: .userMode)
        try container.encode(currentPhase, forKey: .currentPhase)
        try container.encodeIfPresent(routineProgress, forKey: .routineProgress)
    }
}

extension RecommendationItem: Codable {
    enum CodingKeys: String, CodingKey {
        case type, introMessage, welcomeGreeting, isFirstWelcome, contextMessage
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(RecommendationType.self, forKey: .type)
        introMessage = try container.decode(String.self, forKey: .introMessage)
        welcomeGreeting = try container.decodeIfPresent(String.self, forKey: .welcomeGreeting)
        isFirstWelcome = try container.decodeIfPresent(Bool.self, forKey: .isFirstWelcome) ?? false
        contextMessage = try container.decodeIfPresent(String.self, forKey: .contextMessage)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(introMessage, forKey: .introMessage)
        try container.encodeIfPresent(welcomeGreeting, forKey: .welcomeGreeting)
        try container.encode(isFirstWelcome, forKey: .isFirstWelcome)
        try container.encodeIfPresent(contextMessage, forKey: .contextMessage)
    }
}

extension RecommendationType: Codable {
    enum CodingKeys: String, CodingKey {
        case type, pathStep, audioFile, customMeditation
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        
        switch typeString {
        case "path":
            let step = try container.decode(PathStep.self, forKey: .pathStep)
            self = .path(step)
        case "explore":
            let file = try container.decode(AudioFile.self, forKey: .audioFile)
            self = .explore(file)
        case "custom":
            let meditation = try container.decode(AITimerResponse.self, forKey: .customMeditation)
            self = .custom(meditation)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown recommendation type: \(typeString)")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .path(let step):
            try container.encode("path", forKey: .type)
            try container.encode(step, forKey: .pathStep)
        case .explore(let file):
            try container.encode("explore", forKey: .type)
            try container.encode(file, forKey: .audioFile)
        case .custom(let meditation):
            try container.encode("custom", forKey: .type)
            try container.encode(meditation, forKey: .customMeditation)
        }
    }
}
