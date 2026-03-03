//
//  Authentication+ViewModel.swift
//  imagine
//
//  Created by Asaf Shamir on 2026-02-12
//
//  Unified auth flow: Google, Apple, and Email all use the same underlying logic.
//  Sign-up vs sign-in is determined by Firebase/backend result, not by screen mode.
//
//  Enforced call order in every auth success path:
//    1. UserIdentityManager.transitionToAuthenticated()  ← identity first
//    2. AuthenticationAnalyticsManager.recordSignUp/In() ← events second
//    3. authViewModel.handlePostAuthentication()         ← side effects third
//
// Console filter tags:
//   📊 [AUTH:SOCIAL]  — unified social auth (Google, Apple) — link or direct
//   📊 [AUTH:SIGNUP] — sign-up outcome (link success or isNewUser)
//   📊 [AUTH:SIGNIN] — sign-in outcome (returning user)
//   📊 [AUTH:EMAIL]  — email code request / verification

import UIKit
import Firebase
import FirebaseCore
import GoogleSignIn
import Combine
import FirebaseAuth
import AuthenticationServices
import CommonCrypto
import RevenueCat
import FirebaseFirestore
import CryptoKit

// MARK: - Logging

private func log(_ tag: String, _ message: String) {
    print("📊 [\(tag)] \(message)")
}

// MARK: - AuthenticationViewModel

class AuthenticationViewModel: NSObject, ObservableObject {
    @Published var user: FirebaseAuth.User?
    @Published var isLoading = false
    @Published var isAuthenticated = false

    let mode: Authentication.Mode
    private var cancellables = Set<AnyCancellable>()
    private var authViewModel: AuthViewModel
    private let emailValidationService: EmailValidationService = .live

    /// Strong reference to Apple Sign-In delegate to prevent deallocation (signUp link flow only).
    private var currentAppleDelegate: AppleSignInDirectDelegate?

    init(mode: Authentication.Mode, authViewModel: AuthViewModel) {
        self.mode = mode
        self.authViewModel = authViewModel
    }

    // MARK: - Email Code Verification (shared)

    /// Request a 4-digit verification code to be sent to the given email.
    func requestVerificationCode(email: String) async throws {
        log("AUTH:EMAIL", "Requesting code for: \(email)")
        AnalyticsManager.shared.logEvent("email_code_requested", parameters: [
            "method": "email",
            "is_resend": false
        ])
        try await emailValidationService.requestCode(email)
        log("AUTH:EMAIL", "Code sent successfully to: \(email)")
    }

    /// Verify the 4-digit code and sign in with the returned custom token.
    /// Calls completion with (success, isNewUser).
    func verifyCodeAndSignIn(email: String, code: String, completion: @escaping (Bool, Bool) -> Void) {
        log("AUTH:EMAIL", "Verifying code for: \(email)")

        Task { @MainActor in
            do {
                let result = try await emailValidationService.verifyCode(email, code)
                let authResult = try await Auth.auth().signIn(withCustomToken: result.customToken)
                let user = authResult.user
                log("AUTH:EMAIL", "Custom token sign-in SUCCESS uid=\(user.uid) isNewUser=\(result.isNewUser)")

                SharedUserStorage.save(value: AuthenticationMethod.email, forKey: .authenticationMethod)
                SharedUserStorage.save(value: email, forKey: .lastUsedEmail)

                // 1. Identity transition FIRST — alias + identify happens here
                UserIdentityManager.shared.transitionToAuthenticated(uid: user.uid, method: "email")

                if result.isNewUser {
                    // 2. Record event AFTER identity is set
                    AuthenticationAnalyticsManager.shared.recordSignUp(uid: user.uid, method: "email")
                    log("AUTH:EMAIL", "sign_up logged for new email user uid=\(user.uid)")
                } else {
                    AuthenticationAnalyticsManager.shared.recordEmailSignIn()
                    log("AUTH:EMAIL", "sign_in logged for returning email user uid=\(user.uid)")
                }

                AnalyticsManager.shared.logEvent("email_code_verified", parameters: [
                    "is_new_user": result.isNewUser
                ])

                // 3. Post-auth side effects
                self.authViewModel.updateAuthenticationStatus(user: user)
                self.authViewModel.handlePostAuthentication(user: user)

                completion(true, result.isNewUser)
            } catch {
                log("AUTH:EMAIL", "Verification FAILED: \(error.localizedDescription)")
                AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
                GlobalErrorManager.shared.error = .custom(message: error.localizedDescription)
                completion(false, false)
            }
        }
    }

    // MARK: - Google Auth (unified)

    func signInWithGoogle(completion: @escaping (Bool, Bool) -> Void) {
        linkGoogleCredential(completion: completion)
    }

    // MARK: - Apple Auth (unified)

    func signInWithApple(completion: @escaping (Bool, Bool) -> Void) {
        linkAppleCredential(completion: completion)
    }

    // MARK: - Social Auth: Google Credential

