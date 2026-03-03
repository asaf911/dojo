//
//  SessionContextManager.swift
//  Dojo
//
//  Single source of truth for current meditation session context.
//  Set BEFORE navigating to player, cleared after session ends.
//

import Foundation

// MARK: - Debug Logging

private let ANALYTICS_TAG = "📊 ANALYTICS:"

private func analyticsLog(_ message: String) {
    print("\(ANALYTICS_TAG) [SessionContext] \(message)")
}

// MARK: - Analytics Session Context

/// Complete context for a meditation session analytics tracking.
/// Named AnalyticsSessionContext to avoid conflict with MeditationSession.SessionContext.
struct AnalyticsSessionContext {
    // Session identifier (shared across session_start, session_complete, heart_rate_session_complete)
    let sessionId: String
    
    // Core dimensions
    let entryPoint: SessionEntryPoint
    let contentType: SessionContentType
    let contentOrigin: SessionContentOrigin
    var aiCustomizationLevel: AICustomizationLevel
    
    // Recommendation tracking
    let recommendationPosition: RecommendationPosition
    let recommendationTrigger: RecommendationTrigger
    
    // Content identifiers
    let practiceId: String?
    let practiceTitle: String
    let plannedDurationMinutes: Int
    
    // Category and tags (for pre-recorded and path)
    let category: String?
    let tags: [String]
    
    // Path-specific
    let pathStepOrder: Int?
    let isPathLesson: Bool?
    
    // Custom meditation config
    var customConfig: CustomMeditationConfig?
    
    // Timestamps
    let createdAt: Date
    
    // MARK: - Computed Properties
    
    var aiInvolved: Bool {
        contentOrigin == .aiRecommended
    }
}

// MARK: - Session Context Manager

/// Singleton manager for tracking current session context.
/// Entry points set context before navigation, players read context for analytics.
final class SessionContextManager {
    static let shared = SessionContextManager()
    
    // MARK: - Current Context
    
    private(set) var currentContext: AnalyticsSessionContext?
    
    /// Cached journey phase and track for session analytics (updated by ProductJourneyManager).
    /// Enables session_start/complete to include journey context without MainActor dependency.
    private(set) var cachedJourneyPhaseName: String?
    private(set) var cachedJourneyTrack: String?
    
    private init() {}
    
    /// Update journey cache for session analytics. Call from ProductJourneyManager when phase changes.
    func updateJourneyCache(phaseName: String, track: String) {
        cachedJourneyPhaseName = phaseName
        cachedJourneyTrack = track
    }
    
    // MARK: - Setup Methods
    
    /// Setup context for a pre-recorded library meditation.
    /// - Parameters:
    ///   - entryPoint: Where the user initiated from
    ///   - audioFile: The AudioFile being played
    ///   - origin: Whether user selected or AI recommended
    ///   - recommendationPosition: Position in dual recommendation (primary/secondary/single/none)
    func setupLibrarySession(
        entryPoint: SessionEntryPoint,
        audioFile: AudioFile,
        origin: SessionContentOrigin,
        recommendationPosition: RecommendationPosition = .none,
        recommendationTrigger: RecommendationTrigger = .none
    ) {
        let durationMinutes = audioFile.durations.first?.length ?? 0
        
        currentContext = AnalyticsSessionContext(
            sessionId: UUID().uuidString,
            entryPoint: entryPoint,
            contentType: .preRecorded,
            contentOrigin: origin,
            aiCustomizationLevel: origin == .aiRecommended ? .suggested : .none,
            recommendationPosition: recommendationPosition,
            recommendationTrigger: recommendationTrigger,
            practiceId: audioFile.id,
            practiceTitle: audioFile.title,
            plannedDurationMinutes: durationMinutes,
            category: audioFile.category.rawValue,
            tags: audioFile.tags,
            pathStepOrder: nil,
            isPathLesson: nil,
            customConfig: nil,
            createdAt: Date()
        )
        
        analyticsLog("✅ SETUP LIBRARY SESSION")
        analyticsLog("   → Entry Point: \(entryPoint.rawValue)")
        analyticsLog("   → Content Type: pre_recorded")
        analyticsLog("   → Content Origin: \(origin.rawValue)")
        analyticsLog("   → Recommendation Position: \(recommendationPosition.rawValue)")
        analyticsLog("   → Recommendation Trigger: \(recommendationTrigger.rawValue)")
        analyticsLog("   → Practice ID: \(audioFile.id)")
        analyticsLog("   → Title: \(audioFile.title)")
        analyticsLog("   → Duration: \(durationMinutes) min")
        analyticsLog("   → Category: \(audioFile.category.rawValue)")
        logger.eventMessage("SessionContextManager: Setup library session - entry=\(entryPoint.rawValue), origin=\(origin.rawValue), position=\(recommendationPosition.rawValue), trigger=\(recommendationTrigger.rawValue), practice=\(audioFile.id)")
    }
    
