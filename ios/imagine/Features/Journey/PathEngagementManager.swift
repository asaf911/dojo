//
//  PathEngagementManager.swift
//  imagine
//
//  Created by Asaf Shamir on 2025-01-XX
//

import Foundation
import UIKit
import Combine

// MARK: - Debug Logging

private let PATH_ENGAGEMENT_TAG = "🎯 PATH_ENGAGEMENT:"

/// Log path engagement messages (only in DEBUG builds)
private func pathEngagementLog(_ message: String) {
    #if DEBUG
    print("\(PATH_ENGAGEMENT_TAG) \(message)")
    #endif
}

/// Manages path engagement tracking and OneSignal tag updates for automated journey triggers
@MainActor
class PathEngagementManager {
    static let shared = PathEngagementManager()
    
    private let userDefaults = UserDefaults.standard
    private let lastUpdateKey = "path_last_inactivity_update"
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        pathEngagementLog("[INIT] Setting up lifecycle observers")
        setupAppLifecycleObservers()
    }
    
    // MARK: - App Lifecycle Management
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.appDidBecomeActive()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.appDidEnterBackground()
            }
            .store(in: &cancellables)
    }
    
    private func appDidBecomeActive() {
        pathEngagementLog("[APP_ACTIVE] Checking for tag updates")
        
        // Update inactivity tags when app becomes active
        updateInactivityTagsIfNeeded()
        
        // Update current path state to ensure tags are accurate
        PathAnalyticsHandler.shared.updateCurrentPathStateTags()
        pathEngagementLog("[APP_ACTIVE] Path state tags updated")
    }
    
    private func appDidEnterBackground() {
        pathEngagementLog("[APP_BACKGROUND] Storing timestamp for inactivity tracking")
        // Store timestamp for inactivity calculation
        userDefaults.set(Date(), forKey: "path_background_timestamp")
    }
    
    // MARK: - Inactivity Tracking
    
    /// Updates path inactivity tags if enough time has passed since last update
    private func updateInactivityTagsIfNeeded() {
        let now = Date()
        let lastUpdate = userDefaults.object(forKey: lastUpdateKey) as? Date ?? Date.distantPast
        
        // Update once per day
        if Calendar.current.dateInterval(of: .day, for: lastUpdate)?.contains(now) == false {
            pathEngagementLog("[INACTIVITY] Updating tags (new day detected)")
            PathAnalyticsHandler.shared.updatePathInactivityTags()
            userDefaults.set(now, forKey: lastUpdateKey)
            
            logger.eventMessage("PathEngagementManager: Updated inactivity tags")
        } else {
            pathEngagementLog("[INACTIVITY] Skipped update (already updated today)")
        }
    }
    
    // MARK: - Manual Tag Updates
    
    /// Manually trigger a full tag update (useful for debugging or admin functions)
    func forceUpdateAllPathTags() {
        pathEngagementLog("[FORCE_UPDATE] Updating all path tags")
        PathAnalyticsHandler.shared.updateCurrentPathStateTags()
        PathAnalyticsHandler.shared.updatePathInactivityTags()
        pathEngagementLog("[FORCE_UPDATE] Complete")
        
        logger.eventMessage("PathEngagementManager: Force updated all path tags")
    }
    
    /// Reset all path tags (useful for testing or user reset scenarios)
    func resetAllPathTags() {
        pathEngagementLog("[RESET] Clearing all path tags")
        
        let pathTags = [
            "path_status",
            "path_total_steps",
            "path_completed_steps",
            "path_completion_percent",
            "path_last_completed_step",
            "path_last_completed_order",
            "path_last_completed_type",
            "path_next_step_id",
            "path_next_step_order",
            "path_next_step_type",
            "path_next_step_title",
            "path_last_activity",
            "path_days_inactive",
            "path_streak_days",
            "path_longest_streak",
            "path_completion_date"
        ]
        
        for tag in pathTags {
            pushService.removeTag(tag)
        }
        
        pathEngagementLog("[RESET] Removed \(pathTags.count) tags, re-initializing...")
        logger.eventMessage("PathEngagementManager: Reset all path tags")
        
        // Re-initialize tags based on current state
        PathAnalyticsHandler.shared.initializePathTagsForNewUser()
        pathEngagementLog("[RESET] Complete - tags re-initialized")
    }
    
    // MARK: - Journey Trigger Helpers
    
    /// Check if user should enter a re-engagement journey
    func shouldTriggerReEngagementJourney() -> Bool {
        // This is for local logic - OneSignal Journeys will handle the actual triggering
        // But this can be useful for internal app logic
        
        let progressManager = PathProgressManager.shared
        let completedSteps = progressManager.getCompletedSteps()
        let totalSteps = progressManager.totalStepCount
        
        // User has started but not completed the path
        let hasStarted = !completedSteps.isEmpty
        let isCompleted = completedSteps.count == totalSteps
        
        let shouldTrigger = hasStarted && !isCompleted
        pathEngagementLog("[CHECK] shouldTriggerReEngagement=\(shouldTrigger) (started=\(hasStarted), completed=\(isCompleted), steps=\(completedSteps.count)/\(totalSteps))")
        
        return shouldTrigger
    }
    
    /// Check if user should enter an onboarding journey
    func shouldTriggerOnboardingJourney() -> Bool {
        let progressManager = PathProgressManager.shared
        let completedSteps = progressManager.getCompletedSteps()
        let totalSteps = progressManager.totalStepCount
        
        // User hasn't started the path
        let shouldTrigger = completedSteps.isEmpty && totalSteps > 0
        pathEngagementLog("[CHECK] shouldTriggerOnboarding=\(shouldTrigger) (completedSteps=\(completedSteps.count), totalSteps=\(totalSteps))")
        
        return shouldTrigger
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let pathEngagementUpdate = Notification.Name("pathEngagementUpdate")
}
