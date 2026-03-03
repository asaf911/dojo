//
//  SubscriptionViewModel.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  View model for the subscription flow.
//  Handles navigation between screens and purchase actions.
//

import Foundation
import SwiftUI
import RevenueCat

// MARK: - Subscription View Model

@MainActor
class SubscriptionViewModel: ObservableObject {
    
    // MARK: - Published State
    
    /// Current step in the subscription flow
    @Published private(set) var currentStep: SubscriptionStep = .freeTrial
    
    /// Whether a purchase is being processed
    @Published private(set) var isProcessingPurchase: Bool = false
    
    /// Selected package for purchase
    @Published var selectedPackage: Package?
    
    /// Error message to display
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    /// Subscription manager for purchases
    let subscriptionManager: SubscriptionManager
    
    /// Persistent state manager
    private let state = SubscriptionState.shared
    
    /// Analytics handler
    private let analytics = SubscriptionAnalytics.shared
    
    // MARK: - Computed Properties
    
    /// Available packages from RevenueCat
    var availablePackages: [Package] {
        subscriptionManager.offerings?.current?.availablePackages ?? []
    }
    
    /// Default trial package (usually annual)
    var defaultTrialPackage: Package? {
        // Prefer annual package for free trial
        availablePackages.first { $0.packageType == .annual }
            ?? availablePackages.first
    }
    
    /// Annual package
    var annualPackage: Package? {
        availablePackages.first { $0.packageType == .annual }
    }
    
    /// Monthly package
    var monthlyPackage: Package? {
        availablePackages.first { $0.packageType == .monthly }
    }
    
    /// Lifetime package
    var lifetimePackage: Package? {
        availablePackages.first { $0.packageType == .lifetime }
    }
    
    // MARK: - Initialization
    
    init(subscriptionManager: SubscriptionManager = .shared) {
        self.subscriptionManager = subscriptionManager
        
        print("💳 SUBSCRIPTION_VM: ═══════════════════════════════════════")
        print("💳 SUBSCRIPTION_VM: Initializing SubscriptionViewModel")
        print("💳 SUBSCRIPTION_VM: ═══════════════════════════════════════")
    }
    
    // MARK: - Flow Start
    
    /// Called when the subscription view appears for the first time
    func onFlowStart() {
        print("💳 SUBSCRIPTION_VM: [FLOW_START] onFlowStart() called")
        print("💳 SUBSCRIPTION_VM: [FLOW_START] Available packages: \(availablePackages.count)")
        print("💳 SUBSCRIPTION_VM: [FLOW_START] User already subscribed: \(subscriptionManager.isUserSubscribed)")
        
        // Log subscription phase started (for funnel analysis)
        analytics.logSubscriptionPhaseStarted()
        
        // If user is already subscribed (e.g., restored purchases, returning user),
        // auto-complete the subscription phase and exit immediately
        if subscriptionManager.isUserSubscribed {
            print("💳 SUBSCRIPTION_VM: [FLOW_START] User already subscribed - auto-completing phase")
            autoCompleteForSubscribedUser()
            return
        }
        
        analytics.logStepViewed(step: .freeTrial)
        
        // Pre-select the default trial package
        selectedPackage = defaultTrialPackage
        print("💳 SUBSCRIPTION_VM: [FLOW_START] Default package: \(defaultTrialPackage?.identifier ?? "none")")
    }
    
    /// Auto-complete the subscription phase for users who are already subscribed.
    /// This ensures proper funnel analytics while skipping the UI for existing subscribers.
    private func autoCompleteForSubscribedUser() {
        print("💳 SUBSCRIPTION_VM: ═══════════════════════════════════════")
        print("💳 SUBSCRIPTION_VM: [AUTO_COMPLETE] User already subscribed")
        print("💳 SUBSCRIPTION_VM: [AUTO_COMPLETE] Completing subscription phase automatically")
        
        state.markCompleted(didSubscribe: true)
        
        // Refresh phase first so we log the correct next phase (path for Track A, dailyRoutines for Track B)
        ProductJourneyManager.shared.refreshPhase()
        
        // Log subscription-specific analytics (auto-completed)
        analytics.logSubscriptionPhaseCompleted(
            didSubscribe: true,
            exitStep: .freeTrial  // User never saw the UI, log as freeTrial
        )
        
        // Log journey phase transition using actual next phase from ProductJourneyManager
        JourneyAnalytics.logPhaseCompleted(phase: .subscription, nextPhase: ProductJourneyManager.shared.currentPhase)
        
        // Request push notification permission for returning subscribers
        // Uses OneSignal.Notifications.requestPermission() which tracks on OneSignal dashboard
        PushNotificationManager.shared.requestNotificationPermission(source: "subscription_auto_complete")
        
        print("💳 SUBSCRIPTION_VM: [AUTO_COMPLETE] Posting notification -> entering main app (Path phase)")
        
        // Signal to enter main app (Path phase)
        NotificationCenter.default.post(
            name: .subscriptionCompleted,
            object: nil,
            userInfo: ["subscribed": true, "autoCompleted": true]
        )
        
        print("💳 SUBSCRIPTION_VM: ═══════════════════════════════════════")
    }
    
