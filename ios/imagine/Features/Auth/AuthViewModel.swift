// AuthViewModel.swift
// Dojo
// Updated by Asaf Shamir on 2025-04-02

import Combine
import FirebaseAuth
import FirebaseFirestore
import KeychainSwift
import Mixpanel
import AppsFlyerLib
import RevenueCat
import CryptoKit
import AppTrackingTransparency
import AdSupport
import SwiftUI
import Firebase
import FirebaseAnalytics

enum AuthenticationMethod: String, Codable {
    case email = "email"
    case google = "google"
    case apple = "apple"
    case guest = "guest"
    case none = "none"
}

class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    
    // Change from private to private(set) to allow read access but maintain write protection
    private(set) var appState: AppState?
    
    private let keychain = KeychainSwift()

    init(appState: AppState? = nil) {
        self.appState = appState
        checkAuthenticationStatus()
    }
    
    // Method to set the AppState reference if not set during init
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    private func checkAuthenticationStatus() {
        isAuthenticated = Auth.auth().currentUser != nil
        
        // Update AppState if available
        if let appState = appState {
            if isAuthenticated {
                appState.setAuthenticated()
            }
        }
    }

    func updateAuthenticationStatus(user: FirebaseAuth.User?) {
        DispatchQueue.main.async {
            self.isAuthenticated = (user != nil)
            
            // Update AppState if available
            if let appState = self.appState {
                if self.isAuthenticated {
                    appState.setAuthenticated()
                } else {
                    appState.signOut()
                }
            }
        }
    }

    func handlePostAuthentication(user: FirebaseAuth.User) {
        let userEmail = user.email ?? "no email"
        print("📊 [AUTH:POSTAUTH] handlePostAuthentication uid=\(user.uid)")

        FirestoreManager.shared.updateUserTimezone()
        FirestoreManager.shared.updateLastActiveDate()
        FirestoreManager.shared.updateHashedEmail(hashedEmail: hashEmail(userEmail))

        // Identity is already set by UserIdentityManager.transitionToAuthenticated().
        // Only update people properties here — never call identify() from this method.
        Mixpanel.mainInstance().people.set(properties: [
            "$email": hashEmail(userEmail),
            "user_type": "authenticated",
            "is_authenticated": true,
            "first_seen_at": Date()
        ])

        // Log analytics event for user login
        AnalyticsManager.shared.logEvent("user_login", parameters: [
            "user_id": user.uid,
            "method": SharedUserStorage.retrieve(forKey: .authenticationMethod, as: AuthenticationMethod.self)?.rawValue ?? "unknown"
        ])

        // Configure vendor attributes (AppsFlyer, RevenueCat, push) — no identify() call
        self.setAnalyticsUserIdentifiers(uid: user.uid, userEmail: userEmail)

        FirestoreManager.shared.fetchCumulativeMeditationTime { totalTime in
            SharedUserStorage.save(value: totalTime, forKey: .cumulativeMeditationTime)
            NotificationCenter.default.post(name: .didUpdateCumulativeMeditationTime, object: nil)
        }

        // Use StreakManager for syncing streak data
        StreakManager.shared.syncFromFirestore { success in
            if success {
                NotificationCenter.default.post(name: .didUpdateMeditationStreak, object: nil)
                NotificationCenter.default.post(name: .didUpdateLongestMeditationStreak, object: nil)
            }
        }

        FirestoreManager.shared.fetchSessionCount { count in
            SharedUserStorage.save(value: count, forKey: .sessionCount)
            NotificationCenter.default.post(name: .didUpdateSessionCount, object: nil)
        }

        FirestoreManager.shared.fetchTotalSessionDuration { totalDuration in
            SharedUserStorage.save(value: totalDuration, forKey: .totalSessionDuration)
            NotificationCenter.default.post(name: .didUpdateAverageSessionDuration, object: nil)
        }

        FirestoreManager.shared.fetchLongestSessionDuration { duration in
            SharedUserStorage.save(value: duration, forKey: .longestSessionDuration)
            NotificationCenter.default.post(name: .didUpdateLongestSessionDuration, object: nil)
        }
        
        // Sync user preferences from/to Firebase (handles new device restoration)
        UserPreferencesManager.shared.handleUserAuthenticated()
    }

    func setAnalyticsUserIdentifiers(uid: String, userEmail: String) {
        print("📊 [AUTH:POSTAUTH] setAnalyticsUserIdentifiers uid=\(uid)")

        let hashedEmail = hashEmail(userEmail)

        // Identity is already set by UserIdentityManager.transitionToAuthenticated().
        // Only set people properties here — never call identify() from this method.
        Mixpanel.mainInstance().people.set(properties: [
            "$email": hashedEmail,
            "$displayName": SharedUserStorage.retrieve(forKey: .userName, as: String.self) ?? "",
            "user_type": "authenticated",
            "is_authenticated": true
        ])
        print("📊 [AUTH:POSTAUTH] Mixpanel people properties set for uid=\(uid)")
        
        // AppsFlyer
        AppsFlyerManager.shared.setCustomerUserID(uid)
        let appsFlyerID = AppsFlyerLib.shared().getAppsFlyerUID()
        print("📊 [AUTH:POSTAUTH] AppsFlyer customerUserID=\(uid) appsFlyerID=\(appsFlyerID)")

        // RevenueCat — set attribution attributes only (login handled by UserIdentityManager)
        Purchases.shared.logIn(uid) { (_, _, error) in
            if let error = error {
                print("📊 [AUTH:POSTAUTH] RevenueCat login error: \(error.localizedDescription)")
            } else {
                if let displayName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)?
                                       .trimmingCharacters(in: .whitespacesAndNewlines),
                   !displayName.isEmpty {
                    let mixpanelID = Mixpanel.mainInstance().distinctId
                    DispatchQueue.main.async {
                        Purchases.shared.attribution.setAttributes([
                            "$mixpanelDistinctId": mixpanelID,
                            "$appsflyerId": appsFlyerID,
                            "$idfa": ASIdentifierManager.shared().advertisingIdentifier.uuidString,
                            "$email": userEmail,
                            "$displayName": displayName
                        ])
                        print("📊 [AUTH:POSTAUTH] RevenueCat attributes set displayName=\(displayName)")
                    }
                }
            }
        }

        // Push Notifications — login and set email; permission prompt deferred to subscription phase
        pushService.login(userId: uid)
        pushService.setEmail(userEmail)
        print("📊 [AUTH:POSTAUTH] Push service configured uid=\(uid)")
    }

    private func hashEmail(_ email: String) -> String {
        let inputData = Data(email.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    func logout() {
        let currentAuthMethod = SharedUserStorage.retrieve(forKey: .authenticationMethod, as: AuthenticationMethod.self) ?? .none
        let isCurrentlyGuest = appState?.isGuest ?? SharedUserStorage.retrieve(forKey: .isGuest, as: Bool.self) ?? false
        print("📊 [AUTH:POSTAUTH] logout — method=\(currentAuthMethod) isGuest=\(isCurrentlyGuest)")

        isAuthenticated = false
        GlobalErrorManager.shared.error = nil

        if isCurrentlyGuest || currentAuthMethod == .guest {
            print("📊 [AUTH:POSTAUTH] Guest logout — preserving Firebase user")
            if let appState = appState {
                appState.isAuthenticated = false
                appState.isGuest = false
                appState.needsOnboarding = false
                SharedUserStorage.save(value: false, forKey: .isAuthenticated)
                SharedUserStorage.save(value: false, forKey: .isGuest)
            }
            clearUserStatsOnLogout()
        } else {
            print("📊 [AUTH:POSTAUTH] Authenticated logout — preserving Firebase user for guest reuse")
            appState?.signOut()
        }

        SharedUserStorage.save(value: AuthenticationMethod.none, forKey: .authenticationMethod)
        AnalyticsManager.shared.logEvent("sign_out", parameters: [
            "method": "user_action",
            "previous_auth_method": currentAuthMethod.rawValue,
            "was_guest": isCurrentlyGuest
        ])
        print("📊 [AUTH:POSTAUTH] ✅ Logout complete")
    }

    private func clearUserStatsOnLogout() {
        print("📊 [AUTH:POSTAUTH] Clearing user stats from local storage")
        SharedUserStorage.delete(forKey: .sessionCount)
        SharedUserStorage.delete(forKey: .totalSessionDuration)
        SharedUserStorage.delete(forKey: .longestSessionDuration)
        SharedUserStorage.delete(forKey: .meditationStreak)
        SharedUserStorage.delete(forKey: .longestMeditationStreak)
        SharedUserStorage.delete(forKey: .lastMeditationDate)
        SharedUserStorage.delete(forKey: .cumulativeMeditationTime)
        print("📊 [AUTH:POSTAUTH] User stats cleared")
    }

    func switchToGuestMode() {
        print("📊 [AUTH:POSTAUTH] Switching to guest mode")
        isAuthenticated = true
        GlobalErrorManager.shared.error = nil

        if let appState = appState {
            appState.setAuthenticated(isGuest: true)
        }

        SharedUserStorage.save(value: AuthenticationMethod.guest, forKey: .authenticationMethod)
        UserIdentityManager.shared.switchToGuestMode()
        AnalyticsManager.shared.logEvent("switch_to_guest_mode", parameters: ["method": "preserve_firebase_user"])
        print("📊 [AUTH:POSTAUTH] ✅ Guest mode active")
    }

    func deleteAccount(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            GlobalErrorManager.shared.error = .custom(message: "No user is currently logged in.")
            completion(false)
            return
        }

        user.delete { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    GlobalErrorManager.shared.error = .custom(message: "Failed to delete account: \(error.localizedDescription)")
                    AuthenticationAnalyticsManager.shared.recordAuthError(error: error)
                    completion(false)
                } else {
                    print("📊 [AUTH:POSTAUTH] Account deleted successfully")
                    self?.isAuthenticated = false
                    if let appState = self?.appState { appState.signOut() }
                    completion(true)
                    AnalyticsManager.shared.logEvent("delete_account", parameters: [
                        "method": SharedUserStorage.retrieve(forKey: .authenticationMethod, as: AuthenticationMethod.self)?.rawValue ?? "unknown"
                    ])
                }
            }
        }
    }
    
    func updateDisplayNameInRevenueCat(newDisplayName: String) {
        guard validateDisplayName(newDisplayName) else {
            print("AuthViewModel: Invalid display name: \(newDisplayName). Display name not updated in RevenueCat.")
            return
        }
        
        SharedUserStorage.save(value: newDisplayName, forKey: .userName)
        
        guard Auth.auth().currentUser != nil else {
            print("AuthViewModel: No authenticated user found. Cannot update RevenueCat displayName.")
            return
        }
        
        Purchases.shared.attribution.setAttributes([
            "displayName": newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        
        print("📊 [AUTH:POSTAUTH] RevenueCat displayName set to: \(newDisplayName)")
    }
    
    private func validateDisplayName(_ displayName: String) -> Bool {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedDisplayName.isEmpty && trimmedDisplayName.count <= 50
    }
}
