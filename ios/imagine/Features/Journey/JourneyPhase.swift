//
//  JourneyPhase.swift
//  imagine
//
//  Created by Cursor on 1/14/26.
//
//  Defines the phases of the user's product journey.
//  Each phase represents a distinct stage in the user's progression
//  through the app's meditation learning experience.
//

// =============================================================================
// HOW TO ADD A NEW JOURNEY PHASE
// =============================================================================
//
// 1. Add the new case to the JourneyPhase enum below
//    Example: case hybrid
//
// 2. Add it to the `activePhases` array in the correct position
//    The order in this array determines the phase sequence
//    Example: [.onboarding, .path, .hybrid, .dailyRoutines, .customization]
//
// 3. Add displayName and description in the respective computed properties
//
// 4. In ProductJourneyManager.swift:
//    - Add transition logic in determineCurrentPhase()
//    - Add any phase-specific state management
//
// 5. Analytics are handled automatically - no changes needed to:
//    - JourneyAnalytics.swift (fires journey_phase_entered and journey_phase_completed)
//    - AppsFlyerManager.swift (fires af_level_achieved on completion)
//    - OneSignalTagManager.swift (updates journey_phase and journey_phase_order tags)
//
// IMPORTANT: Phase names (rawValue) are stable identifiers used in analytics.
// Never rename existing cases - add new ones instead.
// =============================================================================

import Foundation

// MARK: - Journey Phase

/// Represents the distinct phases of a user's product journey.
/// Phases are sequential - users progress from one phase to the next
/// as they complete the requirements of each phase.
enum JourneyPhase: String, CaseIterable, Codable {
    
    /// Phase: Onboarding - Pre-app onboarding flow
    /// User goes through screens to personalize their experience.
    case onboarding
    
    /// Phase: Subscription - Pre-app subscription flow
    /// User is presented with subscription options before entering the app.
    case subscription
    
    /// Phase: The Path - structured learning journey
    /// User progresses through a series of guided meditation lessons.
    /// This is the primary learning phase for new users.
    case path
    
    /// Phase: Daily Routines - time-based pre-recorded sessions
    /// User has completed the Path and receives recommendations
    /// for morning, noon, evening, and night routines.
    case dailyRoutines
    
    /// Phase: Full customization
    /// User has unlocked full AI-powered meditation customization
    /// after completing 3 routine sessions in the Daily Routines phase.
    case customization
    
    // MARK: - Active Phases Configuration
    
    /// The phases that are currently active/implemented in the app.
    /// Order matters - this defines the progression sequence.
    /// To add a new phase, insert it in the correct position in this array.
    /// Note: Pre-app phases (onboarding, subscription) are handled separately
    /// by their own state managers and are not included in activePhases.
    static var activePhases: [JourneyPhase] {
        return [.path, .dailyRoutines, .customization]
    }
    
    /// All phases in order including pre-app phases (for analytics)
    static var allPhasesInOrder: [JourneyPhase] {
        return [.onboarding, .subscription, .path, .dailyRoutines, .customization]
    }
    
    /// Pre-app phases that must be completed before entering the main app
    static var preAppPhases: [JourneyPhase] {
        return [.onboarding, .subscription]
    }
    
    /// The first phase in the active journey (entry point for new users)
    static var firstPhase: JourneyPhase {
        return activePhases.first ?? .path
    }
    
    /// The last phase in the active journey (fully unlocked state)
    static var lastPhase: JourneyPhase {
        return activePhases.last ?? .customization
    }
    
    // MARK: - Properties
    
    /// The sequential order of this phase within activePhases (0-indexed).
    /// Returns -1 if the phase is not currently active.
    var order: Int {
        return Self.activePhases.firstIndex(of: self) ?? -1
    }
    
    /// The sequential order across ALL phases including pre-app (for analytics).
    /// Use this for analytics to get correct order for onboarding (0) and subscription (1).
    var fullOrder: Int {
        return Self.allPhasesInOrder.firstIndex(of: self) ?? -1
    }
    