    // MARK: - Navigation
    
    /// User taps "View all plans" on free trial screen
    func showAllPlans() {
        print("💳 SUBSCRIPTION_VM: [NAV] showAllPlans() - going to choosePlan")
        analytics.logViewAllPlansTapped()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = .choosePlan
        }
        
        analytics.logStepViewed(step: .choosePlan)
    }
    
    /// User taps back from choose plan screen
    func goBackToFreeTrial() {
        print("💳 SUBSCRIPTION_VM: [NAV] goBackToFreeTrial() - going back to freeTrial")
        analytics.logBackTapped(step: .choosePlan)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = .freeTrial
        }
    }
    
    // MARK: - Subscription Actions
    
    /// User taps "Start Your 7-Day Trial"
    func startFreeTrial() {
        guard let package = defaultTrialPackage else {
            errorMessage = "No trial package available"
            return
        }
        
        purchasePackage(package)
    }
    
    /// User selects and purchases a specific package
    func purchasePackage(_ package: Package) {
        guard !isProcessingPurchase else { return }
        
        isProcessingPurchase = true
        errorMessage = nil
        
        analytics.logSubscriptionAttempted(
            step: currentStep,
            packageId: package.identifier
        )
        
        subscriptionManager.purchase(package: package) { [weak self] success in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.isProcessingPurchase = false
                
                if success {
                    self.analytics.logSubscriptionSucceeded(
                        step: self.currentStep,
                        packageId: package.identifier
                    )
                    self.exitSubscriptionPhase(subscribed: true)
                } else {
                    self.analytics.logSubscriptionFailed(
                        step: self.currentStep,
                        packageId: package.identifier
                    )
                    // User stays on current screen - no error message needed
                    // as RevenueCat shows its own UI for errors/cancellation
                }
            }
        }
    }
    
    /// User dismisses/closes without subscribing
    func skipSubscription() {
        print("💳 SUBSCRIPTION_VM: [SKIP] User skipping subscription at step=\(currentStep.analyticsName)")
        analytics.logSubscriptionSkipped(step: currentStep)
        exitSubscriptionPhase(subscribed: false)
    }
    
    /// Restore purchases by refreshing subscription status
    func restorePurchases() {
        guard !isProcessingPurchase else { return }
        
        isProcessingPurchase = true
        errorMessage = nil
        
        analytics.logRestoreTapped(step: currentStep)
        
        // Refresh subscription status from RevenueCat
        subscriptionManager.refreshSubscriptionStatus()
        
        // Check status after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            
            self.isProcessingPurchase = false
            
            if self.subscriptionManager.isUserSubscribed {
                self.analytics.logRestoreSucceeded(step: self.currentStep)
                self.exitSubscriptionPhase(subscribed: true)
            } else {
                // Restore didn't find an active subscription
                self.errorMessage = "No active subscription found"
            }
        }
    }
    
    // MARK: - Phase Exit
    
    private func exitSubscriptionPhase(subscribed: Bool) {
        print("📊 JOURNEY: ═══════════════════════════════════════════════════")
        print("📊 JOURNEY: [SUBSCRIPTION_EXIT] Completing subscription phase")
        print("📊 JOURNEY: [SUBSCRIPTION_EXIT] subscribed=\(subscribed), exitStep=\(currentStep.analyticsName)")
        
        state.markCompleted(didSubscribe: subscribed)
        
        // Refresh phase first so we log the correct next phase (path for Track A, dailyRoutines for Track B)
        ProductJourneyManager.shared.refreshPhase()
        print("📊 JOURNEY: [SUBSCRIPTION_EXIT] Current phase after refresh: \(ProductJourneyManager.shared.currentPhase.displayName)")
        
        // Log subscription-specific analytics
        analytics.logSubscriptionPhaseCompleted(
            didSubscribe: subscribed,
            exitStep: currentStep
        )
        
        // Log journey phase transition using actual next phase from ProductJourneyManager
        JourneyAnalytics.logPhaseCompleted(phase: .subscription, nextPhase: ProductJourneyManager.shared.currentPhase)
        
        // Request push notification permission
        // Contextually relevant: Free Trial screen mentions "We'll remind you 2 days before trial ends"
        // Uses OneSignal.Notifications.requestPermission() which tracks on OneSignal dashboard
        PushNotificationManager.shared.requestNotificationPermission(source: "subscription_complete")
        
        print("📊 JOURNEY: [SUBSCRIPTION_EXIT] Posting notification -> entering main app (Path phase)")
        
        // Signal to enter main app (Path phase)
        NotificationCenter.default.post(
            name: .subscriptionCompleted,
            object: nil,
            userInfo: ["subscribed": subscribed]
        )
        
        print("📊 JOURNEY: ═══════════════════════════════════════════════════")
    }
}
