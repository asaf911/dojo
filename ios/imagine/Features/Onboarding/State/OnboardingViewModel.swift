//
//  OnboardingViewModel.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  View model driving the onboarding flow.
//  Manages step navigation, user responses, and analytics.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Onboarding View Model

@MainActor
class OnboardingViewModel: ObservableObject {
    
    // MARK: - Published State
    
    /// Current step in the flow
    @Published private(set) var currentStep: OnboardingStep = .welcome
    
    /// Whether a transition is in progress (prevents double-taps)
    @Published private(set) var isTransitioning: Bool = false
    
    /// User responses collected during the flow
    @Published var responses = OnboardingResponses()
    
    /// Timer for auto-advancing screens (like Building)
    @Published private(set) var autoAdvanceProgress: Double = 0
    
    /// Sub-progress for building screen (0.0 to 1.0 as each of 3 items complete)
    @Published var buildingSubProgress: Double = 0
    
    /// Whether Mindful Minutes connection is in progress
    @Published var isConnectingMindfulMinutes: Bool = false
    
    /// Whether Heart Rate enable is in progress
    @Published var isConnectingHeartRate: Bool = false
    
    // MARK: - Dependencies
    
    /// Flow configuration (supports A/B testing)
    let configuration: OnboardingConfiguration
    
    /// Persistent state manager
    private let state = OnboardingState.shared
    
    /// Analytics handler
    private let analytics = OnboardingAnalytics.shared
    
    /// Timer for auto-advance screens
    private var autoAdvanceTimer: Timer?
    private var autoAdvanceStartTime: Date?
    
    // MARK: - Computed Properties
    
    /// Total steps in this configuration
    var totalSteps: Int {
        configuration.totalSteps
    }
    
    /// Current step index within active steps
    var currentStepIndex: Int {
        configuration.index(of: currentStep) ?? 0
    }
    
    /// Progress for progress bar (0.0 to 1.0)
    /// Excludes welcome screen from calculation
    /// Shows relative progress: 1/6 for first screen, 6/6 for last screen
    /// For building screen, interpolates based on buildingSubProgress
    var progress: Double {
        let progressSteps = configuration.activeSteps.filter { $0.showsProgressBar }
        guard let currentIndex = progressSteps.firstIndex(of: currentStep),
              progressSteps.count > 0 else {
            return 0
        }
        
        // Base progress for current step
        let baseProgress = Double(currentIndex + 1) / Double(progressSteps.count)
        
        // For building screen, interpolate between current step progress and 100%
        if currentStep == .building {
            // buildingSubProgress goes from 0 to 1 as 3 items complete
            // We want to fill the remaining progress to reach 100%
            let remainingToFull = 1.0 - baseProgress
            return baseProgress + (remainingToFull * buildingSubProgress)
        }
        
        return baseProgress
    }
    
    /// Whether the user can go back from current step
    var canGoBack: Bool {
        currentStep.canGoBack && currentStepIndex > 0
    }
    
    /// Whether this is the last step
    var isLastStep: Bool {
        currentStep == configuration.activeSteps.last
    }
    
    /// Whether the current step requires input before advancing
    var requiresInput: Bool {
        switch currentStep {
        case .goals:
            return responses.selectedGoal == nil
        case .hurdle:
            return responses.selectedHurdle == nil
        default:
            return false
        }
    }
    
    // MARK: - Initialization
    
    init(configuration: OnboardingConfiguration = .default) {
        self.configuration = configuration
        
        print("🚀 ONBOARDING_VM: ═══════════════════════════════════════")
        print("🚀 ONBOARDING_VM: Initializing with variant=\(configuration.variantId)")
        
        // Resume from saved state if available
        if let savedStep = state.currentStep,
           configuration.includes(savedStep) {
            self.currentStep = savedStep
            self.responses = state.responses
            print("🚀 ONBOARDING_VM: Resuming from saved step=\(savedStep.analyticsName)")
        } else {
            // Start from the beginning
            self.currentStep = configuration.activeSteps.first ?? .welcome
            print("🚀 ONBOARDING_VM: Starting fresh at step=\(currentStep.analyticsName)")
        }
        
        print("🚀 ONBOARDING_VM: ═══════════════════════════════════════")
    }
    
    // MARK: - Flow Start
    
