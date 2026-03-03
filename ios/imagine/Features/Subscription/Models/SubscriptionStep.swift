//
//  SubscriptionStep.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Defines the screens in the Subscription 2026 flow.
//  The flow has 1-2 screens: Free Trial (required) and Choose Plan (conditional).
//

import Foundation

// MARK: - Subscription Step

/// The screens in the subscription phase
enum SubscriptionStep: Int, CaseIterable, Codable {
    case freeTrial = 0     // "7-Day Free Trial" - primary screen (required)
    case choosePlan = 1    // "Choose Your Plan" - optional, user-navigated
    
    // MARK: - Analytics
    
    /// Stable analytics identifier (never change these)
    var analyticsName: String {
        switch self {
        case .freeTrial: return "free_trial"
        case .choosePlan: return "choose_plan"
        }
    }
    
    // MARK: - Display Properties
    
    /// Title displayed on the screen
    var title: String {
        switch self {
        case .freeTrial: return "7-day free trial"
        case .choosePlan: return "Choose your plan"
        }
    }
    
    /// Subtitle or description
    var subtitle: String? {
        switch self {
        case .freeTrial:
            return "We'll remind you 2 days before your trial ends. Cancel anytime."
        case .choosePlan:
            return nil
        }
    }
    
    /// Primary CTA button text
    var ctaText: String {
        switch self {
        case .freeTrial: return "Start free 7-day trial"
        case .choosePlan: return "Continue"
        }
    }
    
    // MARK: - Screen Properties
    
    /// Whether this screen is always shown or conditionally navigated to
    var isRequired: Bool {
        switch self {
        case .freeTrial: return true
        case .choosePlan: return false  // Only shown if user taps "View all plans"
        }
    }
    
    /// Whether to show the close (X) button
    var showsCloseButton: Bool {
        true // Both screens can be dismissed
    }
    
    /// Whether to show "View all plans" link
    var showsViewAllPlansLink: Bool {
        switch self {
        case .freeTrial: return true
        case .choosePlan: return false
        }
    }
}
