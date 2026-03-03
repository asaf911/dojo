//
//  OneSignalTagManager.swift
//  Dojo
//
//  Manages OneSignal user tags for session-based re-targeting.
//  Updates tags on session completion for push notification segmentation.
//

import Foundation

// MARK: - Debug Logging

private let ANALYTICS_TAG = "📊 ANALYTICS:"

private func analyticsLog(_ message: String) {
    print("\(ANALYTICS_TAG) [OneSignal] \(message)")
}

/// Manager for updating OneSignal user tags based on session activity.
@MainActor
final class OneSignalTagManager {
    static let shared = OneSignalTagManager()
    
    // MARK: - Storage Keys
    
    private let totalSessionsKey = "onesignal_total_sessions"
    
    private init() {}
    
    // MARK: - Session Completion Tags
    
    /// Update all relevant tags when a session completes.
    /// Called by AnalyticsRouter on session_complete.
    /// - Parameter context: The session context (captured before async call to avoid race condition)
    func updateTagsOnSessionComplete(context: AnalyticsSessionContext) {
        analyticsLog("🏷️ UPDATING ONESIGNAL TAGS")
        
        // Get current total sessions and increment
        let currentTotal = UserDefaults.standard.integer(forKey: totalSessionsKey)
        let newTotal = currentTotal + 1
        UserDefaults.standard.set(newTotal, forKey: totalSessionsKey)
        
        analyticsLog("   total_sessions: \(newTotal)")
        analyticsLog("   preferred_content_type: \(context.contentType.rawValue)")
        analyticsLog("   preferred_duration: \(context.plannedDurationMinutes)")
        analyticsLog("   ai_user: \(context.aiInvolved)")
        
        // Update engagement tags
        pushService.setTag(key: "last_session_date", value: ISO8601DateFormatter().string(from: Date()))
        pushService.setTag(key: "days_since_session", value: "0")
        pushService.setTag(key: "total_sessions", value: String(newTotal))
        pushService.setTag(key: "has_completed_session", value: "true")
        
        // Content preference tags
        pushService.setTag(key: "preferred_content_type", value: context.contentType.rawValue)
        pushService.setTag(key: "preferred_duration", value: String(context.plannedDurationMinutes))
        
        // AI involvement tag
        pushService.setTag(key: "ai_user", value: String(context.aiInvolved))
        
        // Path-specific tags (if this was a path session)
        if context.contentType == .pathStep {
            analyticsLog("   (also updating path tags)")
            updatePathTags()
        }
        
        analyticsLog("✅ OneSignal tags updated")
        logger.eventMessage("OneSignalTagManager: Updated tags on session complete - total=\(newTotal), type=\(context.contentType.rawValue)")
    }
    
    /// Legacy method - reads context from SessionContextManager (may have race condition issues).
    /// Prefer using updateTagsOnSessionComplete(context:) instead.
    func updateTagsOnSessionComplete() {
        guard let context = SessionContextManager.shared.currentContext else {
            analyticsLog("⚠️ No context available for tag update")
            logger.warnMessage("OneSignalTagManager: No context available for tag update")
            return
        }
        updateTagsOnSessionComplete(context: context)
    }
    
    // MARK: - Path Tags
    
    /// Update path-specific tags based on current progress.
    func updatePathTags() {
        let progressManager = PathProgressManager.shared
        let allSteps = progressManager.pathSteps.sorted { $0.order < $1.order }
        let completedSteps = allSteps.filter {
            PracticeManager.shared.isPracticeCompleted(practiceID: $0.id)
        }
        
        guard !allSteps.isEmpty else { return }
        
        let completionPercentage = Int((Double(completedSteps.count) / Double(allSteps.count)) * 100)
        
        // Status tag
        if completedSteps.count == allSteps.count {
            pushService.setTag(key: "path_status", value: "completed")
            pushService.removeTag("path_next_step")
        } else if completedSteps.isEmpty {
            pushService.setTag(key: "path_status", value: "not_started")
            if let firstStep = allSteps.first {
                pushService.setTag(key: "path_next_step", value: firstStep.id)
            }
        } else {
            pushService.setTag(key: "path_status", value: "in_progress")
            if let nextStep = progressManager.nextStep {
                pushService.setTag(key: "path_next_step", value: nextStep.id)
            }
        }
        
        // Progress percentage
        pushService.setTag(key: "path_progress", value: String(completionPercentage))
        
        // Last activity timestamp
        let timestamp = Int(Date().timeIntervalSince1970)
        pushService.setTag(key: "path_last_activity", value: String(timestamp))
        pushService.setTag(key: "path_days_inactive", value: "0")
        
        logger.eventMessage("OneSignalTagManager: Updated path tags - progress=\(completionPercentage)%, completed=\(completedSteps.count)/\(allSteps.count)")
    }
    