    /// Whether this phase is currently active/implemented in the app.
    var isActive: Bool {
        return Self.activePhases.contains(self)
    }
    
    /// Human-readable name for UI display
    /// Note: rawValues (path, dailyRoutines) are stable analytics identifiers and never change.
    var displayName: String {
        switch self {
        case .onboarding: return "Onboarding"
        case .subscription: return "Subscription"
        case .path: return "Learning Phase"
        case .dailyRoutines: return "Personalized Phase"
        case .customization: return "Custom Practices"
        }
    }
    
    /// Whether this is a pre-app phase (must be completed before entering main app)
    var isPreAppPhase: Bool {
        switch self {
        case .onboarding, .subscription: return true
        default: return false
        }
    }
    
    /// Whether this is an in-app phase (main app experience)
    var isInAppPhase: Bool {
        !isPreAppPhase
    }
    
    /// Name used in analytics events (stable identifier - never change these)
    var analyticsName: String {
        return rawValue
    }
    
    /// Description of what this phase entails
    var description: String {
        switch self {
        case .onboarding:
            return "Personalize your meditation experience"
        case .subscription:
            return "Choose your subscription plan"
        case .path:
            return "Structured course for those starting from scratch"
        case .dailyRoutines:
            return "Hurdle-targeted meditations, pre-recorded and AI custom"
        case .customization:
            return "Create fully personalized meditations with AI"
        }
    }
    
    // MARK: - Phase Comparison
    
    /// Check if this phase comes before another phase in the active sequence
    func isBefore(_ other: JourneyPhase) -> Bool {
        guard self.isActive && other.isActive else { return false }
        return order < other.order
    }
    
    /// Check if this phase comes after another phase in the active sequence
    func isAfter(_ other: JourneyPhase) -> Bool {
        guard self.isActive && other.isActive else { return false }
        return order > other.order
    }
    
    /// Get the next phase in the active sequence (nil if at last phase or inactive)
    var nextPhase: JourneyPhase? {
        guard isActive else { return nil }
        let currentIndex = order
        guard currentIndex >= 0, currentIndex + 1 < Self.activePhases.count else {
            return nil
        }
        return Self.activePhases[currentIndex + 1]
    }
    
    /// Get the previous phase in the active sequence (nil if at first phase or inactive)
    var previousPhase: JourneyPhase? {
        guard isActive else { return nil }
        let currentIndex = order
        guard currentIndex > 0 else {
            return nil
        }
        return Self.activePhases[currentIndex - 1]
    }
    
    /// Whether this is the last phase in the journey (fully unlocked)
    var isLastPhase: Bool {
        return self == Self.lastPhase
    }
    
    /// Whether this is the first phase in the journey (entry point)
    var isFirstPhase: Bool {
        return self == Self.firstPhase
    }
}

// MARK: - Journey Skip Destination (Dev Mode)

/// Granular skip destinations for dev mode testing.
/// Reflects the two-track journey: Learning Phase (dont_know_start) and Personalized Phase (all others).
/// Each destination declares a hurdleOverride in its stateSnapshot to route correctly.
enum JourneySkipDestination: String, CaseIterable {
    // Pre-app phases
    case onboardingStart             = "onboarding_start"
    case subscriptionStart           = "subscription_start"
    // Learning track (hurdle: dont_know_start)
    case learningPhaseStart          = "learning_phase_start"
    case learningPhaseLastStep       = "learning_phase_last_step"
    // Personalized track (hurdle: mind_wont_slow_down)
    case personalizedPhaseStart      = "personalized_phase_start"
    case personalizedPhaseNearUnlock = "personalized_phase_near_unlock"
    case customPractices             = "custom_practices"
    // Timely recommendation test destinations (dev mode)
    case timelyMorning               = "timely_morning"
    case timelyNoon                  = "timely_noon"
    case timelyEvening               = "timely_evening"
    case timelyNight                 = "timely_night"
    
