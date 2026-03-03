//
//  Authentication+Mode.swift
//  imagine
//
//  Created by Asaf Shamir on 2026-02-12
//
//  Mode affects UI copy and feature flags only; auth logic is unified.
//

import Foundation

/// Namespace for the unified authentication feature.
enum Authentication {}

// MARK: - Mode

extension Authentication {
    /// Whether the user is signing in to an existing account or creating a new one.
    enum Mode {
        case signIn
        case signUp
    }
}

// MARK: - Mode Configuration

extension Authentication.Mode {

    /// The label shown in debug logs to identify the active mode.
    var debugLabel: String {
        switch self {
        case .signIn: return "signIn"
        case .signUp: return "signUp"
        }
    }

    // MARK: Copy Strings

    /// Header subtitle displayed above the form on the enter-email step.
    var headerSubtitle: String {
        switch self {
        case .signIn: return "Sign in with"
        case .signUp: return "Create your account with"
        }
    }

    /// Divider text between social buttons and the email field.
    var dividerText: String {
        switch self {
        case .signIn: return "Or sign in with email"
        case .signUp: return "Or sign up with email"
        }
    }

    /// Placeholder / title for the email input field.
    var emailFieldTitle: String {
        switch self {
        case .signIn: return "Email"
        case .signUp: return "Enter your email"
        }
    }

    /// Prompt text shown before the mode-switch button (e.g. "New User? ").
    var switchPromptText: String {
        switch self {
        case .signIn: return "New User? "
        case .signUp: return "Already have an account? "
        }
    }

    /// Title of the mode-switch button (e.g. "Sign Up" / "Sign In").
    var switchActionTitle: String {
        switch self {
        case .signIn: return "Sign Up"
        case .signUp: return "Sign In"
        }
    }

    // MARK: Feature Flags

    /// Only the sign-in screen offers "Continue without an account".
    var showsContinueAsGuest: Bool {
        self == .signIn
    }

    /// ATT (App Tracking Transparency) is requested only during sign-up.
    var requestsATT: Bool {
        self == .signUp
    }

    /// The identity-readiness gate is only needed during sign-up.
    var waitsForIdentityReady: Bool {
        self == .signUp
    }

    // MARK: Layout

    /// iPad-specific top padding differs between modes.
    var iPadTopPadding: CGFloat {
        switch self {
        case .signIn: return 184
        case .signUp: return 204
        }
    }

    // MARK: Navigation

    /// The opposite mode for the mode-switch button.
    var opposite: Authentication.Mode {
        switch self {
        case .signIn: return .signUp
        case .signUp: return .signIn
        }
    }
}