    /// Called when the onboarding view appears for the first time
    func onFlowStart() {
        print("🚀 ONBOARDING_VM: [FLOW_START] onFlowStart() called")
        print("🚀 ONBOARDING_VM: [FLOW_START] Current step: \(currentStep.analyticsName) (\(currentStepIndex + 1)/\(totalSteps))")
        
        // Only mark started if not already started
        if state.startedAt == nil {
            print("🚀 ONBOARDING_VM: [FLOW_START] First time start - marking started")
            state.markStarted(variantId: configuration.variantId)
            analytics.logOnboardingStarted(
                variantId: configuration.variantId,
                totalSteps: totalSteps
            )
            
            // Log journey phase entry for funnel analysis
            // The per-phase tracking in JourneyAnalytics prevents duplicates
            JourneyAnalytics.logPhaseEntered(phase: .onboarding, trigger: "new_user")
        } else {
            print("🚀 ONBOARDING_VM: [FLOW_START] Resuming existing flow")
            
            // Ensure entry is logged even for returning users (deduplication handled internally)
            JourneyAnalytics.logPhaseEntered(phase: .onboarding, trigger: "new_user")
        }
        
        // Log current step view
        analytics.logStepViewed(
            step: currentStep,
            stepIndex: currentStepIndex,
            totalSteps: totalSteps
        )
        
        // Start auto-advance if needed
        startAutoAdvanceIfNeeded()
    }
    
    // MARK: - Navigation
    
    /// Advance to the next step
    func advance() {
        guard !isTransitioning else {
            print("🚀 ONBOARDING_VM: [ADVANCE] Blocked - transition in progress")
            return
        }
        
        print("🚀 ONBOARDING_VM: [ADVANCE] From step: \(currentStep.analyticsName)")
        
        // Stop any auto-advance timer
        stopAutoAdvance()
        
        // Save current responses
        state.responses = responses
        
        // Log step completion
        analytics.logStepCompleted(
            step: currentStep,
            stepIndex: currentStepIndex,
            totalSteps: totalSteps,
            responses: responses
        )
        
        // Check if this is the last step
        guard let nextStep = configuration.nextStep(after: currentStep) else {
            print("🚀 ONBOARDING_VM: [ADVANCE] Last step reached - completing onboarding")
            completeOnboarding()
            return
        }
        
        print("🚀 ONBOARDING_VM: [ADVANCE] To step: \(nextStep.analyticsName)")
        
        // Perform transition
        transitionTo(nextStep)
    }
    
    /// Go back to the previous step
    func goBack() {
        guard canGoBack, !isTransitioning else {
            print("🚀 ONBOARDING_VM: [GO_BACK] Blocked - canGoBack=\(canGoBack) transitioning=\(isTransitioning)")
            return
        }
        
        print("🚀 ONBOARDING_VM: [GO_BACK] From step: \(currentStep.analyticsName)")
        
        // Stop any auto-advance timer
        stopAutoAdvance()
        
        guard let prevStep = configuration.previousStep(before: currentStep) else {
            print("🚀 ONBOARDING_VM: [GO_BACK] No previous step found")
            return
        }
        
        print("🚀 ONBOARDING_VM: [GO_BACK] To step: \(prevStep.analyticsName)")
        transitionTo(prevStep, isForward: false)
    }
    
    /// Skip the current step (if allowed)
    func skip() {
        guard configuration.allowSkip, !isTransitioning else {
            print("🚀 ONBOARDING_VM: [SKIP] Blocked - allowSkip=\(configuration.allowSkip) transitioning=\(isTransitioning)")
            return
        }
        
        print("🚀 ONBOARDING_VM: [SKIP] Skipping step: \(currentStep.analyticsName)")
        analytics.logSkipTapped(step: currentStep, stepIndex: currentStepIndex)
        advance()
    }
    
    // MARK: - Transitions
    
    private func transitionTo(_ step: OnboardingStep, isForward: Bool = true) {
        isTransitioning = true
        
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = step
        }
        
        // Persist progress
        state.currentStep = step
        
        // Log step view
        analytics.logStepViewed(
            step: step,
            stepIndex: configuration.index(of: step) ?? 0,
            totalSteps: totalSteps
        )
        
