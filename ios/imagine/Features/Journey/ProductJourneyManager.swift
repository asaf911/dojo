//
//  ProductJourneyManager.swift
//  imagine
//
//  Created by Cursor on 1/14/26.
//
//  Central orchestrator for the user's product journey.
//  This manager determines which phase the user is in and routes
//  recommendation requests to the appropriate phase-specific manager.
//
//  Architecture:
//  - ProductJourneyManager (this file) - orchestrates phase transitions
//  - PathProgressManager - handles Path phase specifics
//  - ExploreRecommendationManager - handles Daily Routines phase specifics
//

// =============================================================================
// HOW TO ADD A NEW JOURNEY PHASE - ProductJourneyManager Changes
// =============================================================================
//
// When adding a new phase, update the following in this file:
//
// 1. determineCurrentPhase() - Add logic to determine when user is in the new phase
//    Example for onboarding:
//    if !OnboardingManager.shared.isComplete {
//        return .onboarding
//    }
//
// 2. getRecommendation() - Add a case for the new phase
//    Example:
//    case .onboarding:
//        return getOnboardingRecommendation()
//
// 3. Create a helper method for the new phase's recommendation (optional)
//    Example:
//    private func getOnboardingRecommendation() -> JourneyRecommendation? { ... }
//
// 4. Update jumpToPhase() and jumpToDestination() for dev mode testing
//
// ANALYTICS (handled automatically):
// - journey_phase_entered: Fires when entering a phase (new user, phase completion, reset, dev mode)
// - journey_phase_completed: Fires when completing a phase (also triggers entry to next phase)
// - AppsFlyer af_level_achieved: Fires on phase completion for marketing attribution
// - OneSignal tags: Updated for push notification segmentation
//
// For phase configuration, see JourneyPhase.swift
// =============================================================================

import Foundation
import Combine

// MARK: - Debug Logging

private let JOURNEY_TAG = "📊 JOURNEY:"

/// Log journey manager messages (only in DEBUG builds)
private func journeyManagerLog(_ message: String) {
    #if DEBUG
    print("\(JOURNEY_TAG) \(message)")
    #endif
}

// MARK: - Product Journey Manager

