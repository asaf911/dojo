import FirebaseAuth

// MARK: - AuthenticationAnalyticsManager
//
// Records analytics events for authentication flows.
//
// Responsibilities:
//   - Fire sign_up / sign_in / auth_error events
//
// Out of scope (handled by UserIdentityManager):
//   - Mixpanel.identify()  ← NEVER call from here
//   - Mixpanel.createAlias() ← NEVER call from here
//
// Console filter: 📊 [AUTH:EVENT]

class AuthenticationAnalyticsManager {

    static let shared = AuthenticationAnalyticsManager()
    private init() {}

    private static func log(_ message: String) {
        print("📊 [AUTH:EVENT] \(message)")
    }

    // MARK: - Email Authentication

    /// Records a sign-up event for email authentication.
    func recordEmailSignUp() {
        let uid = UserIdentityManager.shared.currentUserId
        recordSignUp(uid: uid, method: "email")
    }

    /// Records a sign-up event for any authentication method.
    /// Identity must already be set by UserIdentityManager.transitionToAuthenticated() before calling this.
    func recordSignUp(uid: String, method: String) {
        Self.log("sign_up method=\(method) uid=\(uid.isEmpty ? "EMPTY" : uid)")
        AnalyticsManager.shared.logEvent("sign_up", parameters: [
            "method": method,
            "firebase_uid": uid
        ])
        Self.log("✅ sign_up logged")
    }

    /// Records a sign-in event for email authentication.
    func recordEmailSignIn() {
        Self.log("sign_in method=email")
        AnalyticsManager.shared.logEvent("sign_in", parameters: ["method": "email"])
    }

    // MARK: - Social Authentication

    /// Records a sign-in event for social providers (returning users only).
    func recordSocialSignIn(method: String) {
        Self.log("sign_in method=\(method)")
        AnalyticsManager.shared.logEvent("sign_in", parameters: ["method": method])
    }

    /// Records authentication events for social providers.
    /// sign_up only for new users, sign_in only for returning users.
    /// Identity must already be set by UserIdentityManager.transitionToAuthenticated() before calling this.
    func recordSocialAuthentication(authResult: AuthDataResult, method: String) {
        let uid = authResult.user.uid
        let isNewUser = authResult.additionalUserInfo?.isNewUser ?? false

        Self.log("social auth method=\(method) isNewUser=\(isNewUser) uid=\(uid)")

        if isNewUser {
            recordSignUp(uid: uid, method: method)
            Self.log("✅ sign_up logged for \(method)")
        } else {
            recordSocialSignIn(method: method)
            Self.log("✅ sign_in logged for \(method)")
        }
    }

    // MARK: - Error Reporting

    /// Records an authentication error event.
    func recordAuthError(error: Error) {
        let nsError = error as NSError
        Self.log("auth_error code=\(nsError.code) message=\(nsError.localizedDescription)")
        AnalyticsManager.shared.logEvent("auth_error", parameters: [
            "error_code": nsError.code,
            "friendly_message": nsError.localizedDescription
        ])
    }
}