    /// Display name for UI picker
    var displayName: String {
        switch self {
        case .onboardingStart:             return "Onboarding: Start"
        case .subscriptionStart:           return "Subscription: Start"
        case .learningPhaseStart:          return "Learning Phase: Start"
        case .learningPhaseLastStep:       return "Learning Phase: Last Step"
        case .personalizedPhaseStart:      return "Personalized Phase: Start"
        case .personalizedPhaseNearUnlock: return "Personalized Phase: Near Unlock"
        case .customPractices:             return "Custom Practices"
        case .timelyMorning:               return "Timely Recommendation: Morning"
        case .timelyNoon:                  return "Timely Recommendation: Noon"
        case .timelyEvening:               return "Timely Recommendation: Evening"
        case .timelyNight:                 return "Timely Recommendation: Night"
        }
    }
    
    /// Description of what state this destination sets up
    var stateDescription: String {
        switch self {
        case .onboardingStart:
            return "Reset all, show onboarding"
        case .subscriptionStart:
            return "Onboarding done, show subscription"
        case .learningPhaseStart:
            return "Track A (dont_know_start) — step 1 of Learning Phase"
        case .learningPhaseLastStep:
            return "Track A (dont_know_start) — last step before Personalized Phase"
        case .personalizedPhaseStart:
            return "Track B (mind_wont_slow_down) — 0/3 sessions, Explore + Path secondary"
        case .personalizedPhaseNearUnlock:
            return "Track B (mind_wont_slow_down) — 2/3 sessions, Custom tease active"
        case .customPractices:
            return "Track B (mind_wont_slow_down) — 3/3 sessions, full AI customization"
        case .timelyMorning:
            return "Force morning timely recommendation in AI chat (slot override)"
        case .timelyNoon:
            return "Force noon timely recommendation in AI chat (slot override)"
        case .timelyEvening:
            return "Force evening timely recommendation in AI chat (slot override)"
        case .timelyNight:
            return "Force night timely recommendation in AI chat (slot override)"
        }
    }
    
    /// The phase this destination lands in
    var targetPhase: JourneyPhase {
        switch self {
        case .onboardingStart:
            return .onboarding
        case .subscriptionStart:
            return .subscription
        case .learningPhaseStart, .learningPhaseLastStep:
            return .path
        case .personalizedPhaseStart, .personalizedPhaseNearUnlock,
             .timelyMorning, .timelyNoon, .timelyEvening, .timelyNight:
            return .dailyRoutines
        case .customPractices:
            return .customization
        }
    }

    /// Optional dev-mode override for timely recommendation slot selection.
    /// Value matches ExploreRecommendationManager.TimeOfDay raw values.
    var timelySlotOverride: String? {
        switch self {
        case .timelyMorning:
            return "morning"
        case .timelyNoon:
            return "noon"
        case .timelyEvening:
            return "evening"
        case .timelyNight:
            return "night"
        default:
            return nil
        }
    }
}

// MARK: - Dev Mode State Types

/// Represents the state of path progress for dev mode skipping.
enum PathProgress {
    /// No steps completed - reset to beginning
    case reset
    /// All steps except the last one completed
    case lastStep
    /// All steps completed
    case complete
}

/// A snapshot of the journey state for a specific skip destination.
/// Declaratively defines what state should look like after a skip.
struct JourneyStateSnapshot {
    let onboardingComplete: Bool
    let subscriptionComplete: Bool
    let pathProgress: PathProgress
    let routineCount: Int
    let targetPhase: JourneyPhase
    /// When non-nil, DevModeSkipService.applySnapshot sets this as the user's hurdle
    /// so determineCurrentPhase() routes to the correct track (Learning vs Personalized).
    /// nil means "don't touch the hurdle" — used when onboarding will set it naturally.
    let hurdleOverride: String?
}

/// Verification result for a dev mode skip operation.
struct DevModeStateVerification {
    let phaseMatches: Bool
    let onboardingMatches: Bool
    let subscriptionMatches: Bool
    let pathMatches: Bool
    let routineCountMatches: Bool
    
