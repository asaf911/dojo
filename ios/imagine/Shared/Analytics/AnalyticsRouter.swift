//
//  AnalyticsRouter.swift
//  Dojo
//
//  Central router for dispatching analytics events to appropriate vendors.
//  - Mixpanel: All events, all properties
//  - AppsFlyer: Only session_start and session_complete
//  - OneSignal: Tags only (updated on session_complete)
//

import Foundation

// MARK: - Debug Logging

private let ANALYTICS_TAG = "📊 ANALYTICS:"

private func analyticsLog(_ message: String) {
    print("\(ANALYTICS_TAG) [Router] \(message)")
}

/// Central analytics router that dispatches events to appropriate vendors.
final class AnalyticsRouter {
    static let shared = AnalyticsRouter()
    
    private init() {}
    
    // MARK: - Debug Helpers
    
    private func logParamsForDebug(_ params: [String: Any]) {
        // Core dimensions
        if let entryPoint = params["entry_point"] as? String {
            analyticsLog("   entry_point: \(entryPoint)")
        }
        if let contentType = params["content_type"] as? String {
            analyticsLog("   content_type: \(contentType)")
        }
        if let contentOrigin = params["content_origin"] as? String {
            analyticsLog("   content_origin: \(contentOrigin)")
        }
        if let aiLevel = params["ai_customization_level"] as? String {
            analyticsLog("   ai_customization_level: \(aiLevel)")
        }
        if let recommendationPosition = params["recommendation_position"] as? String {
            analyticsLog("   recommendation_position: \(recommendationPosition)")
        }
        if let aiInvolved = params["ai_involved"] as? Bool {
            analyticsLog("   ai_involved: \(aiInvolved)")
        }
        if let journeyPhase = params["journey_phase"] as? String {
            analyticsLog("   journey_phase: \(journeyPhase)")
        }
        if let journeyTrack = params["journey_track"] as? String {
            analyticsLog("   journey_track: \(journeyTrack)")
        }
        
        // Content info
        if let practiceId = params["practice_id"] as? String {
            analyticsLog("   practice_id: \(practiceId)")
        }
        if let title = params["practice_title"] as? String {
            analyticsLog("   practice_title: \(title)")
        }
        if let duration = params["planned_duration_minutes"] as? Int {
            analyticsLog("   planned_duration_minutes: \(duration)")
        }
        
        // Progress/outcome
        if let progress = params["progress_percent"] as? Int {
            analyticsLog("   progress_percent: \(progress)")
        }
        if let outcome = params["outcome"] as? String {
            analyticsLog("   outcome: \(outcome)")
        }
        
        // Custom meditation config
        if let configDuration = params["config_duration_minutes"] as? Int {
            analyticsLog("   config_duration_minutes: \(configDuration)")
        }
        if let bgSound = params["config_background_sound"] as? String {
            analyticsLog("   config_background_sound: \(bgSound)")
        }
        if let binaural = params["config_binaural_beat"] as? String {
            analyticsLog("   config_binaural_beat: \(binaural)")
        }
        if let cueCount = params["config_cue_count"] as? Int {
            analyticsLog("   config_cue_count: \(cueCount)")
        }
    }
    
    // MARK: - Session Events
    
    /// Log session preload event (session loaded but not yet started).
    /// - Sends to Mixpanel only
    func logSessionPreload() {
        let params = SessionContextManager.shared.getAnalyticsParameters()
        
        analyticsLog("═══════════════════════════════════════════")
        analyticsLog("📥 EVENT: session_preload")
        analyticsLog("───────────────────────────────────────────")
        logParamsForDebug(params)
        analyticsLog("───────────────────────────────────────────")
        analyticsLog("📤 Sending to: Mixpanel only")
        
        // Mixpanel only - preload events don't go to AppsFlyer
        AnalyticsManager.shared.logEvent("session_preload", parameters: params)
        
        analyticsLog("═══════════════════════════════════════════")
        logger.eventMessage("AnalyticsRouter: Logged session_preload")
    }
    
    /// Log session start event.
    /// - Sends to Mixpanel with all properties
    /// - Sends to AppsFlyer with limited properties
    /// - Fires journey_first_session_started once when session count is 0 (before completion)
    func logSessionStart() {
        let params = SessionContextManager.shared.getAnalyticsParameters()
        
        // Fire journey_first_session_started when user starts their first meditation
        if StatsManager.shared.getSessionCount() == 0 {
            let sessionId = params["session_id"] as? String
            JourneyAnalytics.logFirstSessionStarted(sessionId: sessionId)
        }
        
        analyticsLog("═══════════════════════════════════════════")
        analyticsLog("🚀 EVENT: session_start")
        analyticsLog("───────────────────────────────────────────")
        logParamsForDebug(params)
        analyticsLog("───────────────────────────────────────────")
        analyticsLog("📤 Sending to: Mixpanel (full), AppsFlyer (filtered)")
        
        // Mixpanel: Full event with all properties
        AnalyticsManager.shared.logEvent(SessionEventType.sessionStart.rawValue, parameters: params)
        
        // AppsFlyer: Limited properties for campaign optimization
        let afParams = filterForAppsFlyer(params)
        AppsFlyerManager.shared.logEvent(SessionEventType.sessionStart.rawValue, parameters: afParams)
        
        analyticsLog("═══════════════════════════════════════════")
        logger.eventMessage("AnalyticsRouter: Logged session_start")
    }
    
