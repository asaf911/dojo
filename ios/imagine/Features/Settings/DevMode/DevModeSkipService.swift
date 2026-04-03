//
//  DevModeSkipService.swift
//  imagine
//
//  Created by Cursor on 2/4/26.
//
//  Centralized service for dev mode phase skipping.
//  Provides clean, testable skip functionality with proper state verification.
//

import Foundation
import SwiftUI

/// Centralized service for dev mode phase skipping.
/// Provides clean, testable skip functionality with proper state verification.
@MainActor
final class DevModeSkipService: ObservableObject {
    
    static let shared = DevModeSkipService()
    
    @Published private(set) var isSkipping = false
    @Published private(set) var lastSkipResult: DevModeSkipResult?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Skip to a specific destination in the journey.
    /// Returns a result indicating success or failure with details.
    @discardableResult
    func skipTo(_ destination: JourneySkipDestination) async -> DevModeSkipResult {
        guard !isSkipping else {
            return .failure("Skip already in progress")
        }
        
        isSkipping = true
        defer { isSkipping = false }
        
        #if DEBUG
        print("📊 DEV_SKIP: ═══════════════════════════════════════════════════")
        print("📊 DEV_SKIP: Skipping to: \(destination.displayName)")
        print("📊 DEV_SKIP: Target phase: \(destination.targetPhase.displayName)")
        #endif
        
        let snapshot = destination.stateSnapshot
        
        // 1. Clear chat history for fresh experience
        clearChatHistory()
        
        // 2. Apply state snapshot
        applySnapshot(snapshot, for: destination)
        
        // 3. Sync published states for SwiftUI reactivity
        ProductJourneyManager.shared.syncPreAppPhaseStates()
        
        // 4. Update analytics
        JourneyAnalytics.logPhaseEntered(phase: destination.targetPhase, trigger: "dev_mode")
        Task { @MainActor in
            JourneyAnalytics.updateOneSignalPhaseTag(destination.targetPhase)
        }
        
        // 5. Notify UI to refresh
        NotificationCenter.default.post(name: .aiOnboardingCleared, object: nil)
        
        // 6. Verify state
        let verification = verifyState(for: destination)
        
        #if DEBUG
        print("📊 DEV_SKIP: Verification: \(verification.summary)")
        print("📊 DEV_SKIP: ═══════════════════════════════════════════════════")
        #endif
        
        let result = DevModeSkipResult.success(
            destination: destination,
            verification: verification
        )
        lastSkipResult = result
        
        return result
    }
    
    // MARK: - State Application
    
    private func applySnapshot(_ snapshot: JourneyStateSnapshot, for destination: JourneySkipDestination) {
        // Pre-app phases
        if snapshot.onboardingComplete {
            ensureOnboardingComplete()
        } else {
            resetOnboarding()
            // Full funnel reset: clear session count and journey flags so
            // journey_first_session_started and journey_session_milestone 1–3 can fire again.
            resetSessionAndJourneyFunnelState()
        }
        
        if snapshot.subscriptionComplete {
            ensureSubscriptionComplete()
        } else {
            resetSubscription()
        }
        
        // Path progress
        switch snapshot.pathProgress {
        case .reset:
            resetPath()
            // Clear first-welcome flag so it shows again from the start
            SharedUserStorage.delete(forKey: .hasShownFirstWelcome)
        case .lastStep:
            setPathToLastStep()
        case .complete:
            completeAllPath()
        }
        
        // Routine count
        setRoutineCount(snapshot.routineCount)

        // Timely recommendation override for dev testing.
        // Timely destinations force the time slot; all other destinations clear it.
        applyTimelySlotOverride(for: destination)
        
        // Set hurdle override so determineCurrentPhase() routes to the correct track.
        // Each skip destination declares its expected hurdle via JourneyStateSnapshot.hurdleOverride.
        if let hurdleOverride = snapshot.hurdleOverride {
            UserPreferencesManager.shared.update { prefs in
                prefs.hurdle = hurdleOverride
            }
            #if DEBUG
            print("📊 DEV_SKIP: [APPLY_SNAPSHOT] Set hurdle=\(hurdleOverride) from snapshot")
            #endif
        }
        
        // Always reset all slot keys for fresh recommendation
        // (timely + non-timely + legacy fallback key).
        ExploreRecommendationManager.shared.resetSlotSuggestion()
        
        // Reset entry tracking so dev mode doesn't pollute real user analytics
        // Pre-app phases reset based on whether we're resetting them
        let includePreAppPhases = !snapshot.onboardingComplete
        JourneyAnalytics.resetEntryTracking(includePreAppPhases: includePreAppPhases)
        
        // Set the target phase
        ProductJourneyManager.shared.setPhase(snapshot.targetPhase)
    }
    
    // MARK: - Pre-App Phase Helpers
    
    private func clearChatHistory() {
        SharedUserStorage.delete(forKey: .aiChatHistory)
        // Also clear the in-memory dedup set so back-to-back dev test runs don't
        // inherit excluded IDs from the previous scenario and fall through to custom-only.
        DualRecommendationOrchestrator.shared.clearRecentlyRecommended()
        ContextStateManager.shared.clear()
        #if DEBUG
        print("📊 DEV_SKIP: [CLEAR_CHAT] Cleared chat history + recommendation dedup IDs + context state")
        #endif
    }
    