    /// Setup context for a Path step.
    /// - Parameters:
    ///   - entryPoint: Where the user initiated from
    ///   - pathStep: The PathStep being played
    ///   - origin: Whether user selected or AI recommended
    ///   - recommendationPosition: Position in dual recommendation (primary/secondary/single/none)
    func setupPathSession(
        entryPoint: SessionEntryPoint,
        pathStep: PathStep,
        origin: SessionContentOrigin,
        recommendationPosition: RecommendationPosition = .none,
        recommendationTrigger: RecommendationTrigger = .none
    ) {
        currentContext = AnalyticsSessionContext(
            sessionId: UUID().uuidString,
            entryPoint: entryPoint,
            contentType: .pathStep,
            contentOrigin: origin,
            aiCustomizationLevel: origin == .aiRecommended ? .suggested : .none,
            recommendationPosition: recommendationPosition,
            recommendationTrigger: recommendationTrigger,
            practiceId: pathStep.id,
            practiceTitle: pathStep.title,
            plannedDurationMinutes: pathStep.duration,
            category: "path",
            tags: ["path"],
            pathStepOrder: pathStep.order,
            isPathLesson: pathStep.isLesson,
            customConfig: nil,
            createdAt: Date()
        )
        
        analyticsLog("✅ SETUP PATH SESSION")
        analyticsLog("   → Entry Point: \(entryPoint.rawValue)")
        analyticsLog("   → Content Type: path_step")
        analyticsLog("   → Content Origin: \(origin.rawValue)")
        analyticsLog("   → Recommendation Position: \(recommendationPosition.rawValue)")
        analyticsLog("   → Recommendation Trigger: \(recommendationTrigger.rawValue)")
        analyticsLog("   → Step ID: \(pathStep.id)")
        analyticsLog("   → Step Title: \(pathStep.title)")
        analyticsLog("   → Step Order: \(pathStep.order)")
        analyticsLog("   → Duration: \(pathStep.duration) min")
        analyticsLog("   → Is Lesson: \(pathStep.isLesson)")
        logger.eventMessage("SessionContextManager: Setup path session - entry=\(entryPoint.rawValue), origin=\(origin.rawValue), position=\(recommendationPosition.rawValue), trigger=\(recommendationTrigger.rawValue), step=\(pathStep.id), order=\(pathStep.order)")
    }
    