        // Complete transition after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isTransitioning = false
            self?.startAutoAdvanceIfNeeded()
        }
    }
    
    // MARK: - Auto-Advance (for Building screen)
    
    private func startAutoAdvanceIfNeeded() {
        guard currentStep.autoAdvances,
              let duration = currentStep.minimumDisplaySeconds else {
            return
        }
        
        autoAdvanceProgress = 0
        let startTime = Date()
        autoAdvanceStartTime = startTime
        
        // Update progress every 0.05 seconds
        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / duration, 1.0)
            
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                self.autoAdvanceProgress = progress
                
                if progress >= 1.0 {
                    timer.invalidate()
                    self.advance()
                }
            }
        }
    }
    
    private func stopAutoAdvance() {
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
        autoAdvanceStartTime = nil
        autoAdvanceProgress = 0
    }
    
    // MARK: - Input Handling
    
    /// Set familiarity level from Sensei screen
    func setFamiliarity(_ displayName: String) {
        if let familiarity = OnboardingFamiliarity(displayName: displayName) {
            responses.selectedFamiliarity = familiarity
            analytics.logOptionSelected(step: .sensei, optionId: familiarity.rawValue)
        }
    }
    
    /// Select a goal (single-select)
    func selectGoal(_ goal: OnboardingGoal) {
        responses.selectedGoal = goal
        analytics.logOptionSelected(step: .goals, optionId: goal.rawValue)
    }
    
    /// Select a hurdle option (single-select, goal-specific)
    func selectHurdle(_ option: HurdleScreenContent.HurdleOption) {
        responses.selectedHurdle = option
        analytics.logOptionSelected(step: .hurdle, optionId: option.id)
    }
    
    /// Mark Mindful Minutes as connected and log the result
    /// - Parameters:
    ///   - connected: Whether Mindful Minutes was connected
    ///   - result: The result type ("authorized", "denied", "skipped", "already_authorized")
    func markMindfulMinutesConnected(_ connected: Bool, result: String) {
        responses.connectedMindfulMinutes = connected
        PermissionAnalytics.log(permission: "mindful_minutes", result: result, source: "onboarding")
    }
    
    /// Mark Heart Rate as enabled and log the result
    /// Note: For heart rate (read permission), we cannot confirm actual authorization
    /// - Parameter result: The result type ("prompted", "skipped")
    func markHeartRateEnabled(result: String) {
        // For heart rate, we set enabled=true when prompted (soft confirmation)
        let enabled = (result == "prompted")
        responses.enabledHeartRate = enabled
        PermissionAnalytics.log(permission: "heart_rate", result: result, source: "onboarding")
    }
    
    // MARK: - Completion
    
    private func completeOnboarding() {
        print("📊 JOURNEY: ═══════════════════════════════════════════════════")
        print("📊 JOURNEY: [ONBOARDING_COMPLETE] Completing onboarding flow")
        
        // Save final state to OnboardingState (legacy storage for backward compatibility)
        state.responses = responses
        state.markCompleted()
        
        // Sync ProductJourneyManager published states for SwiftUI reactivity
        Task { @MainActor in
            ProductJourneyManager.shared.syncPreAppPhaseStates()
        }
        
        // Save to unified UserPreferences (new consolidated storage) - batched for single persist/sync
        UserPreferencesManager.shared.update { prefs in
            prefs.goal = responses.selectedGoal?.rawValue
            prefs.hurdle = responses.selectedHurdle?.id
            prefs.familiarity = responses.selectedFamiliarity?.rawValue
            prefs.connectedHealthKit = responses.connectedHealthKit
            prefs.enabledHeartRate = responses.enabledHeartRate
            prefs.connectedMindfulMinutes = responses.connectedMindfulMinutes
            prefs.onboardingCompletedAt = Date()
        }
        UserPreferencesManager.shared.updateMixpanelProperties()
        
        print("📊 JOURNEY: [ONBOARDING_COMPLETE] Responses saved:")
        print("📊 JOURNEY:   - Goal: \(responses.selectedGoal?.rawValue ?? "none")")
        print("📊 JOURNEY:   - Hurdle: \(responses.selectedHurdle?.id ?? "none")")
        print("📊 JOURNEY:   - Mindful Minutes: \(responses.connectedMindfulMinutes)")
        print("📊 JOURNEY:   - Heart Rate: \(responses.enabledHeartRate)")
        print("📊 JOURNEY:   - HealthKit (legacy): \(responses.connectedHealthKit)")
        
        // Log onboarding-specific analytics
        analytics.logOnboardingCompleted(
            responses: responses,
            variantId: configuration.variantId,
            totalSteps: totalSteps,
            duration: state.duration
        )
        
        // Log journey phase transition (onboarding -> subscription)
        JourneyAnalytics.logPhaseCompleted(phase: .onboarding, nextPhase: .subscription)
        
        print("📊 JOURNEY: [ONBOARDING_COMPLETE] Posting notification -> transitioning to subscription")
        print("📊 JOURNEY: [ONBOARDING_COMPLETE] OnboardingState.isComplete=\(OnboardingState.shared.isComplete)")
        print("📊 JOURNEY: [ONBOARDING_COMPLETE] SubscriptionState.isComplete=\(SubscriptionState.shared.isComplete)")
        
        // Notify the system to transition to subscription
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
        
        print("📊 JOURNEY: ═══════════════════════════════════════════════════")
    }
    
    // MARK: - Cleanup
    
    deinit {
        autoAdvanceTimer?.invalidate()
    }
}