/// Central manager that orchestrates the user's product journey through phases.
/// Determines current phase based on completion states and provides
/// the appropriate recommendations for each phase.
@MainActor
class ProductJourneyManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ProductJourneyManager()
    
    // MARK: - Published State
    
    /// The user's current journey phase
    @Published private(set) var currentPhase: JourneyPhase = JourneyPhase.firstPhase
    
    /// Trigger for forcing UI refresh
    @Published var refreshTrigger: UUID = UUID()
    
    /// Pre-app phase completion state (observable for ContentView routing)
    @Published private(set) var isOnboardingComplete: Bool = OnboardingState.shared.isComplete
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        // Load cached phase first (survives app restart race condition)
        // This prevents the phase from resetting to .path while PathProgressManager loads async
        if let cachedPhaseString = SharedUserStorage.retrieve(forKey: .cachedJourneyPhase, as: String.self),
           let cachedPhase = JourneyPhase(rawValue: cachedPhaseString) {
            currentPhase = cachedPhase
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Loaded cached phase: \(cachedPhase.displayName)")
        } else {
            // No cached phase - determine from current state (may be inaccurate on cold start)
            currentPhase = determineCurrentPhase()
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] No cached phase, determined: \(currentPhase.displayName)")
            // Cache the initial phase
            savePhaseToCache()
        }
        updateSessionContextJourneyCache()
        
        // Note: Phase entry tracking is now handled per-phase in JourneyAnalytics.logPhaseEntered()
        // Pre-app phases (onboarding, subscription) fire their own entry events
        // In-app phases get entry events via logPhaseCompleted() chain
        
        // Listen for path completion to auto-advance phase
        NotificationCenter.default.publisher(for: .pathStepCompletedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPhase()
            }
            .store(in: &cancellables)
        
        // Listen for journey reset notifications
        NotificationCenter.default.publisher(for: .aiOnboardingCleared)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPhase()
            }
            .store(in: &cancellables)
        
        // Listen for PathProgressManager to finish loading - then verify phase
        PathProgressManager.shared.$pathSteps
            .dropFirst() // Skip initial empty value
            .filter { !$0.isEmpty } // Only when steps are loaded
            .first() // Only need the first loaded value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.verifyAndRefreshPhase()
            }
            .store(in: &cancellables)
        
        logger.eventMessage("ProductJourneyManager: Initialized with phase=\(currentPhase.displayName)")
    }
    
    /// Verify phase after PathProgressManager loads and refresh if needed
    private func verifyAndRefreshPhase() {
        let determinedPhase = determineCurrentPhase()
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Verifying phase: cached=\(currentPhase.displayName), determined=\(determinedPhase.displayName)")
        
        // If determined phase differs from cached, update to the determined one
        // This handles cases where the state has changed (e.g., completed a step in previous session)
        if determinedPhase != currentPhase {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Phase mismatch - updating from \(currentPhase.displayName) to \(determinedPhase.displayName)")
            currentPhase = determinedPhase
            savePhaseToCache()
            updateSessionContextJourneyCache()
            refreshTrigger = UUID()
        }
    }
    
    // MARK: - Constants
    
    /// Number of routine sessions required to unlock customization phase
    static let routinesRequiredForCustomization = 3
    
    // MARK: - Phase Determination
    
    /// Determines the current phase based on completion states
    /// Called on init and after significant state changes
    /// Note: Pre-app phases (onboarding, subscription) are handled by
    /// ContentView and their respective state managers, not by this method.
    func determineCurrentPhase() -> JourneyPhase {
        journeyManagerLog(" ─────────────────────────────────────────────")
        journeyManagerLog(" [DETERMINE_PHASE] Checking journey state...")
        journeyManagerLog("   OnboardingState.isComplete: \(OnboardingState.shared.isComplete)")
        journeyManagerLog("   PathProgressManager.allStepsCompleted: \(PathProgressManager.shared.allStepsCompleted)")
        journeyManagerLog("   PathProgressManager.completedStepCount: \(PathProgressManager.shared.completedStepCount)/\(PathProgressManager.shared.totalStepCount)")
        
        // Pre-app phases are handled separately by ContentView
        // This method only determines in-app phases (path, dailyRoutines, customization)
        
        // Check if pre-app phases are complete
        // If not, return .path as a fallback (ContentView will intercept)
        if !OnboardingState.shared.isComplete {
            journeyManagerLog(" [DETERMINE_PHASE] ⚠️ Onboarding NOT complete - returning .path (ContentView will show onboarding)")
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Pre-app: onboarding not complete")
            return .path // ContentView will show onboarding instead
        }
        
        // Phase 1: Path - only for users who selected "dont_know_start" as their hurdle.
        // All other users skip directly to dailyRoutines (they have a specific problem to solve).
        let hurdle = UserPreferencesManager.shared.hurdle
        let wantsPath = hurdle == "dont_know_start"
        journeyManagerLog("[DETERMINE_PHASE] hurdle=\(hurdle ?? "nil") wantsPath=\(wantsPath)")
        if wantsPath && !PathProgressManager.shared.allStepsCompleted {
            journeyManagerLog(" [DETERMINE_PHASE] ✅ Phase = PATH (steps: \(PathProgressManager.shared.completedStepCount)/\(PathProgressManager.shared.totalStepCount))")
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Phase=path (dont_know_start hurdle, \(PathProgressManager.shared.completedStepCount)/\(PathProgressManager.shared.totalStepCount) steps)")
            return .path
        }
        if !wantsPath {
            journeyManagerLog("[DETERMINE_PHASE] Skipping Path phase - user has specific hurdle, routing to dailyRoutines")
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Skipping Path phase for hurdle=\(hurdle ?? "nil") - routing to dailyRoutines")
        }
        
        // Personalized Phase — Track B users stay in dailyRoutines permanently.
        // The recommendation orchestrator handles the progression
        // from pre-recorded sessions to AI-custom meditations based on hurdle fit quality.
        // The routine counter is preserved in storage for analytics but no longer gates phase transitions.
        let routineCount = getRoutineCompletionCount()
        journeyManagerLog(" [DETERMINE_PHASE] ✅ Phase = DAILY_ROUTINES (Personalized Phase, routines: \(routineCount) completed)")
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Phase=dailyRoutines (Personalized Phase, hurdle=\(hurdle ?? "nil"))")
        return .dailyRoutines
    }
    
    /// Save current phase to cache for persistence across app restarts
    private func savePhaseToCache() {
        SharedUserStorage.save(value: currentPhase.rawValue, forKey: .cachedJourneyPhase)
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Phase cached: \(currentPhase.displayName)")
    }
    
    /// Update SessionContextManager journey cache so session_start/complete include journey_phase and journey_track.
    private func updateSessionContextJourneyCache() {
        let track = UserPreferencesManager.shared.hurdle == "dont_know_start" ? "learning" : "personalized"
        SessionContextManager.shared.updateJourneyCache(phaseName: currentPhase.analyticsName, track: track)
    }
    
    /// Set the current phase directly (for dev mode use only).
    /// This bypasses normal phase determination logic.
    func setPhase(_ phase: JourneyPhase) {
        journeyManagerLog(" [SET_PHASE] Setting phase directly to: \(phase.displayName)")
        currentPhase = phase
        refreshTrigger = UUID()
        savePhaseToCache()
        updateSessionContextJourneyCache()
    }
    
    /// Sync pre-app phase published properties with their source state managers.
    /// This enables SwiftUI reactivity in ContentView for onboarding routing.
    func syncPreAppPhaseStates() {
        let newOnboardingComplete = OnboardingState.shared.isComplete
        if isOnboardingComplete != newOnboardingComplete {
            journeyManagerLog(" [SYNC] isOnboardingComplete: \(isOnboardingComplete) → \(newOnboardingComplete)")
            isOnboardingComplete = newOnboardingComplete
        }
    }
    
    /// Refresh and update the current phase
    func refreshPhase() {
        let previousPhase = currentPhase
        currentPhase = determineCurrentPhase()
        refreshTrigger = UUID()
        
        // Sync pre-app phase states for SwiftUI reactivity
        syncPreAppPhaseStates()
        
        // Always update SessionContextManager cache so session analytics include journey context
        updateSessionContextJourneyCache()
        
        // Log phase transition if changed
        if previousPhase != currentPhase {
            // Save to cache whenever phase changes
            savePhaseToCache()
            
            journeyManagerLog(" refreshPhase() - PHASE TRANSITION!")
            journeyManagerLog("    \(previousPhase.displayName) (order=\(previousPhase.order)) → \(currentPhase.displayName) (order=\(currentPhase.order))")
            logger.eventMessage("ProductJourneyManager: Phase transition \(previousPhase.displayName) -> \(currentPhase.displayName)")
            
            // Only fire journey_phase_completed for the path phase if the user is actually
            // on the Learning track (dont_know_start). Track B users are never in the path
            // phase — their currentPhase was cached as .path only as a pre-app fallback while
            // onboarding/subscription were incomplete. Firing path_completed for them produces
            // a false Mixpanel event implying they "finished" the structured course.
            let isLearningTransition = previousPhase == .path && UserPreferencesManager.shared.hurdle == "dont_know_start"
            let isMeaningfulTransition = previousPhase != .path || isLearningTransition
            
            if isMeaningfulTransition {
                JourneyAnalytics.logPhaseCompleted(phase: previousPhase, nextPhase: currentPhase)
            } else {
                journeyManagerLog("[refreshPhase] Skipping spurious path→* completion (Track B user, hurdle=\(UserPreferencesManager.shared.hurdle ?? "nil"))")
                logger.aiChat("🧠 AI_DEBUG [JOURNEY] Skipped path completion event — Track B user never entered Learning Phase")
                // Still fire the entry event for the phase the user is actually entering
                JourneyAnalytics.logPhaseEntered(phase: currentPhase, trigger: "phase_completion")
            }
        }
        // Removed verbose "No phase change" logging - it's expected and noisy
    }
    
    // MARK: - Recommendations
    
    /// Get the appropriate recommendation for the user's current journey phase.
    /// Returns nil if no recommendation should be shown.
    func getRecommendation() -> JourneyRecommendation? {
        // Refresh phase first to ensure we're up to date
        currentPhase = determineCurrentPhase()
        
        switch currentPhase {
        case .onboarding, .subscription:
            // Pre-app phases don't show recommendations
            return nil
            
        case .path:
            return getPathRecommendation()
            
        case .dailyRoutines:
            return getDailyRoutineRecommendation()
            
        case .customization:
            // Future: Return customization recommendation
            return nil
        }
    }
    
    /// Get path step recommendation from PathProgressManager
    private func getPathRecommendation() -> JourneyRecommendation? {
        guard PathProgressManager.shared.shouldRecommendPath() else {
            logger.aiChat("🧭 JOURNEY: Path recommendation skipped - shouldRecommendPath=false")
            return nil
        }
        
        guard let step = PathProgressManager.shared.nextStep,
              let message = PathProgressManager.shared.getRecommendationMessage() else {
            logger.aiChat("🧭 JOURNEY: Path recommendation skipped - no next step or message")
            return nil
        }
        
        let welcomeGreeting = PathProgressManager.shared.getWelcomeGreeting()
        
        logger.aiChat("🧭 JOURNEY: Returning path recommendation for step=\(step.id)")
        return .path(step: step, message: message, welcomeGreeting: welcomeGreeting)
    }
    
    /// Legacy journey hook for daily routines. Sensei no longer surfaces Explore catalog sessions here—
    /// users open Library for pre-recorded routines; chat suggestions use custom meditations via
    /// ``RecommendationContextEngine`` / ``DualRecommendationOrchestrator``.
    private func getDailyRoutineRecommendation() -> JourneyRecommendation? {
        logger.aiChat("🧭 JOURNEY: getDailyRoutineRecommendation() — disabled (Sensei is custom-only; Explore in Library)")
        return nil
    }
    
    /// Get daily routine recommendation asynchronously, waiting for audio files to load
    /// Use this when you need to ensure files are loaded before checking
    func getDailyRoutineRecommendationAsync(completion: @escaping (JourneyRecommendation?) -> Void) {
        logger.aiChat("🧭 JOURNEY: getDailyRoutineRecommendationAsync() — disabled (Sensei is custom-only; Explore in Library)")
        completion(nil)
    }
    
    // MARK: - Routine Completion Tracking (for Customization Unlock)
    
    /// Get the current count of completed routine sessions
    func getRoutineCompletionCount() -> Int {
        return SharedUserStorage.retrieve(forKey: .completedRoutineSessionsCount, as: Int.self) ?? 0
    }
    
    /// Increment the routine completion count and check for phase transition
    /// Call this when a session from the "routines" category is completed
    func incrementRoutineCompletionCount() {
        let previousCount = getRoutineCompletionCount()
        let newCount = previousCount + 1
        SharedUserStorage.save(value: newCount, forKey: .completedRoutineSessionsCount)
        
        journeyManagerLog(" incrementRoutineCompletionCount()")
        journeyManagerLog("    Routine count: \(previousCount) -> \(newCount)/\(Self.routinesRequiredForCustomization)")
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Routine completed! Count: \(previousCount) -> \(newCount)/\(Self.routinesRequiredForCustomization)")
        
        // Check if this unlocks customization
        if newCount >= Self.routinesRequiredForCustomization && previousCount < Self.routinesRequiredForCustomization {
            journeyManagerLog(" 🎉 CUSTOMIZATION UNLOCKED!")
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] 🎉 UNLOCK! Customization phase unlocked!")
            
            // Reset slot suggestion so customization phase gets a fresh auto-suggestion
            // (the slot may have been used for the routine they just completed)
            ExploreRecommendationManager.shared.resetSlotSuggestion()
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Slot reset for fresh customization suggestion")
            
            // Refresh phase to update to customization
            let previousPhase = currentPhase
            currentPhase = determineCurrentPhase()
            refreshTrigger = UUID()
            
            // Save to cache
            savePhaseToCache()
            
            // Log analytics for phase transition
            if previousPhase != currentPhase {
                journeyManagerLog(" ⚡️ PHASE TRANSITION: \(previousPhase.displayName) -> \(currentPhase.displayName)")
                // User completed previousPhase (dailyRoutines) and is entering currentPhase (customization)
                JourneyAnalytics.logPhaseCompleted(phase: previousPhase, nextPhase: currentPhase)
            }
            
            // Post notification for UI to react (includes unlock flag for celebration)
            NotificationCenter.default.post(
                name: .journeyPhaseChanged,
                object: nil,
                userInfo: [
                    "newPhase": currentPhase,
                    "isUnlock": true,
                    "previousPhase": previousPhase
                ]
            )
        }
    }
    
    /// Check if customization phase is unlocked
    func isCustomizationUnlocked() -> Bool {
        return getRoutineCompletionCount() >= Self.routinesRequiredForCustomization
    }
    
    /// Reset routine completion count (for dev mode)
    func resetRoutineCompletionCount() {
        SharedUserStorage.delete(forKey: .completedRoutineSessionsCount)
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Routine completion count reset")
    }
    
    // MARK: - Dev Mode Controls
    
    /// Reset the entire product journey to the beginning.
    /// Clears all progress and returns user to the start of the Path.
    /// Optionally also resets pre-app phases (onboarding, subscription).
    /// - Parameter includePreAppPhases: If true, also resets onboarding and subscription.
    /// - Parameter skipAnalytics: If true, skips firing analytics (caller will handle it).
    func resetJourney(includePreAppPhases: Bool = false, skipAnalytics: Bool = false) {
        journeyManagerLog(" ═══════════════════════════════════════════════════════════")
        journeyManagerLog(" [RESET_JOURNEY] 🔄 Starting journey reset")
        journeyManagerLog(" [RESET_JOURNEY] includePreAppPhases=\(includePreAppPhases), skipAnalytics=\(skipAnalytics)")
        journeyManagerLog(" ───────────────────────────────────────────────────────────")
        
        // Log state BEFORE reset
        journeyManagerLog(" [RESET_JOURNEY] BEFORE reset state:")
        journeyManagerLog("   - OnboardingState.isComplete: \(OnboardingState.shared.isComplete)")
        journeyManagerLog("   - currentPhase: \(currentPhase.displayName)")
        journeyManagerLog("   - PathProgressManager.completedStepCount: \(PathProgressManager.shared.completedStepCount)")
        
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] 🔄 Resetting entire journey...")
        
        // Clear AI chat history from storage
        SharedUserStorage.delete(forKey: .aiChatHistory)
        journeyManagerLog(" [RESET_JOURNEY] ✓ Cleared AI chat history")
        
        // Clear first AI meditation flag so user gets their free meditation again
        SharedUserStorage.delete(forKey: .hasCreatedFirstAIMeditation)
        
        // Clear first custom recommendation flag so first meditation gets goal+hurdle prompt again
        SharedUserStorage.delete(forKey: .hasReceivedFirstCustomMeditation)
        
        // Clear first session complete flag so user gets free-first-session behavior again
        SharedUserStorage.delete(forKey: .hasCompletedFirstSession)
        
        // Clear onboarding responses (legacy key)
        SharedUserStorage.delete(forKey: .onboardingResponses)
        
        // Clear unified user preferences (hurdle, goal, familiarity) so re-running onboarding
        // writes fresh values and determineCurrentPhase() routes to the correct track.
        UserPreferencesManager.shared.reset()
        journeyManagerLog(" [RESET_JOURNEY] ✓ Cleared UserPreferencesManager (hurdle/goal/familiarity reset)")
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] UserPreferencesManager reset — onboarding choices cleared")
        
        // Clear user profile so first meditation detection works correctly
        UserProfileManager.shared.reset()
        journeyManagerLog(" [RESET_JOURNEY] ✓ Cleared user profile and meditation flags")
        
        // Clear Path step completions and forced completion flag
        PracticeManager.shared.clearPathStepsByPattern()
        PathProgressManager.shared.resetForcedCompletion()
        PathProgressManager.shared.refreshProgress()
        journeyManagerLog(" [RESET_JOURNEY] ✓ Cleared Path progress")
        
        // Clear Daily Routines phase state
        resetRoutineCompletionCount()
        ExploreRecommendationManager.shared.resetSlotSuggestion()
        journeyManagerLog(" [RESET_JOURNEY] ✓ Cleared routine completion count")
        
        // Optionally reset pre-app phases (onboarding)
        if includePreAppPhases {
            OnboardingState.shared.reset()
            SubscriptionState.shared.reset()
            journeyManagerLog(" [RESET_JOURNEY] ✓ Reset pre-app phases (Onboarding)")
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Pre-app phases also reset")
        }
        
        // Reset phase entry tracking so events fire again for new journey
        JourneyAnalytics.resetEntryTracking(includePreAppPhases: includePreAppPhases)
        journeyManagerLog(" [RESET_JOURNEY] ✓ Reset phase entry tracking")
        
        // Clear session milestone and first-session flags so they can fire again
        if includePreAppPhases {
            SharedUserStorage.delete(forKey: .loggedSessionMilestones)
            SharedUserStorage.delete(forKey: .loggedFirstSessionStarted)
            journeyManagerLog(" [RESET_JOURNEY] ✓ Cleared session milestone and first-session flags")
        }
        
        // Determine the target first phase based on what was reset
        // If pre-app phases were reset, the first phase is .onboarding
        // Otherwise, the first phase is .path (first active/in-app phase)
        let targetFirstPhase: JourneyPhase = includePreAppPhases ? .onboarding : JourneyPhase.firstPhase
        
        // Update phase (always set to firstPhase for internal tracking - ContentView will intercept pre-app)
        currentPhase = JourneyPhase.firstPhase
        refreshTrigger = UUID()
        
        // Save to cache and update SessionContextManager journey cache
        savePhaseToCache()
        updateSessionContextJourneyCache()
        
        // Sync pre-app phase states for SwiftUI reactivity (ContentView observes these)
        syncPreAppPhaseStates()
        
        // Log state AFTER reset
        journeyManagerLog(" ───────────────────────────────────────────────────────────")
        journeyManagerLog(" [RESET_JOURNEY] AFTER reset state:")
        journeyManagerLog("   - OnboardingState.isComplete: \(OnboardingState.shared.isComplete)")
        journeyManagerLog("   - currentPhase: \(currentPhase.displayName)")
        journeyManagerLog("   - targetFirstPhase: \(targetFirstPhase.displayName)")
        
        // Fire analytics only if not skipped (caller may want to fire their own)
        if !skipAnalytics {
            // Update OneSignal tags to reflect reset state
            Task { @MainActor in
                JourneyAnalytics.updateOneSignalPhaseTag(targetFirstPhase)
            }
            
            // Log phase entry for funnel analysis
            JourneyAnalytics.logPhaseEntered(phase: targetFirstPhase, trigger: "journey_reset")
        }
        
        // Post notification to notify any open AI chat views
        NotificationCenter.default.post(name: .aiOnboardingCleared, object: nil)
        
        journeyManagerLog(" [RESET_JOURNEY] ✅ Journey reset COMPLETE")
        journeyManagerLog(" [RESET_JOURNEY] Expected next flow: \(includePreAppPhases ? "Onboarding >> Path" : "Path")")
        journeyManagerLog(" ═══════════════════════════════════════════════════════════")
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] ✅ Journey reset complete - phase=\(currentPhase.displayName)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the journey phase changes
    static let journeyPhaseChanged = Notification.Name("journeyPhaseChanged")
    
    /// Posted when the journey is reset
    static let journeyReset = Notification.Name("journeyReset")
    
    /// Posted to show a phase transition (dev mode) - includes fromPhase and toPhase in userInfo
    static let journeyShowTransition = Notification.Name("journeyShowTransition")
}
