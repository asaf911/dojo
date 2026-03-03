//
//  EmailAuthStep.swift
//  imagine
//
//  Created by Asaf Shamir on 2026-02-12
//

import Foundation

/// The two steps of the email code authentication flow.
enum EmailAuthStep {
    /// User enters their email address.
    case enterEmail
    /// User enters the 4-digit verification code sent to their email.
    case enterCode
}