    private func linkGoogleCredential(completion: @escaping (Bool, Bool) -> Void) {
        log("AUTH:SOCIAL", "Google auth started — uid=\(UserIdentityManager.shared.currentUserId)")

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            let error = NSError(domain: "AuthenticationViewModel", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get clientID"])
            AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
            GlobalErrorManager.shared.error = .custom(message: "Configuration error")
            completion(false, false)
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            let error = NSError(domain: "AuthenticationViewModel", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No root view controller"])
            AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
            GlobalErrorManager.shared.error = .custom(message: "UI error")
            completion(false, false)
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] signInResult, error in
            DispatchQueue.main.async {
                if let error = error {
                    log("AUTH:SOCIAL", "FAILED method=google error=\(error.localizedDescription)")
                    AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
                    GlobalErrorManager.shared.error = .custom(message: error.localizedDescription)
                    completion(false, false)
                    return
                }

                guard let signInResult = signInResult else {
                    let error = NSError(domain: "AuthenticationViewModel", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No sign-in result"])
                    AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
                    GlobalErrorManager.shared.error = .custom(message: "Google sign-in failed")
                    completion(false, false)
                    return
                }

                let user = signInResult.user
                guard let idToken = user.idToken?.tokenString else {
                    let error = NSError(domain: "AuthenticationViewModel", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token"])
                    AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
                    GlobalErrorManager.shared.error = .custom(message: "Google authentication failed")
                    completion(false, false)
                    return
                }

                if let profile = user.profile {
                    SharedUserStorage.save(value: profile.name, forKey: .userName)
                }

                let accessToken = user.accessToken.tokenString
                let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

                UserIdentityManager.shared.linkWithSocialCredential(credential) { linkResult in
                    DispatchQueue.main.async {
                        switch linkResult {
                        case .success(let socialResult):
                            self?.handleSocialAuthSuccess(socialResult, method: "google", completion: completion)
                        case .failure(let error):
                            log("AUTH:SOCIAL", "FAILED method=google error=\(error.localizedDescription)")
                            AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
                            GlobalErrorManager.shared.error = .custom(message: error.localizedDescription)
                            completion(false, false)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Social Auth: Apple Credential

    private func linkAppleCredential(completion: @escaping (Bool, Bool) -> Void) {
        log("AUTH:SOCIAL", "Apple auth started — uid=\(UserIdentityManager.shared.currentUserId)")

        let rawNonce = randomNonceString()
        let hashedNonce = sha256(rawNonce)

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleSignInDirectDelegate(completion: { [weak self] result in
            DispatchQueue.main.async {
                self?.currentAppleDelegate = nil

                switch result {
                case .success(let credential):
                    log("AUTH:SOCIAL", "Apple credential obtained — linking")

                    UserIdentityManager.shared.linkWithSocialCredential(credential) { linkResult in
                        DispatchQueue.main.async {
                            switch linkResult {
                            case .success(let socialResult):
                                self?.handleSocialAuthSuccess(socialResult, method: "apple", completion: completion)
                            case .failure(let error):
                                log("AUTH:SOCIAL", "FAILED method=apple error=\(error.localizedDescription)")
                                AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
                                GlobalErrorManager.shared.error = .custom(message: error.localizedDescription)
                                completion(false, false)
                            }
                        }
                    }

                case .failure(let error):
                    log("AUTH:SOCIAL", "FAILED method=apple error=\(error.localizedDescription)")
                    AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
                    GlobalErrorManager.shared.error = .custom(message: error.localizedDescription)
                    completion(false, false)
                }
            }
        }, nonce: rawNonce)

        self.currentAppleDelegate = delegate
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        controller.performRequests()
    }

    // MARK: - Social Auth Success Handler

    private func handleSocialAuthSuccess(_ result: SocialAuthResult, method: String, completion: @escaping (Bool, Bool) -> Void) {
        let uid = result.authResult.user.uid
        let isNewUser = result.wasLinked || (result.authResult.additionalUserInfo?.isNewUser ?? false)

        log("AUTH:SOCIAL", "SUCCESS method=\(method) wasLinked=\(result.wasLinked) isNewUser=\(isNewUser) uid=\(uid)")

        SharedUserStorage.save(value: method == "google" ? AuthenticationMethod.google : AuthenticationMethod.apple, forKey: .authenticationMethod)

        // 1. Identity transition FIRST
        UserIdentityManager.shared.transitionToAuthenticated(uid: uid, method: method)

        // 2. Record event AFTER identity is set
        if isNewUser {
            AuthenticationAnalyticsManager.shared.recordSignUp(uid: uid, method: method)
        } else {
            AuthenticationAnalyticsManager.shared.recordSocialSignIn(method: method)
        }

        // 3. Post-auth side effects
        authViewModel.updateAuthenticationStatus(user: result.authResult.user)
        authViewModel.handlePostAuthentication(user: result.authResult.user)

        completion(true, isNewUser)
    }

    // MARK: - Private Helpers (Apple nonce generation)

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var random: UInt8 = 0
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }
            if random < charset.count {
                result.append(charset[Int(random) % charset.count])
                remainingLength -= 1
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AppleSignInDirectDelegate

/// Direct Apple Sign-In delegate that returns a credential instead of signing in.
/// Used exclusively by the signUp link flow to link Apple credentials to an anonymous user.
class AppleSignInDirectDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<AuthCredential, Error>) -> Void
    private let nonce: String

    init(completion: @escaping (Result<AuthCredential, Error>) -> Void, nonce: String) {
        self.completion = completion
        self.nonce = nonce
        super.init()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            fatalError("AppleSignInDirectDelegate: No key window available")
        }
        return window
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            let error = NSError(domain: "AppleSignInDirectDelegate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected credential type"])
            completion(.failure(error))
            return
        }

        if let fullName = appleIDCredential.fullName {
            let formatter = PersonNameComponentsFormatter()
            formatter.style = .default
            let displayName = formatter.string(from: fullName)
            if !displayName.isEmpty {
                SharedUserStorage.save(value: displayName, forKey: .userName)
            } else if let givenName = fullName.givenName {
                SharedUserStorage.save(value: givenName, forKey: .userName)
            }
        }

        guard let identityToken = appleIDCredential.identityToken else {
            let error = NSError(domain: "AppleSignInDirectDelegate", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get identity token"])
            completion(.failure(error))
            return
        }

        let tokenString = String(data: identityToken, encoding: .utf8) ?? ""
        let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: tokenString, rawNonce: nonce)
        completion(.success(credential))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }
}