    /// Setup context for a custom meditation.
    /// - Parameters:
    ///   - entryPoint: Where the user initiated from (ai_chat or create_screen)
    ///   - config: The meditation configuration
    ///   - origin: Whether user created or AI generated
    ///   - customizationLevel: Level of AI involvement
    ///   - recommendationPosition: Position in dual recommendation (primary/secondary/single/none)
    ///   - title: Optional title for the meditation (from AI or user)
    func setupCustomMeditationSession(
        entryPoint: SessionEntryPoint,
        config: CustomMeditationConfig,
        origin: SessionContentOrigin,
        customizationLevel: AICustomizationLevel,
        recommendationPosition: RecommendationPosition = .none,
        recommendationTrigger: RecommendationTrigger = .none,
        title: String? = nil
    ) {
        let practiceTitle = title ?? "Custom Meditation"
        currentContext = AnalyticsSessionContext(
            sessionId: UUID().uuidString,
            entryPoint: entryPoint,
            contentType: .customMeditation,
            contentOrigin: origin,
            aiCustomizationLevel: customizationLevel,
            recommendationPosition: recommendationPosition,
            recommendationTrigger: recommendationTrigger,
            practiceId: nil,
            practiceTitle: practiceTitle,
            plannedDurationMinutes: config.durationMinutes,
            category: nil,
            tags: [],
            pathStepOrder: nil,
            isPathLesson: nil,
            customConfig: config,
            createdAt: Date()
        )
        
        analyticsLog("✅ SETUP CUSTOM MEDITATION SESSION")
        analyticsLog("   → Entry Point: \(entryPoint.rawValue)")
        analyticsLog("   → Content Type: custom_meditation")
        analyticsLog("   → Content Origin: \(origin.rawValue)")
        analyticsLog("   → AI Customization Level: \(customizationLevel.rawValue)")
        analyticsLog("   → Recommendation Position: \(recommendationPosition.rawValue)")
        analyticsLog("   → Recommendation Trigger: \(recommendationTrigger.rawValue)")
        analyticsLog("   → Title: \(practiceTitle)")
        analyticsLog("   → Duration: \(config.durationMinutes) min")
        analyticsLog("   → Background Sound: \(config.backgroundSound?.name ?? "none")")
        analyticsLog("   → Binaural Beat: \(config.binauralBeat?.name ?? "none")")
        analyticsLog("   → Cues Count: \(config.cues.count)")
        let deeplinkURL = config.generateDeeplinkURL()
        analyticsLog("   → Deeplink URL: \(deeplinkURL)")
        logger.eventMessage("SessionContextManager: Setup custom meditation - entry=\(entryPoint.rawValue), origin=\(origin.rawValue), level=\(customizationLevel.rawValue), position=\(recommendationPosition.rawValue), trigger=\(recommendationTrigger.rawValue), title=\(practiceTitle), duration=\(config.durationMinutes)min")
    }
    
    /// Setup context for a custom meditation from TimerSessionConfig.
    /// Convenience method that creates CustomMeditationConfig internally.
    func setupCustomMeditationSession(
        entryPoint: SessionEntryPoint,
        timerConfig: TimerSessionConfig,
        origin: SessionContentOrigin,
        customizationLevel: AICustomizationLevel,
        recommendationPosition: RecommendationPosition = .none,
        recommendationTrigger: RecommendationTrigger = .none
    ) {
        let config = CustomMeditationConfig(from: timerConfig)
        setupCustomMeditationSession(
            entryPoint: entryPoint,
            config: config,
            origin: origin,
            customizationLevel: customizationLevel,
            recommendationPosition: recommendationPosition,
            recommendationTrigger: recommendationTrigger,
            title: timerConfig.title
        )
    }
    
    // MARK: - Modification Tracking
    
    /// Mark that the user modified an AI-generated configuration.
    /// Call this when user changes parameters in the Create screen after AI suggested.
    func markUserModified(newConfig: CustomMeditationConfig) {
        guard var context = currentContext else {
            logger.warnMessage("SessionContextManager: markUserModified called but no context exists")
            return
        }
        
        // Update to modified level and new config
        context.aiCustomizationLevel = .modified
        context.customConfig = newConfig
        currentContext = context
        
        analyticsLog("🔄 MARKED AS USER-MODIFIED")
        analyticsLog("   → Previous Level: \(context.aiCustomizationLevel.rawValue)")
        analyticsLog("   → New Level: modified")
        analyticsLog("   → New Duration: \(newConfig.durationMinutes) min")
        logger.eventMessage("SessionContextManager: Marked as user-modified with new config")
    }
    
    /// Mark that the user modified an AI-generated configuration (from TimerSessionConfig).
    func markUserModified(timerConfig: TimerSessionConfig) {
        let newConfig = CustomMeditationConfig(from: timerConfig)
        markUserModified(newConfig: newConfig)
    }
    
