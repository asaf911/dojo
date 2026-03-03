//
//  UserMode.swift
//  imagine
//
//  The two high-level states a user can be in for recommendation purposes.
//  This is the only branching logic at the top of the recommendation framework.
//

import Foundation

// MARK: - User Mode

/// The two recommendation modes. All branching in the dual recommendation
/// system starts here — nothing else causes the system to fork.
enum UserMode: String, Codable {

    /// User has not completed The Path.
    /// The Path drives the Primary recommendation; context drives the Secondary.
    case learn

    /// User has completed or skipped The Path.
    /// Context drives the Primary recommendation; contrast drives the Secondary.
    case personal

    // MARK: - Factory

    /// Derives the user mode from the current journey phase.
    /// Returns nil for pre-app phases where recommendations are not shown.
    static func from(phase: JourneyPhase) -> UserMode? {
        switch phase {
        case .path:
            return .learn
        case .dailyRoutines, .customization:
            return .personal
        case .onboarding, .subscription:
            return nil
        }
    }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .learn:    return "Learn"
        case .personal: return "Personal"
        }
    }
}