    // MARK: - Subscription Tags
    
    /// Update subscription status tag.
    /// - Parameter status: Subscription status ("free", "trial", "subscribed")
    func updateSubscriptionStatus(_ status: String) {
        pushService.setTag(key: "subscription_status", value: status)
        logger.eventMessage("OneSignalTagManager: Updated subscription_status to \(status)")
    }
    
    // MARK: - Inactivity Tracking
    
    /// Update days since last session tag.
    /// Should be called daily (e.g., on app launch or background fetch).
    func updateInactivityTags() {
        // Get last session date from storage
        guard let lastDateString = UserDefaults.standard.string(forKey: "last_session_date_storage"),
              let lastDate = ISO8601DateFormatter().date(from: lastDateString) else {
            return
        }
        
        let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        pushService.setTag(key: "days_since_session", value: String(max(0, daysSince)))
        
        logger.eventMessage("OneSignalTagManager: Updated days_since_session to \(daysSince)")
    }
    
    // MARK: - Session Streak Tags
    
    /// Update session streak tags.
    /// - Parameters:
    ///   - currentStreak: Current streak count
    ///   - isAtRisk: Whether streak will be lost tomorrow
    func updateStreakTags(currentStreak: Int, isAtRisk: Bool) {
        pushService.setTag(key: "session_streak", value: String(currentStreak))
        pushService.setTag(key: "streak_at_risk", value: String(isAtRisk))
        
        logger.eventMessage("OneSignalTagManager: Updated streak tags - streak=\(currentStreak), atRisk=\(isAtRisk)")
    }
    
    // MARK: - Initial Setup
    
    /// Initialize tags for a new user.
    /// Call after user registration/first launch.
    func initializeTagsForNewUser() {
        // Session/engagement tags
        pushService.setTag(key: "total_sessions", value: "0")
        pushService.setTag(key: "has_completed_session", value: "false")
        pushService.setTag(key: "ai_user", value: "false")
        pushService.setTag(key: "subscription_status", value: "free")
        
        // Path tags
        pushService.setTag(key: "path_status", value: "not_started")
        pushService.setTag(key: "path_progress", value: "0")
        
        // Journey phase tags
        let firstPhase = JourneyPhase.firstPhase
        pushService.setTag(key: "journey_phase", value: firstPhase.rawValue)
        pushService.setTag(key: "journey_phase_order", value: String(firstPhase.order))
        
        UserDefaults.standard.set(0, forKey: totalSessionsKey)
        
        logger.eventMessage("OneSignalTagManager: Initialized tags for new user - journey_phase=\(firstPhase.rawValue)")
    }
    
    // MARK: - Cleanup Legacy Tags
    
    /// Remove legacy path tags that are no longer used.
    /// Call once during migration to clean up old tag format.
    func cleanupLegacyTags() {
        let legacyTags = [
            "path_total_steps",
            "path_completed_steps",
            "path_completion_percent",
            "path_next_step_id",
            "path_next_step_order",
            "path_next_step_type",
            "path_next_step_title",
            "path_last_completed_step",
            "path_last_completed_order",
            "path_last_completed_type",
            "path_streak_days",
            "path_longest_streak",
            "path_completion_date"
        ]
        
        for tag in legacyTags {
            pushService.removeTag(tag)
        }
        
        logger.eventMessage("OneSignalTagManager: Cleaned up \(legacyTags.count) legacy tags")
    }
}
