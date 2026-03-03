//
//  PathAnalyticsHandler.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-04-28
//

import Foundation
import Mixpanel
import Combine

/// Dedicated handler for Path-specific analytics that extends the existing analytics system
@MainActor
class PathAnalyticsHandler {
    static let shared = PathAnalyticsHandler()
    
    // Set to true only when debugging path analytics issues
    private let verboseLogging = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotificationObserver()
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .didLogPracticeEvent)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePracticeEvent(notification: notification)
            }
            .store(in: &cancellables)
    }
    
    private func handlePracticeEvent(notification: Notification) {
        if verboseLogging { print("🔍 PathAnalyticsHandler: Received practice event notification") }
        
        guard let userInfo = notification.userInfo else {
            if verboseLogging { print("❌ PathAnalyticsHandler: No userInfo in notification") }
            return
        }
        
        if verboseLogging {
            print("🔍 PathAnalyticsHandler: UserInfo keys: \(Array(userInfo.keys))")
            print("🔍 PathAnalyticsHandler: UserInfo: \(userInfo)")
        }
        
        guard let eventName = userInfo["eventName"] as? String else {
            if verboseLogging { print("❌ PathAnalyticsHandler: Missing eventName in notification userInfo") }
            return
        }
        
        if verboseLogging { print("🔍 PathAnalyticsHandler: Event name: \(eventName)") }
        
        // Try to get practiceID from multiple possible sources
        var practiceID: String?
        
        // Method 1: Direct practiceID (from AudioPlayerManager)
        if let directID = userInfo["practiceID"] as? String {
            practiceID = directID
            if verboseLogging { print("🔍 PathAnalyticsHandler: Found practiceID (direct): \(directID)") }
        }
        // Method 2: From parameters (from AnalyticsManager)
        else if let parameters = userInfo["parameters"] as? [String: Any],
                let paramID = parameters["practice_id"] as? String {
            practiceID = paramID
            if verboseLogging { print("🔍 PathAnalyticsHandler: Found practiceID (from parameters): \(paramID)") }
        }
        
        guard let finalPracticeID = practiceID else {
            if verboseLogging {
                print("❌ PathAnalyticsHandler: Could not find practiceID in notification")
                print("❌ PathAnalyticsHandler: Available userInfo: \(userInfo)")
            }
            return
        }
        
        if verboseLogging { print("🔍 PathAnalyticsHandler: Using practiceID: \(finalPracticeID)") }
        
        let isPath = isPathStep(practiceID: finalPracticeID)
        if verboseLogging { print("🔍 PathAnalyticsHandler: Is path step: \(isPath)") }
        
        if isPath {
            if verboseLogging { print("✅ PathAnalyticsHandler: Processing path event - \(eventName) for \(finalPracticeID)") }
            processPathEvent(eventName: eventName, practiceID: finalPracticeID)
        } else {
            if verboseLogging { print("ℹ️ PathAnalyticsHandler: Skipping non-path practice: \(finalPracticeID)") }
        }
    }
    
    private func isPathStep(practiceID: String) -> Bool {
        // Use PathProgressManager as the single source of truth instead of PathDataManager
        let allSteps = PathProgressManager.shared.pathSteps
        let isPath = allSteps.contains(where: { $0.id == practiceID })
        
        if verboseLogging {
            print("🔍 PathAnalyticsHandler: Checking if \(practiceID) is path step")
            print("🔍 PathAnalyticsHandler: Total path steps: \(allSteps.count)")
            print("🔍 PathAnalyticsHandler: Path step IDs: \(allSteps.map { $0.id })")
            print("🔍 PathAnalyticsHandler: Is path step result: \(isPath)")
        }
        
        return isPath
    }
    
    private func processPathEvent(eventName: String, practiceID: String) {
        if verboseLogging { print("🔍 PathAnalyticsHandler: Processing path event: \(eventName) for practice: \(practiceID)") }
        
        // Map standard practice events and new session events to Path-specific events
        let pathEventName: String
        
        switch eventName {
        case "practice_start", "session_start":
            pathEventName = "path_step_started"
            if verboseLogging { print("✅ PathAnalyticsHandler: Mapped to path_step_started") }
        case "practice_complete", "session_complete":
            pathEventName = "path_step_completed"
            if verboseLogging { print("✅ PathAnalyticsHandler: Mapped to path_step_completed - will track progress") }
            trackPathProgress(completedStepID: practiceID)
            // Also update OneSignal tags using the new manager
            OneSignalTagManager.shared.updatePathTags()
        case "practice_25_percent_complete", 
             "practice_50_percent_complete", 
             "practice_75_percent_complete",
             "session_progress":
            // Progress events are now handled by AnalyticsRouter
            if verboseLogging { print("ℹ️ PathAnalyticsHandler: Skipping progress event: \(eventName)") }
            return
        default:
            // Not a Path-specific event we care about
            if verboseLogging { print("ℹ️ PathAnalyticsHandler: Skipping unrecognized event: \(eventName)") }
            return
        }
        
        // Get the step details to include as parameters
        if let step = findPathStep(practiceID: practiceID) {
            let parameters = createStepParameters(step: step)
            if verboseLogging { print("✅ PathAnalyticsHandler: Logging analytics event: \(pathEventName)") }
            AnalyticsManager.shared.logEvent(pathEventName, parameters: parameters)
        } else {
            if verboseLogging { print("❌ PathAnalyticsHandler: Could not find path step for ID: \(practiceID)") }
        }
    }
    
    private func findPathStep(practiceID: String) -> PathStep? {
        return PathProgressManager.shared.pathSteps.first(where: { $0.id == practiceID })
    }
    
    private func createStepParameters(step: PathStep) -> [String: Any] {
        // Use PathProgressManager as the single source of truth
        let allSteps = PathProgressManager.shared.pathSteps.sorted(by: { $0.order < $1.order })
        let totalSteps = allSteps.count
        
        // Find completed steps
        let completedSteps = allSteps.filter {
            PracticeManager.shared.isPracticeCompleted(practiceID: $0.id)
        }
        
        let completedCount = completedSteps.count
        let completionPercentage = totalSteps > 0 ? Double(completedCount) / Double(totalSteps) : 0.0
        
        return [
            "step_id": step.id,
            "step_order": step.order,
            "step_title": step.title,
            "step_type": step.isLesson ? "lesson" : "practice",
            "step_duration": step.duration,
            "is_premium": step.premium,
            "completion_percentage": Int(completionPercentage * 100),
            "total_steps_count": totalSteps,
            "completed_steps_count": completedCount
        ]
    }
    
    private func trackPathProgress(completedStepID: String) {
        if verboseLogging { print("🚀 PathAnalyticsHandler: trackPathProgress called for step: \(completedStepID)") }
        
        guard let _ = findPathStep(practiceID: completedStepID) else { 
            if verboseLogging { print("❌ PathAnalyticsHandler: Could not find completed step: \(completedStepID)") }
            return 
        }
        
        // Use PathProgressManager as the single source of truth
        let allSteps = PathProgressManager.shared.pathSteps.sorted(by: { $0.order < $1.order })
        let totalSteps = allSteps.count
        
        // Find completed steps
        let completedSteps = allSteps.filter {
            PracticeManager.shared.isPracticeCompleted(practiceID: $0.id)
        }
        
        let completedCount = completedSteps.count
        let percentage = totalSteps > 0 ? Double(completedCount) / Double(totalSteps) : 0.0
        
        if verboseLogging { print("📊 PathAnalyticsHandler: Progress stats - Completed: \(completedCount)/\(totalSteps) (\(Int(percentage * 100))%)") }
        
        // Check milestone thresholds
        for milestone in [0.25, 0.50, 0.75, 1.0] {
            if percentage >= milestone {
                // Check if we just crossed this milestone threshold
                let previousPercentage = totalSteps > 0 ? Double(completedCount - 1) / Double(totalSteps) : 0.0
                
                if previousPercentage < milestone && completedSteps.map({ $0.id }).contains(completedStepID) {
                    // We just crossed this milestone
                    let params: [String: Any] = [
                        "milestone": milestone,
                        "milestone_percentage": Int(milestone * 100),
                        "completed_steps_count": completedCount,
                        "total_steps_count": totalSteps,
                        "latest_completed_step_id": completedStepID
                    ]
                    
                    if verboseLogging { print("🎯 PathAnalyticsHandler: Milestone reached: \(Int(milestone * 100))%") }
                    AnalyticsManager.shared.logEvent("path_milestone_reached", parameters: params)
                    
                    // For 100% completion, log a special event
                    if milestone == 1.0 {
                        if verboseLogging { print("🎉 PathAnalyticsHandler: Path completed!") }
                        AnalyticsManager.shared.logEvent("path_completed", parameters: [
                            "total_steps_count": totalSteps,
                            "completion_date": Date()
                        ])
                    }
                }
            }
        }
        
        // Update OneSignal tags for path progress
        if verboseLogging { print("🏷️ PathAnalyticsHandler: Calling updateOneSignalPathTags...") }
        updateOneSignalPathTags(completedStepID: completedStepID)
    }
    
    // MARK: - OneSignal Tagging Strategy
    
    /// Updates OneSignal tags with essential path progress data for Journey automation (optimized for tag limits)
    private func updateOneSignalPathTags(completedStepID: String) {
        print("🏷️ OneSignal: Starting optimized tag update for completed step: \(completedStepID)")
        
        guard let _ = findPathStep(practiceID: completedStepID) else { 
            print("❌ OneSignal: Could not find completed step: \(completedStepID)")
            return 
        }
        
        // Use PathProgressManager as the single source of truth instead of PathDataManager
        let allSteps = PathProgressManager.shared.pathSteps.sorted(by: { $0.order < $1.order })
        let completedSteps = allSteps.filter { 
            PracticeManager.shared.isPracticeCompleted(practiceID: $0.id) 
        }
        let completionPercentage = allSteps.isEmpty ? 0.0 : Double(completedSteps.count) / Double(allSteps.count)
        
        print("📊 Push: Tag data - Total: \(allSteps.count), Completed: \(completedSteps.count), Percentage: \(Int(completionPercentage * 100))%")
        
        // ESSENTIAL TAGS ONLY (5 tags total)
        print("🏷️ Push: Setting essential tags only...")
        
        // 1. Status (most important for journey triggers)
        if completedSteps.count == allSteps.count {
            pushService.setTag(key: "path_status", value: "completed")
            print("✅ Push: Status set to 'completed'")
        } else {
            pushService.setTag(key: "path_status", value: "in_progress")
            print("✅ Push: Status set to 'in_progress'")
        }
        
        // 2. Progress percentage (for segment targeting)
        pushService.setTag(key: "path_progress", value: String(Int(completionPercentage * 100)))
        
        // 3. Next step ID (for deep linking)
        if let nextStep = PathProgressManager.shared.nextStep {
            pushService.setTag(key: "path_next_step", value: nextStep.id)
            print("🏷️ Push: Next step: \(nextStep.title)")
        } else {
            pushService.removeTag("path_next_step")
        }
        
        // 4. Last activity timestamp (for inactivity detection)
        let timestamp = Int(Date().timeIntervalSince1970)
        pushService.setTag(key: "path_last_activity", value: String(timestamp))
        
        // 5. Days since last activity (calculated field for journey triggers)
        pushService.setTag(key: "path_days_inactive", value: "0") // Reset since user just completed
        
        logger.eventMessage("Updated essential path tags for completed step: \(completedStepID)")
        print("✅ Push: Essential tag update completed for step: \(completedStepID)")
    }
    
    /// Initialize essential tags for users (optimized for tag limits)
    func initializePathTagsForNewUser() {
        print("🔄 Push: initializePathTagsForNewUser called (essential tags only)")
        
        // Use PathProgressManager as the single source of truth instead of PathDataManager
        let allSteps = PathProgressManager.shared.pathSteps.sorted(by: { $0.order < $1.order })
        
        guard !allSteps.isEmpty else { 
            print("❌ Push: No path steps available for initialization")
            return 
        }
        
        // Get completed steps using the same data source
        let completedSteps = allSteps.filter { 
            PracticeManager.shared.isPracticeCompleted(practiceID: $0.id) 
        }
        
        print("📊 Push: Initialization data - Total steps: \(allSteps.count), Completed: \(completedSteps.count)")
        
        if completedSteps.isEmpty {
            // User hasn't started path - set essential initial tags
            print("🏷️ Push: User hasn't started - setting essential initial tags")
            pushService.setTag(key: "path_status", value: "not_started")
            pushService.setTag(key: "path_progress", value: "0")
            pushService.setTag(key: "path_days_inactive", value: "0")
            
            if let firstStep = allSteps.first {
                pushService.setTag(key: "path_next_step", value: firstStep.id)
                print("✅ Push: Set first step as next: \(firstStep.title)")
            }
            
            logger.eventMessage("Initialized essential path tags for new user")
            print("✅ Push: Essential new user initialization completed")
        } else {
            // User has some progress, update tags to current state
            print("🔄 Push: User has progress, updating current state")
            updateCurrentPathStateTags()
        }
    }
    
    /// Updates tags to reflect current path state (essential tags only)
    func updateCurrentPathStateTags() {
        print("🔄 Push: updateCurrentPathStateTags called (essential tags only)")
        
        // Use PathProgressManager as the single source of truth instead of PathDataManager
        let allSteps = PathProgressManager.shared.pathSteps.sorted(by: { $0.order < $1.order })
        let completedSteps = allSteps.filter { 
            PracticeManager.shared.isPracticeCompleted(practiceID: $0.id) 
        }
        
        guard !allSteps.isEmpty else { 
            print("❌ Push: No path steps available for state update")
            return 
        }
        
        let completionPercentage = allSteps.isEmpty ? 0.0 : Double(completedSteps.count) / Double(allSteps.count)
        
        print("📊 Push: State update data - Total: \(allSteps.count), Completed: \(completedSteps.count), Percentage: \(Int(completionPercentage * 100))%")
        
        // ESSENTIAL TAGS ONLY
        print("🏷️ Push: Updating essential tags only")
        
        // Status
        if completedSteps.count == allSteps.count {
            pushService.setTag(key: "path_status", value: "completed")
            pushService.removeTag("path_next_step") // No next step when completed
        } else {
            pushService.setTag(key: "path_status", value: "in_progress")
            
            // Next step
            if let nextStep = PathProgressManager.shared.nextStep {
                pushService.setTag(key: "path_next_step", value: nextStep.id)
                print("🏷️ Push: Next step: \(nextStep.title)")
            }
        }
        
        // Progress percentage
        pushService.setTag(key: "path_progress", value: String(Int(completionPercentage * 100)))
        
        logger.eventMessage("Updated essential path state tags")
        print("✅ Push: Essential state update completed")
    }
    
    /// Updates inactivity tracking - should be called daily (simplified for essential tags)
    func updatePathInactivityTags() {
        // Get the last activity timestamp and calculate days inactive
        if let lastActivityString = getUserTag("path_last_activity"),
           let lastTimestamp = Double(lastActivityString) {
            
            let daysSinceLastActivity = Int(Date().timeIntervalSince1970 - lastTimestamp) / 86400
            pushService.setTag(key: "path_days_inactive", value: String(max(0, daysSinceLastActivity)))
            
            logger.eventMessage("Updated path inactivity: \(daysSinceLastActivity) days")
        }
    }
    
    /// Helper to get current user tag value
    private func getUserTag(_ key: String) -> String? {
        // Note: Push service doesn't provide a direct way to get current tags
        // This would need to be implemented based on your app's tag caching strategy
        // For now, return nil and rely on server-side tag management
        return nil
    }
    
    /// Track when a user views a path step (to be called from the UI)
    func trackStepViewed(step: PathStep) {
        let parameters = createStepParameters(step: step)
        AnalyticsManager.shared.logEvent("path_step_viewed", parameters: parameters)
    }
    
    /// Clean up old path tags that are no longer needed (call once to migrate to essential tags)
    func cleanupLegacyPathTags() {
        print("🧹 Push: Cleaning up legacy path tags...")
        
        // Remove old comprehensive tags that we no longer use
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
        
        print("✅ Push: Legacy tag cleanup completed")
        logger.eventMessage("Cleaned up legacy path tags")
    }
}