    /// Update the entry point (e.g., when navigating from AI chat to Create screen).
    func updateEntryPoint(_ newEntryPoint: SessionEntryPoint) {
        guard let context = currentContext else {
            logger.warnMessage("SessionContextManager: updateEntryPoint called but no context exists")
            return
        }
        
        // Create new context with updated entry point (preserve sessionId)
        currentContext = AnalyticsSessionContext(
            sessionId: context.sessionId,
            entryPoint: newEntryPoint,
            contentType: context.contentType,
            contentOrigin: context.contentOrigin,
            aiCustomizationLevel: context.aiCustomizationLevel,
            recommendationPosition: context.recommendationPosition,
            recommendationTrigger: context.recommendationTrigger,
            practiceId: context.practiceId,
            practiceTitle: context.practiceTitle,
            plannedDurationMinutes: context.plannedDurationMinutes,
            category: context.category,
            tags: context.tags,
            pathStepOrder: context.pathStepOrder,
            isPathLesson: context.isPathLesson,
            customConfig: context.customConfig,
            createdAt: context.createdAt
        )
        
        logger.eventMessage("SessionContextManager: Updated entry point to \(newEntryPoint.rawValue)")
    }
    
    // MARK: - Context Access
    
    /// Check if there's an active context (AI-generated session in progress).
    var hasActiveContext: Bool {
        currentContext != nil
    }
    
    /// Check if current context is AI-originated (for modification tracking).
    var isAIOriginated: Bool {
        currentContext?.contentOrigin == .aiRecommended
    }
    
    // MARK: - Analytics Parameters
    
    /// Generate analytics parameters dictionary from current context.
    /// Returns empty dictionary if no context is set.
    func getAnalyticsParameters() -> [String: Any] {
        guard let context = currentContext else {
            logger.warnMessage("SessionContextManager: getAnalyticsParameters called but no context exists")
            return [:]
        }
        
        var params: [String: Any] = [
            "session_id": context.sessionId,
            "entry_point": context.entryPoint.rawValue,
            "content_type": context.contentType.rawValue,
            "content_origin": context.contentOrigin.rawValue,
            "ai_customization_level": context.aiCustomizationLevel.rawValue,
            "recommendation_position": context.recommendationPosition.rawValue,
            "recommendation_trigger": context.recommendationTrigger.rawValue,
            "practice_title": context.practiceTitle,
            "planned_duration_minutes": context.plannedDurationMinutes,
            "ai_involved": context.aiInvolved
        ]
        
        // Heart rate feature flag status
        params["hr_feature_enabled"] = SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false)
        
        // Practice ID (for pre-recorded and path)
        if let practiceId = context.practiceId {
            params["practice_id"] = practiceId
        }
        
        // Category
        if let category = context.category {
            params["category"] = category
        }
        
        // Tags
        if !context.tags.isEmpty {
            params["tags"] = context.tags.joined(separator: ",")
        }
        
        // Path-specific
        if let stepOrder = context.pathStepOrder {
            params["path_step_order"] = stepOrder
        }
        if let isLesson = context.isPathLesson {
            params["is_path_lesson"] = isLesson
        }
        
        // Custom meditation config
        if let config = context.customConfig {
            let configParams = config.toAnalyticsParameters()
            for (key, value) in configParams {
                params[key] = value
            }
        }
        
        // Journey context (for funnel joining with journey_phase_entered/completed)
        if let phaseName = cachedJourneyPhaseName {
            params["journey_phase"] = phaseName
        }
        if let track = cachedJourneyTrack {
            params["journey_track"] = track
        }
        
        return params
    }
    
    /// Get parameters specifically for session completion (includes outcome).
    func getCompletionParameters(progressPercent: Int) -> [String: Any] {
        var params = getAnalyticsParameters()
        params["progress_percent"] = progressPercent
        params["outcome"] = SessionOutcomeType.from(progressPercent: progressPercent).rawValue
        return params
    }
    
    /// Get parameters for session progress events.
    func getProgressParameters(milestone: Int) -> [String: Any] {
        var params = getAnalyticsParameters()
        params["progress_percent"] = milestone
        return params
    }
    
    // MARK: - Cleanup
    
    /// Clear the current context. Call when session ends.
    func clearContext() {
        if let context = currentContext {
            analyticsLog("🧹 CLEARING CONTEXT")
            analyticsLog("   → Was: \(context.contentType.rawValue) - \(context.practiceTitle)")
            logger.eventMessage("SessionContextManager: Clearing context for \(context.practiceTitle)")
        }
        currentContext = nil
    }
}
