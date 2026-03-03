//
//  OnboardingResponses.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  User input collected during onboarding.
//  Used for personalization and analytics.
//

import Foundation

// MARK: - Onboarding Responses

/// Collected user data from onboarding for personalization
struct OnboardingResponses: Codable, Equatable {
    
    /// Selected familiarity level from the Sensei screen
    var selectedFamiliarity: OnboardingFamiliarity?
    
    /// Selected goal from the Goals screen (single-select)
    var selectedGoal: OnboardingGoal?
    
    /// Selected hurdle from the Hurdle screen (single-select, goal-specific)
    var selectedHurdle: HurdleScreenContent.HurdleOption?
    
    // MARK: - Health Permissions (Separate)
    
    /// Whether user connected Mindful Minutes (write permission)
    var connectedMindfulMinutes: Bool = false
    
    /// Whether user enabled Heart Rate tracking (read permission)
    /// Note: This only means the user tapped "Enable" - iOS does not confirm actual authorization
    var enabledHeartRate: Bool = false
    
    /// Legacy property for backward compatibility with existing users
    /// Stored for Codable compatibility with previously saved data
    private var _legacyConnectedHealthKit: Bool = false
    
    /// Whether user has any HealthKit connection (backward compatible)
    /// Returns true if: legacy was set, OR mindful minutes connected, OR heart rate enabled
    var connectedHealthKit: Bool {
        get { _legacyConnectedHealthKit || connectedMindfulMinutes || enabledHeartRate }
        set { _legacyConnectedHealthKit = newValue }
    }
    
    /// Timestamp when responses were collected
    var timestamp: Date = Date()
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case selectedFamiliarity
        case selectedGoal
        case selectedHurdle
        case connectedMindfulMinutes
        case enabledHeartRate
        case _legacyConnectedHealthKit = "connectedHealthKit"
        case timestamp
    }
    
    // MARK: - Analytics Helpers
    
    /// Familiarity as string for analytics
    var familiarityAnalyticsString: String {
        selectedFamiliarity?.rawValue ?? "none"
    }
    
    /// Goal as string for analytics
    var goalAnalyticsString: String {
        selectedGoal?.rawValue ?? "none"
    }
    
    /// Hurdle as string for analytics
    var hurdleAnalyticsString: String {
        selectedHurdle?.id ?? "none"
    }
    
    /// Mindful Minutes as string for analytics
    var mindfulMinutesAnalyticsString: String {
        connectedMindfulMinutes ? "connected" : "not_connected"
    }
    
    /// Heart Rate as string for analytics
    var heartRateAnalyticsString: String {
        enabledHeartRate ? "enabled" : "not_enabled"
    }
}

// MARK: - Onboarding Familiarity

/// Familiarity levels users can select on the Sensei screen (single-select)
enum OnboardingFamiliarity: String, Codable, CaseIterable, Hashable {
    case brandNew = "brand_new"
    case occasional = "occasional"
    case regular = "regular"
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .brandNew: return "I’m new"
        case .occasional: return "I practice sometimes"
        case .regular: return "I practice consistently"
        }
    }
    
    /// Initialize from display name string
    init?(displayName: String) {
        switch displayName {
        case "I am brand new": self = .brandNew
        case "I practice occasionally": self = .occasional
        case "I practice regularly": self = .regular
        default: return nil
        }
    }
}

// MARK: - Onboarding Goal

/// Goals users can select (single-select)
enum OnboardingGoal: String, Codable, CaseIterable, Hashable {
    // Primary goals (shown initially)
    case relaxation = "relaxation"
    case spiritualGrowth = "spiritual_growth"
    case betterSleep = "better_sleep"
    
    // Secondary goals (shown after "More goals")
    case focus = "focus"
    case visualization = "visualization"
    case energy = "energy"
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .relaxation: return "Relaxation"
        case .spiritualGrowth: return "Spiritual growth"
        case .betterSleep: return "Better sleep"
        case .focus: return "Sharpen focus"
        case .visualization: return "Visualization"
        case .energy: return "Boost energy"
        }
    }
    
    /// Icon name (custom asset from Onboardingassets)
    var iconName: String {
        switch self {
        case .relaxation: return "goalRelaxation"
        case .spiritualGrowth: return "goalGrowth"
        case .betterSleep: return "goalSleep"
        case .focus: return "goalFocus"
        case .visualization: return "goalVisualization"
        case .energy: return "goalEnergy"
        }
    }
    
    /// Whether this is a primary goal (shown initially)
    var isPrimary: Bool {
        switch self {
        case .relaxation, .spiritualGrowth, .betterSleep: return true
        case .focus, .visualization, .energy: return false
        }
    }
    
    /// Primary goals shown initially
    static var primaryGoals: [OnboardingGoal] {
        allCases.filter { $0.isPrimary }
    }
    
    /// Secondary goals revealed by "More goals"
    static var secondaryGoals: [OnboardingGoal] {
        allCases.filter { !$0.isPrimary }
    }
}

