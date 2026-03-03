//
//  SubscriptionAnalytics.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Comprehensive analytics for the subscription flow.
//  Events are designed for funnel analysis and conversion tracking.
//

import Foundation

// MARK: - Subscription Analytics

/// Analytics handler for the subscription flow
struct SubscriptionAnalytics {
    
    // MARK: - Singleton
    
    static let shared = SubscriptionAnalytics()
    
    private init() {}
    
    // MARK: - Event Names (Stable Identifiers)
    
    private enum Event {
        static let phaseStarted = "subscription_started"
        static let phaseCompleted = "subscription_completed"
        static let stepViewed = "subscription_step_viewed"
        static let viewPlansTapped = "subscription_view_plans_tapped"
        static let subscriptionAttempted = "subscription_attempted"
        static let subscriptionSucceeded = "subscription_succeeded"
        static let subscriptionFailed = "subscription_failed"
        static let subscriptionSkipped = "subscription_skipped"
        static let backTapped = "subscription_back_tapped"
        static let restoreTapped = "subscription_restore_tapped"
        static let restoreSucceeded = "subscription_restore_succeeded"
    }
    
    // MARK: - Flow Events
    
    /// Log when subscription phase starts
    func logSubscriptionPhaseStarted() {
        let params: [String: Any] = [
            "from_onboarding": true,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // AnalyticsManager routes to AppsFlyer internally - no direct call needed
        AnalyticsManager.shared.logEvent(Event.phaseStarted, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.phaseStarted)")
        #endif
    }
    
    /// Log when subscription phase completes
    func logSubscriptionPhaseCompleted(didSubscribe: Bool, exitStep: SubscriptionStep) {
        let params: [String: Any] = [
            "did_subscribe": didSubscribe,
            "exit_step": exitStep.analyticsName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // AnalyticsManager routes to AppsFlyer internally - no direct call needed
        AnalyticsManager.shared.logEvent(Event.phaseCompleted, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.phaseCompleted) subscribed=\(didSubscribe) exit=\(exitStep.analyticsName)")
        #endif
    }
    
    // MARK: - Step Events
    
    /// Log when a step is viewed
    func logStepViewed(step: SubscriptionStep) {
        let params: [String: Any] = [
            "step_name": step.analyticsName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        AnalyticsManager.shared.logEvent(Event.stepViewed, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.stepViewed) step=\(step.analyticsName)")
        #endif
    }
    
    /// Log when "View all plans" is tapped
    func logViewAllPlansTapped() {
        let params: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        AnalyticsManager.shared.logEvent(Event.viewPlansTapped, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.viewPlansTapped)")
        #endif
    }
    
    /// Log when back is tapped
    func logBackTapped(step: SubscriptionStep) {
        let params: [String: Any] = [
            "step_name": step.analyticsName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        AnalyticsManager.shared.logEvent(Event.backTapped, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.backTapped) step=\(step.analyticsName)")
        #endif
    }
    
    // MARK: - Subscription Events
    
    /// Log when subscription purchase is attempted
    func logSubscriptionAttempted(step: SubscriptionStep, packageId: String?) {
        var params: [String: Any] = [
            "step_name": step.analyticsName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let packageId = packageId {
            params["package_id"] = packageId
        }
        
        // AnalyticsManager routes to AppsFlyer internally - no direct call needed
        AnalyticsManager.shared.logEvent(Event.subscriptionAttempted, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.subscriptionAttempted) step=\(step.analyticsName) package=\(packageId ?? "nil")")
        #endif
    }
    
    /// Log when subscription purchase succeeds
    func logSubscriptionSucceeded(step: SubscriptionStep, packageId: String?) {
        var params: [String: Any] = [
            "step_name": step.analyticsName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let packageId = packageId {
            params["package_id"] = packageId
        }
        
        // AnalyticsManager routes to AppsFlyer internally - no direct call needed
        AnalyticsManager.shared.logEvent(Event.subscriptionSucceeded, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.subscriptionSucceeded) step=\(step.analyticsName) package=\(packageId ?? "nil")")
        #endif
    }
    
    /// Log when subscription purchase fails
    func logSubscriptionFailed(step: SubscriptionStep, packageId: String? = nil) {
        var params: [String: Any] = [
            "step_name": step.analyticsName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let packageId = packageId {
            params["package_id"] = packageId
        }
        
        AnalyticsManager.shared.logEvent(Event.subscriptionFailed, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.subscriptionFailed) step=\(step.analyticsName)")
        #endif
    }
    
    /// Log when user skips subscription
    func logSubscriptionSkipped(step: SubscriptionStep) {
        let params: [String: Any] = [
            "step_name": step.analyticsName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        AnalyticsManager.shared.logEvent(Event.subscriptionSkipped, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.subscriptionSkipped) step=\(step.analyticsName)")
        #endif
    }
    
    // MARK: - Restore Events
    
    /// Log when restore is tapped
    func logRestoreTapped(step: SubscriptionStep) {
        let params: [String: Any] = [
            "step_name": step.analyticsName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        AnalyticsManager.shared.logEvent(Event.restoreTapped, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.restoreTapped) step=\(step.analyticsName)")
        #endif
    }
    
    /// Log when restore succeeds
    func logRestoreSucceeded(step: SubscriptionStep) {
        let params: [String: Any] = [
            "step_name": step.analyticsName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        AnalyticsManager.shared.logEvent(Event.restoreSucceeded, parameters: params)
        
        #if DEBUG
        print("📊 SUBSCRIPTION_ANALYTICS: \(Event.restoreSucceeded) step=\(step.analyticsName)")
        #endif
    }
}
