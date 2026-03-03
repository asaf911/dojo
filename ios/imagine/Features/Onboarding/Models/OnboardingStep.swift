//
//  OnboardingStep.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Defines the 10 screens in the Onboarding flow.
//  Each step has metadata for analytics, navigation rules, and display properties.
//

import Foundation

// MARK: - Onboarding Step

/// The 10 screens in the onboarding phase
enum OnboardingStep: Int, CaseIterable, Codable {
    case welcome = 0               // "Welcome To Dojo"
    case sensei = 1                // "The Sensei Is Listening"
    case goals = 2                 // "What Do You Seek?"
    case goalsAcknowledgment = 3   // Goal-specific acknowledgment
    case hurdle = 4                // "What Is Your Biggest Hurdle?"
    case hurdleAcknowledgment = 5  // Hurdle-specific acknowledgment
    case healthMindfulMinutes = 6  // Mindful Minutes - Apple Health write permission
    case healthHeartRate = 7       // Heart Rate - Apple Health read permission
    case building = 8              // "Your Personalized Path Is Taking Shape"
    case ready = 9                 // "Your Path Is Ready"
    
    // MARK: - Analytics
    
    /// Stable analytics identifier (never change these)
    var analyticsName: String {
        switch self {
        case .welcome: return "welcome"
        case .sensei: return "sensei_listening"
        case .goals: return "goals_selection"
        case .goalsAcknowledgment: return "goals_acknowledgment"
        case .hurdle: return "hurdle_selection"
        case .hurdleAcknowledgment: return "hurdle_acknowledgment"
        case .healthMindfulMinutes: return "health_mindful_minutes"
        case .healthHeartRate: return "health_heart_rate"
        case .building: return "path_building"
        case .ready: return "path_ready"
        }
    }
    
    /// Human-readable step number (1-indexed)
    var stepNumber: Int {
        rawValue + 1
    }
    
    // MARK: - Display Properties
    
    /// Title displayed on the screen
    /// NOTE: These must match what was previously displayed inline on each screen
    var title: String {
        switch self {
        case .welcome: return "Welcome to Dojo"
        case .sensei: return "The sensei\u{00A0}is listening"  // Non-breaking space to prevent awkward line break
        case .goals: return "What matters most right now?"     // Updated to match inline title
        case .goalsAcknowledgment: return "Great choice"       // Fallback (actual title is dynamic based on goal)
        case .hurdle: return "What is your biggest hurdle?"    // Fallback (actual title is dynamic)
        case .hurdleAcknowledgment: return "We'll work on this" // Fallback (actual title is dynamic based on hurdle)
        case .healthMindfulMinutes: return "Awareness over assumptions"
        case .healthHeartRate: return "We don't guess, we measure"
        case .building: return "This is built around you"  
        case .ready: return "Your path is ready"
        }
    }
    
    /// Subtitle or description
    var subtitle: String? {
        switch self {
        case .welcome:
            return "Guided, personal meditation\nA practice built for you"
        case .sensei:
            return nil  // Text shown below Sensei in SenseiScreen
        case .goals:
            return nil  // Text shown below Sensei in GoalsScreen
        case .goalsAcknowledgment:
            return nil  // Dynamic content shown in GoalsAcknowledgmentScreen body
        case .hurdle:
            return nil  // Dynamic content shown in HurdleScreen body
        case .hurdleAcknowledgment:
            return nil  // Dynamic content shown in HurdleAcknowledgmentScreen body
        case .healthMindfulMinutes:
            return nil
        case .healthHeartRate:
            return nil
        case .building:
            return nil
        case .ready:
            return nil  // Text shown below Sensei in ReadyScreen
        }
    }
    
    /// Primary CTA button text
    var ctaText: String {
        switch self {
        case .welcome: return "Get started"
        case .sensei: return "Set intention"
        case .goals: return "Set intention"
        case .goalsAcknowledgment: return "Continue"  // Fallback (actual CTA is dynamic based on goal)
        case .hurdle: return "Work through it"
        case .hurdleAcknowledgment: return "Continue"  // Fallback (actual CTA is dynamic based on hurdle)
        case .healthMindfulMinutes: return "Connect Apple Health"
        case .healthHeartRate: return "Enable Heart Rate"
        case .building: return "" // No CTA, auto-advances
        case .ready: return "Begin your practice"
        }
    }
    
    // MARK: - Navigation Properties
    
    /// Whether this step collects user input
    var collectsInput: Bool {
        switch self {
        case .goals, .hurdle: return true
        case .welcome, .sensei, .goalsAcknowledgment, .hurdleAcknowledgment, .healthMindfulMinutes, .healthHeartRate, .building, .ready: return false
        }
    }
    
    /// Whether user can navigate back from this step
    var canGoBack: Bool {
        switch self {
        case .welcome, .building, .ready: return false
        case .sensei, .goals, .goalsAcknowledgment, .hurdle, .hurdleAcknowledgment, .healthMindfulMinutes, .healthHeartRate: return true
        }
    }
    
    /// Minimum time to display this screen (for animated/loading screens)
    var minimumDisplaySeconds: TimeInterval? {
        switch self {
        case .building: return 3.5
        case .welcome, .sensei, .goals, .goalsAcknowledgment, .hurdle, .hurdleAcknowledgment, .healthMindfulMinutes, .healthHeartRate, .ready: return nil
        }
    }
    
    /// Whether progress bar should be visible on this screen
    var showsProgressBar: Bool {
        switch self {
        case .welcome: return false
        case .sensei, .goals, .goalsAcknowledgment, .hurdle, .hurdleAcknowledgment, .healthMindfulMinutes, .healthHeartRate, .building, .ready: return true
        }
    }
    
    /// Whether title/subtitle should be shown in the unified header
    /// All screens show title in header EXCEPT Welcome (which has centered content layout)
    var showsTitleInHeader: Bool {
        switch self {
        case .welcome: return false
        case .sensei, .goals, .goalsAcknowledgment, .hurdle, .hurdleAcknowledgment, .healthMindfulMinutes, .healthHeartRate, .building, .ready: return true
        }
    }
    
    /// Whether this screen auto-advances after minimum display time
    var autoAdvances: Bool {
        switch self {
        case .building: return true
        case .welcome, .sensei, .goals, .goalsAcknowledgment, .hurdle, .hurdleAcknowledgment, .healthMindfulMinutes, .healthHeartRate, .ready: return false
        }
    }
}
