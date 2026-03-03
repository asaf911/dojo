//
//  OnboardingAnalytics.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Comprehensive analytics for the onboarding flow.
//  Events use legacy event names for backward compatibility with existing dashboards.
//  All events include onboarding_version: "2026" to identify this flow version.
//

import Foundation

// MARK: - Onboarding Analytics

/// Analytics handler for the onboarding flow
struct OnboardingAnalytics {
    
    // MARK: - Singleton
    
    static let shared = OnboardingAnalytics()
    
    private init() {}
    
    // MARK: - Event Names (Legacy names for backward compatibility)
    
    private enum Event {
        static let flowStarted = "onboarding_started"
        static let flowCompleted = "onboarding_completed"
        static let stepViewed = "onboarding_screen_viewed"
        static let stepCompleted = "onboarding_step_completed"
        static let optionSelected = "onboarding_option_selected"
        static let skipTapped = "onboarding_skipped"
    }
    
    // MARK: - Version Property
    
    /// Version identifier added to all events for dashboard filtering
    private let onboardingVersion = "2026"
    
    /// Creates base parameters with version info
    private func baseParams() -> [String: Any] {
        return [
            "onboarding_version": onboardingVersion,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
    }
    
    // MARK: - Flow Events
    
    /// Log when onboarding flow starts
    func logOnboardingStarted(variantId: String, totalSteps: Int) {
        var params = baseParams()
        params["variant_id"] = variantId
        params["total_steps"] = totalSteps
        
        // AnalyticsManager routes to AppsFlyer internally - no direct call needed
        AnalyticsManager.shared.logEvent(Event.flowStarted, parameters: params)
        
        #if DEBUG
        print("📊 ONBOARDING_ANALYTICS: \(Event.flowStarted) variant=\(variantId)")
        #endif
    }
    
    /// Log when onboarding flow completes
    func logOnboardingCompleted(
        responses: OnboardingResponses,
        variantId: String,
        totalSteps: Int,
        duration: TimeInterval?
    ) {
        var params = baseParams()
        params["variant_id"] = variantId
        params["total_steps"] = totalSteps
        params["goal_selected"] = responses.goalAnalyticsString
        params["hurdle_selected"] = responses.hurdleAnalyticsString
        params["connected_healthkit"] = responses.connectedHealthKit  // Legacy - backward compatible
        params["connected_mindful_minutes"] = responses.connectedMindfulMinutes
        params["enabled_heart_rate"] = responses.enabledHeartRate
        
        if let duration = duration {
            params["duration_seconds"] = Int(duration)
        }
        
        // AnalyticsManager routes to AppsFlyer internally - no direct call needed
        AnalyticsManager.shared.logEvent(Event.flowCompleted, parameters: params)
        
        #if DEBUG
        print("📊 ONBOARDING_ANALYTICS: \(Event.flowCompleted) goal=\(responses.goalAnalyticsString) hurdle=\(responses.hurdleAnalyticsString) mindful_minutes=\(responses.connectedMindfulMinutes) heart_rate=\(responses.enabledHeartRate)")
        #endif
    }
    
    // MARK: - Step Events
    
    /// Log when a step is viewed
    func logStepViewed(step: OnboardingStep, stepIndex: Int, totalSteps: Int) {
        var params = baseParams()
        params["screen_name"] = step.analyticsName
        params["step_index"] = stepIndex
        params["step_number"] = stepIndex + 1
        params["total_steps"] = totalSteps
        
        AnalyticsManager.shared.logEvent(Event.stepViewed, parameters: params)
        
        #if DEBUG
        print("📊 ONBOARDING_ANALYTICS: \(Event.stepViewed) screen=\(step.analyticsName) (\(stepIndex + 1)/\(totalSteps))")
        #endif
    }
    
    /// Log when a step is completed (user advances)
    func logStepCompleted(
        step: OnboardingStep,
        stepIndex: Int,
        totalSteps: Int,
        responses: OnboardingResponses
    ) {
        var params = baseParams()
        params["screen_name"] = step.analyticsName
        params["step_index"] = stepIndex
        params["step_number"] = stepIndex + 1
        params["total_steps"] = totalSteps
        
        // Add step-specific data
        switch step {
        case .sensei:
            params["selection"] = responses.familiarityAnalyticsString
        case .goals:
            params["selection"] = responses.goalAnalyticsString
        case .goalsAcknowledgment:
            params["acknowledged_goal"] = responses.goalAnalyticsString
        case .hurdle:
            params["selection"] = responses.hurdleAnalyticsString
        case .hurdleAcknowledgment:
            params["acknowledged_hurdle"] = responses.hurdleAnalyticsString
        case .healthMindfulMinutes:
            params["connected_mindful_minutes"] = responses.connectedMindfulMinutes
        case .healthHeartRate:
            params["enabled_heart_rate"] = responses.enabledHeartRate
        case .welcome, .building, .ready:
            break
        }
        
        AnalyticsManager.shared.logEvent(Event.stepCompleted, parameters: params)
        
        #if DEBUG
        // Build debug string with step-specific selection
        var debugInfo = "screen=\(step.analyticsName)"
        switch step {
        case .sensei:
            debugInfo += " selection=\(responses.familiarityAnalyticsString)"
        case .goals:
            debugInfo += " selection=\(responses.goalAnalyticsString)"
        case .goalsAcknowledgment:
            debugInfo += " acknowledged_goal=\(responses.goalAnalyticsString)"
        case .hurdle:
            debugInfo += " selection=\(responses.hurdleAnalyticsString)"
        case .hurdleAcknowledgment:
            debugInfo += " acknowledged_hurdle=\(responses.hurdleAnalyticsString)"
        case .healthMindfulMinutes:
            debugInfo += " connected_mindful_minutes=\(responses.connectedMindfulMinutes)"
        case .healthHeartRate:
            debugInfo += " enabled_heart_rate=\(responses.enabledHeartRate)"
        case .welcome, .building, .ready:
            break
        }
        print("📊 ONBOARDING_ANALYTICS: \(Event.stepCompleted) \(debugInfo)")
        #endif
    }
    
    // MARK: - Interaction Events
    
    /// Log when an option is selected
    func logOptionSelected(step: OnboardingStep, optionId: String) {
        var params = baseParams()
        params["screen_name"] = step.analyticsName
        params["option"] = optionId
        params["selected"] = true
        
        AnalyticsManager.shared.logEvent(Event.optionSelected, parameters: params)
        
        #if DEBUG
        print("📊 ONBOARDING_ANALYTICS: \(Event.optionSelected) screen=\(step.analyticsName) option=\(optionId) selected=true")
        #endif
    }
    
    /// Log when skip button is tapped
    func logSkipTapped(step: OnboardingStep, stepIndex: Int) {
        var params = baseParams()
        params["screen_name"] = step.analyticsName
        params["step_index"] = stepIndex
        
        AnalyticsManager.shared.logEvent(Event.skipTapped, parameters: params)
        
        #if DEBUG
        print("📊 ONBOARDING_ANALYTICS: \(Event.skipTapped) screen=\(step.analyticsName)")
        #endif
    }
}
