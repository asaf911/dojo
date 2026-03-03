import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import AuthenticationServices
import Mixpanel
import CryptoKit

/// Provides direct Firebase sign-in with social credentials.
/// The Auth feature uses credential + UserIdentityManager.linkWithSocialCredential for unified flow.
/// These methods are retained for potential future use (e.g. re-auth, account linking UI).
class AuthenticationServicesManager {
    // Retain the Apple sign-in delegate to prevent it from being deallocated prematurely.
    static var currentAppleDelegate: AppleSignInDelegate?

    /// Updated to return AuthDataResult instead of just FirebaseAuth.User.
    static func signInWithGoogle(completion: @escaping (Result<AuthDataResult, Error>) -> Void) {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            let error = NSError(domain: "AuthenticationServicesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get clientID"])
            completion(.failure(error))
            return
        }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            let error = NSError(domain: "AuthenticationServicesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root view controller"])
            completion(.failure(error))
            return
        }
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { signInResult, error in
            if let error = error {
                print("AuthenticationServicesManager: Google sign in error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let signInResult = signInResult else {
                let error = NSError(domain: "AuthenticationServicesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No sign-in result"])
                print("AuthenticationServicesManager: Google sign in failed - no result")
                completion(.failure(error))
                return
            }
            let user = signInResult.user
            guard let idToken = user.idToken?.tokenString else {
                let error = NSError(domain: "AuthenticationServicesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token"])
                print("AuthenticationServicesManager: Google sign in failed - no ID token")
                completion(.failure(error))
                return
            }
            let accessToken = user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    print("AuthenticationServicesManager: Firebase sign in with Google credential failed: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                if let authResult = authResult {
                    // Save user display name and profile image if available
                    if let profile = user.profile {
                        let displayName = profile.name
                        print("AuthenticationServicesManager: Saving Google user display name: \(displayName)")
                        SharedUserStorage.save(value: displayName, forKey: .userName)
                        
                        // Save profile picture URL (200px dimension)
                        if let imageURL = profile.imageURL(withDimension: 200) {
                            print("AuthenticationServicesManager: Saving Google user profile image URL")
                            SharedUserStorage.save(value: imageURL.absoluteString, forKey: .userProfileImageURL)
                        }
                    }
                    
                    print("AuthenticationServicesManager: Firebase Google sign in successful for user: \(authResult.user.email ?? "unknown")")
                    completion(.success(authResult))
                } else {
                    let error = NSError(domain: "AuthenticationServicesManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user returned after social sign in"])
                    print("AuthenticationServicesManager: Google sign in failed - no user returned")
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Updated to return AuthDataResult instead of just FirebaseAuth.User.
    static func signInWithApple(completion: @escaping (Result<AuthDataResult, Error>) -> Void) {
        // Generate a secure random nonce.
        let rawNonce = randomNonceString()
        print("AuthenticationServicesManager: Generated raw nonce: \(rawNonce)")
        // Compute SHA256 hash of the nonce.
        let hashedNonce = sha256(rawNonce)
        print("AuthenticationServicesManager: Hashed nonce for Apple sign in: \(hashedNonce)")
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleSignInDelegate(completion: completion, nonce: rawNonce)
        // Retain the delegate to prevent deallocation.
        currentAppleDelegate = delegate
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        print("AuthenticationServicesManager: Starting Apple sign in request.")
        controller.performRequests()
    }
    
    // MARK: - Helper Functions for Nonce Generation
    
    private static func randomNonceString(length: Int = 32) -> String {
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
    
    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// Helper class to handle Apple Sign-In delegation.
class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<AuthDataResult, Error>) -> Void
    private let nonce: String
    
    init(completion: @escaping (Result<AuthDataResult, Error>) -> Void, nonce: String) {
        self.completion = completion
        self.nonce = nonce
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            fatalError("AppleSignInDelegate: No key window available")
        }
        return window
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("AppleSignInDelegate: Did complete with authorization.")
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            // Extract and save full name if available
            if let fullName = appleIDCredential.fullName {
                let formatter = PersonNameComponentsFormatter()
                formatter.style = .default
                let displayName = formatter.string(from: fullName)
                if !displayName.isEmpty {
                    print("AppleSignInDelegate: Saving Apple user display name: \(displayName)")
                    SharedUserStorage.save(value: displayName, forKey: .userName)
                } else if let givenName = fullName.givenName {
                    // Fallback to just the first name if the formatter returns empty
                    print("AppleSignInDelegate: Saving Apple user given name: \(givenName)")
                    SharedUserStorage.save(value: givenName, forKey: .userName)
                }
            }
            
            guard let identityToken = appleIDCredential.identityToken else {
                let error = NSError(domain: "AppleSignInDelegate", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get identity token"])
                print("AppleSignInDelegate: \(error.localizedDescription)")
                completion(.failure(error))
                // Clear the retained delegate.
                AuthenticationServicesManager.currentAppleDelegate = nil
                return
            }
            let tokenString = String(data: identityToken, encoding: .utf8) ?? ""
            print("AppleSignInDelegate: Received identity token: \(tokenString.prefix(20))...") // Print first 20 characters
            let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: tokenString, rawNonce: nonce)
            Auth.auth().signIn(with: credential) { authResult, error in
                // Clear the retained delegate once we have a result.
                AuthenticationServicesManager.currentAppleDelegate = nil
                if let error = error {
                    print("AppleSignInDelegate: Firebase sign in failed: \(error.localizedDescription)")
                    self.completion(.failure(error))
                    return
                }
                if let authResult = authResult {
                    print("AppleSignInDelegate: Firebase sign in successful for user: \(authResult.user.email ?? "unknown")")
                    self.completion(.success(authResult))
                } else {
                    let error = NSError(domain: "AppleSignInDelegate", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user returned after Apple sign in"])
                    print("AppleSignInDelegate: \(error.localizedDescription)")
                    self.completion(.failure(error))
                }
            }
        } else {
            let error = NSError(domain: "AppleSignInDelegate", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected credential type"])
            print("AppleSignInDelegate: \(error.localizedDescription)")
            completion(.failure(error))
            AuthenticationServicesManager.currentAppleDelegate = nil
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("AppleSignInDelegate: Did complete with error: \(error.localizedDescription)")
        completion(.failure(error))
        AuthenticationServicesManager.currentAppleDelegate = nil
    }
}