    private func ensureOnboardingComplete() {
        if !OnboardingState.shared.isComplete {
            OnboardingState.shared.markStarted(variantId: "dev_skip")
            OnboardingState.shared.markCompleted()
        }
        // Safety net: if the snapshot provided no hurdleOverride AND hurdle is still nil
        // (e.g. after a full reset), default to "dont_know_start" so determineCurrentPhase()
        // has a valid value. Skip destinations that carry a hurdleOverride in their snapshot
        // will overwrite this value in applySnapshot() immediately after.
        if UserPreferencesManager.shared.hurdle == nil {
            UserPreferencesManager.shared.update { prefs in
                prefs.hurdle = "dont_know_start"
                prefs.goal = "spiritual_growth"
            }
            #if DEBUG
            print("📊 DEV_SKIP: [ENSURE_ONBOARDING] Set safety-net defaults: hurdle=dont_know_start goal=spiritual_growth")
            #endif
        }
    }
    
    private func resetOnboarding() {
        OnboardingState.shared.reset()
        // Also clear unified user preferences (hurdle, goal, familiarity) so that
        // re-running onboarding writes fresh values and recommendations update accordingly.
        // Without this, UserPreferencesManager keeps the old hurdle and the journey
        // routing in determineCurrentPhase() stays on the previous track.
        UserPreferencesManager.shared.reset()
        #if DEBUG
        print("📊 DEV_SKIP: [RESET_ONBOARDING] Cleared OnboardingState + UserPreferencesManager (hurdle/goal/familiarity reset)")
        #endif
    }
    
    /// Resets session count and journey funnel flags so dev mode funnel testing
    /// can reproduce journey_first_session_started and journey_session_milestone 1–3.
    /// Also clears hasCompletedFirstSession so subscription gating can be tested.
    private func resetSessionAndJourneyFunnelState() {
        SharedUserStorage.save(value: 0, forKey: .sessionCount)
        SharedUserStorage.delete(forKey: .loggedFirstSessionStarted)
        SharedUserStorage.delete(forKey: .loggedSessionMilestones)
        SharedUserStorage.delete(forKey: .hasCompletedFirstSession)
        FirestoreManager.shared.updateSessionCount(0)
        #if DEBUG
        print("📊 DEV_SKIP: [RESET_FUNNEL] sessionCount=0, cleared loggedFirstSessionStarted, loggedSessionMilestones, hasCompletedFirstSession")
        #endif
    }
    
    /// Simulate post-first-session user (will be gated on play until subscribed)
    private func ensureSubscriptionComplete() {
        SharedUserStorage.save(value: true, forKey: .hasCompletedFirstSession)
    }
    
    private func resetSubscription() {
        SharedUserStorage.delete(forKey: .hasCompletedFirstSession)
        SubscriptionState.shared.reset()
    }
    
    // MARK: - Path Progress Helpers
    
    private func resetPath() {
        PathProgressManager.shared.resetForcedCompletion()
        PracticeManager.shared.clearPathStepsByPattern()
        PathProgressManager.shared.refreshProgress()
    }
    
    private func setPathToLastStep() {
        PathProgressManager.shared.resetForcedCompletion()
        PracticeManager.shared.clearPathStepsByPattern()
        
        let steps = PathProgressManager.shared.pathSteps
        if steps.count > 1 {
            for step in steps.dropLast() {
                PracticeManager.shared.markPracticeAsCompleted(practiceID: step.id)
            }
        }
        PathProgressManager.shared.refreshProgress()
    }
    
    private func completeAllPath() {
        PathProgressManager.shared.forceMarkAllStepsCompleted()
    }
    
    // MARK: - Routine Count Helper
    
    private func setRoutineCount(_ count: Int) {
        SharedUserStorage.save(value: count, forKey: .completedRoutineSessionsCount)
    }

    private func applyTimelySlotOverride(for destination: JourneySkipDestination) {
        if let slotOverride = destination.timelySlotOverride {
            SharedUserStorage.save(value: slotOverride, forKey: .devTimelySlotOverride)
            SharedUserStorage.save(value: true, forKey: .devUseTimelySlotOverride)
            #if DEBUG
            print("📊 DEV_SKIP: [TIMELY_OVERRIDE] Set slot override=\(slotOverride)")
            #endif
        } else {
            SharedUserStorage.delete(forKey: .devTimelySlotOverride)
            SharedUserStorage.delete(forKey: .devUseTimelySlotOverride)
            #if DEBUG
            print("📊 DEV_SKIP: [TIMELY_OVERRIDE] Cleared slot override")
            #endif
        }
    }
    
    // MARK: - Verification
    
    private func verifyState(for destination: JourneySkipDestination) -> DevModeStateVerification {
        let expected = destination.stateSnapshot
        
        let hasCompletedFirstSession = SharedUserStorage.retrieve(forKey: .hasCompletedFirstSession, as: Bool.self) ?? false
        return DevModeStateVerification(
            phaseMatches: ProductJourneyManager.shared.currentPhase == expected.targetPhase,
            onboardingMatches: OnboardingState.shared.isComplete == expected.onboardingComplete,
            subscriptionMatches: hasCompletedFirstSession == expected.subscriptionComplete,
            pathMatches: verifyPathProgress(expected.pathProgress),
            routineCountMatches: ProductJourneyManager.shared.getRoutineCompletionCount() == expected.routineCount
        )
    }
    
    private func verifyPathProgress(_ expected: PathProgress) -> Bool {
        switch expected {
        case .reset:
            return PathProgressManager.shared.completedStepCount == 0
        case .lastStep:
            let total = PathProgressManager.shared.totalStepCount
            // If steps haven't loaded yet, we can't verify last step precisely
            if total == 0 { return true }
            return PathProgressManager.shared.completedStepCount == total - 1
        case .complete:
            return PathProgressManager.shared.allStepsCompleted
        }
    }
}