    var allPassed: Bool {
        phaseMatches && onboardingMatches && subscriptionMatches &&
        pathMatches && routineCountMatches
    }
    
    var summary: String {
        if allPassed { return "All checks passed" }
        var failures: [String] = []
        if !phaseMatches { failures.append("phase") }
        if !onboardingMatches { failures.append("onboarding") }
        if !subscriptionMatches { failures.append("subscription") }
        if !pathMatches { failures.append("path") }
        if !routineCountMatches { failures.append("routines") }
        return "Mismatch: \(failures.joined(separator: ", "))"
    }
}

/// Result of a dev mode skip operation.
enum DevModeSkipResult {
    case success(destination: JourneySkipDestination, verification: DevModeStateVerification)
    case failure(String)
    
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - State Snapshots

extension JourneySkipDestination {
    
    /// The complete state snapshot this destination requires.
    /// Declarative definition of what state should look like after skip.
    /// hurdleOverride is applied by DevModeSkipService to route determineCurrentPhase() correctly.
    var stateSnapshot: JourneyStateSnapshot {
        switch self {
        case .onboardingStart:
            // Full reset — user will pick their own hurdle through onboarding
            return JourneyStateSnapshot(
                onboardingComplete: false,
                subscriptionComplete: false,
                pathProgress: .reset,
                routineCount: 0,
                targetPhase: .onboarding,
                hurdleOverride: nil
            )
            
        case .subscriptionStart:
            // Onboarding done — hurdle should have been set during onboarding, preserve it
            return JourneyStateSnapshot(
                onboardingComplete: true,
                subscriptionComplete: false,
                pathProgress: .reset,
                routineCount: 0,
                targetPhase: .subscription,
                hurdleOverride: nil
            )
            
        case .learningPhaseStart:
            // Track A: dont_know_start → Learning Phase, step 1
            return JourneyStateSnapshot(
                onboardingComplete: true,
                subscriptionComplete: true,
                pathProgress: .reset,
                routineCount: 0,
                targetPhase: .path,
                hurdleOverride: "dont_know_start"
            )
            
        case .learningPhaseLastStep:
            // Track A: dont_know_start → Learning Phase, penultimate step
            return JourneyStateSnapshot(
                onboardingComplete: true,
                subscriptionComplete: true,
                pathProgress: .lastStep,
                routineCount: 0,
                targetPhase: .path,
                hurdleOverride: "dont_know_start"
            )
            
        case .personalizedPhaseStart:
            // Track B: specific hurdle → Personalized Phase, 0/3 sessions
            return JourneyStateSnapshot(
                onboardingComplete: true,
                subscriptionComplete: true,
                pathProgress: .complete,
                routineCount: 0,
                targetPhase: .dailyRoutines,
                hurdleOverride: "mind_wont_slow_down"
            )
            
        case .personalizedPhaseNearUnlock:
            // Track B: specific hurdle → Personalized Phase, 2/3 sessions (Custom tease active)
            return JourneyStateSnapshot(
                onboardingComplete: true,
                subscriptionComplete: true,
                pathProgress: .complete,
                routineCount: 2,
                targetPhase: .dailyRoutines,
                hurdleOverride: "mind_wont_slow_down"
            )
            
        case .customPractices:
            // Track B: fully unlocked — all 3 sessions completed
            return JourneyStateSnapshot(
                onboardingComplete: true,
                subscriptionComplete: true,
                pathProgress: .complete,
                routineCount: 3,
                targetPhase: .customization,
                hurdleOverride: "mind_wont_slow_down"
            )

        case .timelyMorning, .timelyNoon, .timelyEvening, .timelyNight:
            // Timely recommendation testing should always land in Personalized Phase.
            // Uses Track B defaults to avoid Path-mode dependencies and force a timely dual recommendation.
            return JourneyStateSnapshot(
                onboardingComplete: true,
                subscriptionComplete: true,
                pathProgress: .complete,
                routineCount: 0,
                targetPhase: .dailyRoutines,
                hurdleOverride: "mind_wont_slow_down"
            )
        }
    }
}