    /// Log session progress event (milestone reached).
    /// - Sends to Mixpanel only
    /// - Parameter milestone: Progress percentage (25, 50, 75, 95)
    func logSessionProgress(milestone: Int) {
        let params = SessionContextManager.shared.getProgressParameters(milestone: milestone)
        
        analyticsLog("📍 EVENT: session_progress (\(milestone)%)")
        analyticsLog("   📤 Sending to: Mixpanel only")
        
        // Mixpanel only - progress events don't go to AppsFlyer
        AnalyticsManager.shared.logEvent(SessionEventType.sessionProgress.rawValue, parameters: params)
        
        logger.eventMessage("AnalyticsRouter: Logged session_progress at \(milestone)%")
    }
    
    /// Log session complete event.
    /// - Sends to Mixpanel with all properties
    /// - Sends to AppsFlyer with limited properties
    /// - Updates OneSignal tags
    func logSessionComplete() {
        let params = SessionContextManager.shared.getCompletionParameters(progressPercent: 100)
        
        // IMPORTANT: Capture context BEFORE async call to avoid race condition
        // (context may be cleared before async task executes)
        let capturedContext = SessionContextManager.shared.currentContext
        
        analyticsLog("═══════════════════════════════════════════")
        analyticsLog("🏁 EVENT: session_complete")
        analyticsLog("───────────────────────────────────────────")
        logParamsForDebug(params)
        analyticsLog("───────────────────────────────────────────")
        analyticsLog("📤 Sending to: Mixpanel (full), AppsFlyer (filtered), OneSignal (tags)")
        
        // Mixpanel: Full event with all properties
        AnalyticsManager.shared.logEvent(SessionEventType.sessionComplete.rawValue, parameters: params)
        
        // AppsFlyer: Limited properties for campaign optimization
        let afParams = filterForAppsFlyer(params)
        AppsFlyerManager.shared.logEvent(SessionEventType.sessionComplete.rawValue, parameters: afParams)
        
        // OneSignal: Update user tags (main actor isolated)
        // Pass captured context to avoid race condition with context clearing
        if let context = capturedContext {
            Task { @MainActor in
                OneSignalTagManager.shared.updateTagsOnSessionComplete(context: context)
            }
        } else {
            analyticsLog("⚠️ No context to pass to OneSignal")
        }
        
        // Mark first session complete for subscription gating.
        // Don't rely on getSessionCount() — it can be overwritten by Firestore sync.
        let alreadySet = SharedUserStorage.retrieve(forKey: .hasCompletedFirstSession, as: Bool.self) ?? false
        if !alreadySet {
            SharedUserStorage.save(value: true, forKey: .hasCompletedFirstSession)
            analyticsLog("📊 [SUBSCRIPTION_GATE] First session complete — set hasCompletedFirstSession=true")
        } else {
            analyticsLog("📊 [SUBSCRIPTION_GATE] hasCompletedFirstSession already set, skipping")
        }

        analyticsLog("═══════════════════════════════════════════")
        logger.eventMessage("AnalyticsRouter: Logged session_complete")
    }
    
    /// Log session aborted event (user exited early).
    /// - Sends to Mixpanel only
    /// - Parameter progressPercent: Actual progress when user exited (0-99)
    func logSessionAborted(progressPercent: Int) {
        let params = SessionContextManager.shared.getCompletionParameters(progressPercent: progressPercent)
        
        analyticsLog("═══════════════════════════════════════════")
        analyticsLog("⏹️ EVENT: session_aborted (\(progressPercent)%)")
        analyticsLog("───────────────────────────────────────────")
        logParamsForDebug(params)
        analyticsLog("───────────────────────────────────────────")
        analyticsLog("📤 Sending to: Mixpanel only")
        
        // Mixpanel only - aborted events don't go to AppsFlyer
        AnalyticsManager.shared.logEvent(SessionEventType.sessionAborted.rawValue, parameters: params)
        
        analyticsLog("═══════════════════════════════════════════")
        logger.eventMessage("AnalyticsRouter: Logged session_aborted at \(progressPercent)%")
    }
    
