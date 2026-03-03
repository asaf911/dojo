//
//  EmailValidationService.swift
//  imagine
//
//  Created by Asaf Shamir on 2026-02-12
//

import Foundation
import FirebaseFunctions

// MARK: - Result Model

struct VerifyCodeResult {
    let customToken: String
    let isNewUser: Bool
}

// MARK: - Service (struct of closures)

struct EmailValidationService {
    /// Request a 4-digit verification code for the given email.
    var requestCode: (_ email: String) async throws -> Void

    /// Verify the 4-digit code and receive a Firebase Custom Token.
    var verifyCode: (_ email: String, _ code: String) async throws -> VerifyCodeResult
}

// MARK: - Live

extension EmailValidationService {
    static let live = EmailValidationService(
        requestCode: { email in
            print("EMAIL_AUTH: [SERVICE] Calling requestEmailCode for: \(email)")
            let callable = Functions.functions().httpsCallable("requestEmailCode")
            do {
                _ = try await callable.call(["email": email])
                print("EMAIL_AUTH: [SERVICE] requestEmailCode SUCCESS")
            } catch {
                let nsError = error as NSError
                print("EMAIL_AUTH: [SERVICE] requestEmailCode FAILED")
                print("EMAIL_AUTH: [SERVICE]   domain: \(nsError.domain)")
                print("EMAIL_AUTH: [SERVICE]   code: \(nsError.code)")
                print("EMAIL_AUTH: [SERVICE]   description: \(nsError.localizedDescription)")
                if let details = nsError.userInfo["details"] {
                    print("EMAIL_AUTH: [SERVICE]   details: \(details)")
                }
                throw error
            }
        },
        verifyCode: { email, code in
            let callable = Functions.functions().httpsCallable("verifyEmailCode")
            let result = try await callable.call(["email": email, "code": code])

            guard let data = result.data as? [String: Any] else {
                throw NSError(
                    domain: "EmailValidation", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid server response"]
                )
            }

            // The server may return success: false with remainingAttempts on bad code
            if let success = data["success"] as? Bool, !success {
                let remaining = data["remainingAttempts"] as? Int ?? 0
                let message = remaining > 0
                    ? "Invalid code. \(remaining) attempts remaining."
                    : "Too many incorrect attempts. Please request a new code."
                throw NSError(
                    domain: "EmailValidation", code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            guard let token = data["customToken"] as? String,
                  let isNew = data["isNewUser"] as? Bool else {
                throw NSError(
                    domain: "EmailValidation", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid server response"]
                )
            }

            return VerifyCodeResult(customToken: token, isNewUser: isNew)
        }
    )
}

// MARK: - Preview

extension EmailValidationService {
    static let preview = EmailValidationService(
        requestCode: { _ in
            try await Task.sleep(nanoseconds: 500_000_000)
        },
        verifyCode: { _, code in
            try await Task.sleep(nanoseconds: 500_000_000)
            guard code == "1234" else {
                throw NSError(
                    domain: "EmailValidation", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid code. 4 attempts remaining."]
                )
            }
            return VerifyCodeResult(customToken: "preview-token", isNewUser: true)
        }
    )
}