    /// Log session rated event.
    /// - Sends to Mixpanel only
    /// - Parameter rating: User's rating (1-5)
    func logSessionRated(rating: Int) {
        var params = SessionContextManager.shared.getAnalyticsParameters()
        params["rating"] = rating
        
        analyticsLog("⭐ EVENT: session_rated (rating=\(rating))")
        analyticsLog("   📤 Sending to: Mixpanel only")
        
        // Mixpanel only
        AnalyticsManager.shared.logEvent(SessionEventType.sessionRated.rawValue, parameters: params)
        
        logger.eventMessage("AnalyticsRouter: Logged session_rated with rating=\(rating)")
    }
    
    // MARK: - Path-Specific Events
    
    /// Log path step started event.
    /// - Sends to Mixpanel only
    func logPathStepStarted() {
        guard let context = SessionContextManager.shared.currentContext,
              context.contentType == .pathStep else {
            analyticsLog("⚠️ path_step_started skipped - not a path step")
            return
        }
        
        analyticsLog("🛤️ EVENT: path_step_started (step order: \(context.pathStepOrder ?? 0))")
        analyticsLog("   📤 Sending to: Mixpanel only")
        
        let params = SessionContextManager.shared.getAnalyticsParameters()
        AnalyticsManager.shared.logEvent("path_step_started", parameters: params)
        
        logger.eventMessage("AnalyticsRouter: Logged path_step_started")
    }
    
    /// Log path step completed event.
    /// - Sends to Mixpanel only
    func logPathStepCompleted() {
        guard let context = SessionContextManager.shared.currentContext,
              context.contentType == .pathStep else {
            analyticsLog("⚠️ path_step_completed skipped - not a path step")
            return
        }
        
        analyticsLog("🛤️ EVENT: path_step_completed (step order: \(context.pathStepOrder ?? 0))")
        analyticsLog("   📤 Sending to: Mixpanel only")
        
        let params = SessionContextManager.shared.getCompletionParameters(progressPercent: 100)
        AnalyticsManager.shared.logEvent("path_step_completed", parameters: params)
        
        logger.eventMessage("AnalyticsRouter: Logged path_step_completed")
    }
    
    /// Log path milestone reached event.
    /// - Sends to Mixpanel only
    /// - Parameters:
    ///   - milestone: Path completion milestone (25, 50, 75, 100)
    ///   - completedStepsCount: Number of completed steps
    ///   - totalStepsCount: Total number of steps
    func logPathMilestoneReached(milestone: Int, completedStepsCount: Int, totalStepsCount: Int) {
        var params = SessionContextManager.shared.getAnalyticsParameters()
        params["milestone"] = milestone
        params["milestone_percentage"] = milestone
        params["completed_steps_count"] = completedStepsCount
        params["total_steps_count"] = totalStepsCount
        
        AnalyticsManager.shared.logEvent("path_milestone_reached", parameters: params)
        
        logger.eventMessage("AnalyticsRouter: Logged path_milestone_reached at \(milestone)%")
    }
    
    /// Log path completed event (100% milestone).
    /// - Sends to Mixpanel only
    func logPathCompleted(totalStepsCount: Int) {
        var params: [String: Any] = [
            "total_steps_count": totalStepsCount,
            "completion_date": Date()
        ]
        
        // Add context if available
        if let context = SessionContextManager.shared.currentContext {
            params["entry_point"] = context.entryPoint.rawValue
            params["content_origin"] = context.contentOrigin.rawValue
        }
        
        AnalyticsManager.shared.logEvent("path_completed", parameters: params)
        
        logger.eventMessage("AnalyticsRouter: Logged path_completed")
    }
    
    // MARK: - AppsFlyer Filtering
    
    /// Filter parameters for AppsFlyer (keep only marketing-relevant properties).
    private func filterForAppsFlyer(_ params: [String: Any]) -> [String: Any] {
        let allowedKeys: Set<String> = [
            "entry_point",
            "content_type",
            "content_origin",
            "planned_duration_minutes",
            "ai_involved",
            "ai_customization_level",
            "journey_phase",
            "journey_track"
        ]
        
        return params.filter { allowedKeys.contains($0.key) }
    }
    
    // MARK: - Session Lifecycle
    
    /// End the current session and clear context.
    /// Call this after logging completion/abort events.
    func endSession() {
        analyticsLog("🔚 END SESSION - clearing context")
        SessionContextManager.shared.clearContext()
        logger.eventMessage("AnalyticsRouter: Session ended, context cleared")
    }
}

// MARK: - Notification for Practice Events

extension Notification.Name {
    /// Posted when a session event is logged. Used by PathAnalyticsHandler.
    static let didLogSessionEvent = Notification.Name("didLogSessionEvent")
}
