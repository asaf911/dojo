import UIKit
import FirebaseAuth
import Mixpanel
import RevenueCat

// MARK: - UserIdentityManager
//
// Single source of truth for user identity across all analytics vendors.
//
// Lifecycle:
//   1. boot()                        — called once from AppDelegate, every launch
//   2. transitionToAuthenticated()   — called once after any sign-up or sign-in, BEFORE recording events
//   3. onSignOut()                   — called when user signs out
//
// Identity rule:
//   This is the ONLY file that calls Mixpanel.identify().
//   No other file may call that method directly.
//
// Mixpanel identity strategy (Simplified ID Merge):
//   - Anonymous users: identify() is NOT called. Mixpanel uses its own internal device ID.
//   - On auth: identify(firebaseUID) is called once. Mixpanel automatically sends a
//     $identify event linking the anonymous device ID → firebaseUID on its backend.
//   - This is the correct approach for Mixpanel Simplified ID Merge projects.
//   - createAlias() is intentionally NOT used — it is incompatible with Simplified ID Merge.
//
// Console filter tags:
//   📊 [ID:BOOT]        — boot, anonymous user creation
//   📊 [ID:TRANSITION]  — transitionToAuthenticated (identify + stitching)
//   📊 [ID:VENDOR]      — vendor configuration (RevenueCat, AppsFlyer, push)
//   📊 [ID:LIFECYCLE]   — install / reinstall tracking
//   📊 [ID:SOCIAL]      — linkWithSocialCredential (link or fallback)
//   📊 [ID:SIGNOUT]     — sign-out and cleanup

// MARK: - SocialAuthResult

/// Result of linkWithSocialCredential. Indicates whether link succeeded or fallback to direct sign-in was used.
struct SocialAuthResult {
    let authResult: AuthDataResult
    /// true = credential was linked to anonymous user; false = fell back to direct sign-in
    let wasLinked: Bool
}

// MARK: - UserIdentityManager

class UserIdentityManager {

    static let shared = UserIdentityManager()
    private let logger = Logger(subsystem: "UserIdentityManager", category: "Identity")

    // MARK: - Logging

    private static func log(_ tag: String, _ message: String) {
        print("📊 [\(tag)] \(message)")
    }

    private func log(_ tag: String, _ message: String) {
        Self.log(tag, message)
    }

    // MARK: - Public State

    /// Always returns the current Firebase UID (anonymous or authenticated).
    var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    var isAuthenticated: Bool {
        guard let user = Auth.auth().currentUser else { return false }
        return !user.isAnonymous
    }

    var isAnonymous: Bool {
        Auth.auth().currentUser?.isAnonymous ?? true
    }

    /// True once boot() has finished establishing a Firebase user and configuring Mixpanel.
    private(set) var isIdentityReady = false

    // MARK: - Private State

    private weak var appState: AnyObject?

    /// Strong reference to prevent deallocation when Apple Sign-In overrides Auth.currentUser.
    private var pendingAnonymousUser: FirebaseAuth.User?

    private var hasBootstrapped = false
    private var hasSetUpSubscriptionListener = false
    private var subscriptionDebounce: DispatchWorkItem?
    private var anonymousSignInRetryCount = 0
    private let maxAnonymousSignInRetries = 3

    private init() {}

    // MARK: - AppState Reference

    func setAppState(_ appState: AnyObject) {
        self.appState = appState
        log("ID:BOOT", "AppState reference configured")
    }

    private func refreshAppStateOnboardingIfNeeded() {
        if let appState = self.appState,
           appState.responds(to: Selector(("refreshOnboardingState"))) {
            _ = appState.perform(Selector(("refreshOnboardingState")))
            log("ID:BOOT", "Refreshed AppState onboarding state")
        }
    }

    // MARK: - Vendor Configuration Retry

    func retryVendorConfiguration() {
        log("ID:VENDOR", "Retrying vendor configuration")
        configureAllVendors()
    }

    // MARK: - Boot

    /// Call once from AppDelegate.didFinishLaunchingWithOptions, after all SDK initialisation.
    func bootstrapIfNeeded() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        boot()
    }

    private func boot() {
        log("ID:BOOT", "========== BOOT ==========")

        // Reset per-session state
        pendingAnonymousUser = nil
        anonymousSignInRetryCount = 0

        if let existingUser = Auth.auth().currentUser {
            log("ID:BOOT", "Existing user: uid=\(existingUser.uid) anonymous=\(existingUser.isAnonymous)")
            validateExistingUser(existingUser) { [weak self] isValid in
                if isValid {
                    Self.log("ID:BOOT", "User validated — finalising boot")
                    self?.finalizeBoot(with: existingUser)
                } else {
                    Self.log("ID:BOOT", "User invalid on server — creating fresh anonymous user")
                    self?.createAnonymousUser()
                }
            }
        } else {
            log("ID:BOOT", "No existing user — creating anonymous user")
            createAnonymousUser()
        }
    }

    // MARK: - Boot Helpers

    private func validateExistingUser(_ user: FirebaseAuth.User, completion: @escaping (Bool) -> Void) {
        user.reload { error in
            if let error = error {
                let isDeleted = error.localizedDescription.contains("no user record") ||
                                error.localizedDescription.contains("user may have been deleted")
                if isDeleted {
                    UserIdentityManager.log("ID:BOOT", "User deleted from server")
                    completion(false)
                } else {
                    UserIdentityManager.log("ID:BOOT", "Reload error (assuming valid): \(error.localizedDescription)")
                    completion(true)
                }
            } else {
                UserIdentityManager.log("ID:BOOT", "User exists on server")
                completion(true)
            }
        }
    }

    private func createAnonymousUser() {
        if anonymousSignInRetryCount == 0, Auth.auth().currentUser != nil {
            try? Auth.auth().signOut()
            log("ID:BOOT", "Signed out stale cached user")
        }

        log("ID:BOOT", "Creating anonymous user (attempt \(anonymousSignInRetryCount + 1)/\(maxAnonymousSignInRetries + 1))")

        Auth.auth().signInAnonymously { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                Self.log("ID:BOOT", "Anonymous sign-in failed: \(error.localizedDescription)")
                let nsError = error as NSError
                let isNetwork = nsError.code == 17020 ||
                                nsError.localizedDescription.lowercased().contains("network") ||
                                nsError.localizedDescription.lowercased().contains("timeout")
                if isNetwork && self.anonymousSignInRetryCount < self.maxAnonymousSignInRetries {
                    self.anonymousSignInRetryCount += 1
                    let delay = Double(self.anonymousSignInRetryCount) * 1.5
                    Self.log("ID:BOOT", "Retrying in \(delay)s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.createAnonymousUser()
                    }
                }
                return
            }

            guard let user = result?.user else { return }
            self.anonymousSignInRetryCount = 0
            self.pendingAnonymousUser = user
            Self.log("ID:BOOT", "Anonymous user created: uid=\(user.uid)")
            self.finalizeBoot(with: user)
        }
    }

    private func finalizeBoot(with user: FirebaseAuth.User) {
        let uid = user.uid

        if user.isAnonymous {
            // Anonymous users: do NOT call identify().
            // Mixpanel retains its own internal device ID for this session.
            // When the user authenticates, transitionToAuthenticated() calls identify(authUID)
            // and Mixpanel's backend automatically stitches pre-auth events (install, etc.)
            // to the authenticated profile via its $identify event mechanism.
            log("ID:BOOT", "Anonymous user — Mixpanel device ID preserved (no identify call)")
            log("ID:BOOT", "Mixpanel anonId=\(Mixpanel.mainInstance().distinctId)")
        } else {
            // Returning authenticated user — restore their Mixpanel identity on boot.
            Mixpanel.mainInstance().identify(distinctId: uid)
            Mixpanel.mainInstance().flush()
            log("ID:BOOT", "Returning authenticated user — Mixpanel identified as uid=\(uid)")
        }

        trackLifecycleEvents()
        configureAllVendors()

        isIdentityReady = true
        log("ID:BOOT", "✅ Boot complete — isIdentityReady=true firebase_uid=\(uid) authenticated=\(!user.isAnonymous)")
        log("ID:BOOT", "==========================")

        refreshAppStateOnboardingIfNeeded()
    }

    // MARK: - Auth Transition (THE critical method)

    /// Call after any successful sign-in or sign-up, BEFORE recording any analytics events.
    ///
    /// This is the ONLY place in the codebase that calls Mixpanel.identify().
    ///
    /// How stitching works (Mixpanel Simplified ID Merge):
    ///   1. During the anonymous phase, identify() was never called — Mixpanel retained
    ///      its own internal device ID (e.g. "$device:abc123").
    ///   2. Calling identify(authUID) here causes the SDK to send a $identify event:
    ///        { $anon_distinct_id: "$device:abc123", $identified_id: authUID }
    ///   3. Mixpanel's backend merges both profiles — all pre-auth events (install, etc.)
    ///      appear on the authenticated user's profile. Funnel connects automatically.
    func transitionToAuthenticated(uid: String, method: String) {
        // Capture Mixpanel's current anonymous device ID before calling identify().
        // This is what will be stitched to authUID on Mixpanel's backend.
        let anonMixpanelId = Mixpanel.mainInstance().distinctId

        log("ID:TRANSITION", "========== TRANSITION ==========")
        log("ID:TRANSITION", "firebase_uid=\(uid)")
        log("ID:TRANSITION", "method=\(method)")
        log("ID:TRANSITION", "mixpanel_anon_id=\(anonMixpanelId)")
        log("ID:TRANSITION", "will_stitch=\(anonMixpanelId != uid)")

        // Identify with the authenticated Firebase UID.
        // The SDK automatically sends $identify { anon: anonMixpanelId, identified: uid }
        // to Mixpanel's backend, stitching all pre-auth events to this profile.
        Mixpanel.mainInstance().identify(distinctId: uid)
        Mixpanel.mainInstance().flush()
        log("ID:TRANSITION", "✅ identify(\(uid)) called — Mixpanel $identify event sent")
        log("ID:TRANSITION", "✅ Backend will stitch: \(anonMixpanelId) → \(uid)")

        configureAllVendors()
        syncEntitlementsAfterLogin(uid: uid)
        SessionFirebaseSync.shared.performFullSync()

        // Record transition event — useful for verifying stitching in Mixpanel
        AnalyticsManager.shared.logEvent("identity_transition", parameters: [
            "uid": uid,
            "mixpanel_anon_id": anonMixpanelId,
            "stitched": anonMixpanelId != uid,
            "method": method
        ])

        log("ID:TRANSITION", "✅ Transition complete for uid=\(uid)")
        log("ID:TRANSITION", "================================")
    }

    // MARK: - Social Credential Linking

    /// Links a social credential to the existing anonymous user, preserving its UID.
    /// Falls back to direct sign-in if the anonymous user is unavailable or if the credential
    /// is already in use (AuthErrorCode.credentialAlreadyInUse / 17025).
    func linkWithSocialCredential(
        _ credential: AuthCredential,
        completion: @escaping (Result<SocialAuthResult, Error>) -> Void
    ) {
        log("ID:SOCIAL", "linkWithSocialCredential called")

        if let stored = pendingAnonymousUser, stored.isAnonymous {
            log("ID:SOCIAL", "Using stored anonymous user: \(stored.uid)")
            pendingAnonymousUser = nil
            linkCredential(credential, to: stored, completion: completion)
            return
        }

        if let current = Auth.auth().currentUser {
            log("ID:SOCIAL", "Current Firebase user: \(current.uid) anonymous=\(current.isAnonymous)")
            if current.isAnonymous {
                pendingAnonymousUser = nil
                linkCredential(credential, to: current, completion: completion)
            } else {
                log("ID:SOCIAL", "User already authenticated — falling back to direct sign-in")
                performDirectSocialSignIn(credential: credential) { result in
                    completion(result.map { SocialAuthResult(authResult: $0, wasLinked: false) })
                }
            }
        } else {
            log("ID:SOCIAL", "No Firebase user found — retrying after brief delay")
            retryLinkWithDelay(credential: credential, retryCount: 0, completion: completion)
        }
    }

    private func linkCredential(
        _ credential: AuthCredential,
        to user: FirebaseAuth.User,
        completion: @escaping (Result<SocialAuthResult, Error>) -> Void
    ) {
        user.link(with: credential) { [weak self] result, error in
            if let error = error {
                Self.log("ID:SOCIAL", "Link failed: \(error.localizedDescription)")
                self?.pendingAnonymousUser = nil
                let isCredentialInUse = (error as NSError).code == 17025 // AuthErrorCode.credentialAlreadyInUse
                if isCredentialInUse {
                    Self.log("ID:SOCIAL", "Credential already in use — falling back to direct sign-in")
                    self?.performDirectSocialSignIn(credential: credential) { directResult in
                        completion(directResult.map { SocialAuthResult(authResult: $0, wasLinked: false) })
                    }
                    return
                }
                let isDeleted = error.localizedDescription.contains("no user record") ||
                                error.localizedDescription.contains("user may have been deleted")
                if isDeleted {
                    Self.log("ID:SOCIAL", "Anonymous user deleted on server — falling back to direct sign-in")
                    self?.handleInvalidCachedUser { success in
                        if success {
                            self?.performDirectSocialSignIn(credential: credential) { directResult in
                                completion(directResult.map { SocialAuthResult(authResult: $0, wasLinked: false) })
                            }
                        } else {
                            completion(.failure(error))
                        }
                    }
                } else {
                    completion(.failure(error))
                }
                return
            }

            guard let result = result else {
                completion(.failure(NSError(domain: "UserIdentityManager", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No result from credential linking"])))
                return
            }

            Self.log("ID:SOCIAL", "✅ Linked — UID preserved: \(result.user.uid)")
            self?.configureAllVendors()
            completion(.success(SocialAuthResult(authResult: result, wasLinked: true)))
        }
    }

    private func retryLinkWithDelay(
        credential: AuthCredential,
        retryCount: Int,
        completion: @escaping (Result<SocialAuthResult, Error>) -> Void
    ) {
        guard retryCount < 3 else {
            log("ID:SOCIAL", "Max retries reached — falling back to direct sign-in")
            performDirectSocialSignIn(credential: credential) { result in
                completion(result.map { SocialAuthResult(authResult: $0, wasLinked: false) })
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if let current = Auth.auth().currentUser, current.isAnonymous {
                self.linkCredential(credential, to: current, completion: completion)
            } else {
                self.retryLinkWithDelay(credential: credential, retryCount: retryCount + 1, completion: completion)
            }
        }
    }

    private func performDirectSocialSignIn(
        credential: AuthCredential,
        completion: @escaping (Result<AuthDataResult, Error>) -> Void
    ) {
        log("ID:SOCIAL", "Direct sign-in (new UID will be created — alias handles stitching)")
        Auth.auth().signIn(with: credential) { [weak self] result, error in
            if let error = error {
                Self.log("ID:SOCIAL", "Direct sign-in failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let result = result else {
                completion(.failure(NSError(domain: "UserIdentityManager", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No result from direct sign-in"])))
                return
            }
            Self.log("ID:SOCIAL", "Direct sign-in succeeded: uid=\(result.user.uid)")
            self?.configureAllVendors()
            completion(.success(result))
        }
    }

    // MARK: - Sign Out

    func onSignOut() {
        log("ID:SIGNOUT", "Signing out uid=\(currentUserId)")
        pendingAnonymousUser = nil
        try? Auth.auth().signOut()
        log("ID:SIGNOUT", "✅ Signed out")
    }

    /// Preserves Firebase user; reconfigures vendors as anonymous context.
    func switchToGuestMode() {
        log("ID:SIGNOUT", "Switching to guest mode — preserving Firebase user uid=\(currentUserId)")
        if Auth.auth().currentUser == nil {
            createAnonymousUser()
        } else {
            configureAllVendors()
            refreshAppStateOnboardingIfNeeded()
        }
    }

    // MARK: - Private: Vendor Configuration

    func configureAllVendors() {
        let uid = currentUserId
        guard !uid.isEmpty else {
            log("ID:VENDOR", "No UID — skipping vendor configuration")
            return
        }

        log("ID:VENDOR", "Configuring vendors for uid=\(uid) anonymous=\(isAnonymous)")

        setupSubscriptionListenerIfNeeded()
        updateMixpanelProperties()

        if Purchases.isConfigured {
            Purchases.shared.logIn(uid) { _, _, error in
                if let error = error {
                    UserIdentityManager.log("ID:VENDOR", "RevenueCat login error: \(error.localizedDescription)")
                } else {
                    UserIdentityManager.log("ID:VENDOR", "RevenueCat configured uid=\(uid)")
                }
            }
        } else {
            log("ID:VENDOR", "RevenueCat not yet configured — skipping")
        }

        AppsFlyerManager.shared.setCustomerUserID(uid)
        log("ID:VENDOR", "AppsFlyer customerUserID=\(uid)")

        if !isAnonymous {
            pushService.login(userId: uid)
            log("ID:VENDOR", "Push notifications configured uid=\(uid)")
        } else {
            log("ID:VENDOR", "Push notifications skipped (anonymous user)")
        }
    }

    private func updateMixpanelProperties() {
        let mixpanel = Mixpanel.mainInstance()

        mixpanel.people.set(property: "user_type", to: isAuthenticated ? "authenticated" : "anonymous")
        mixpanel.people.set(property: "is_authenticated", to: isAuthenticated)

        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            mixpanel.people.set(property: "app_version", to: version)
        }

        let isSubscribed = SharedUserStorage.retrieve(forKey: .isUserSubscribed, as: Bool.self) ?? false
        mixpanel.people.set(property: "is_subscribed", to: isSubscribed)

        if let firstSeen = SharedUserStorage.retrieve(forKey: .firstSeenDate, as: Date.self) {
            mixpanel.people.set(property: "first_seen", to: firstSeen)
        }
        if let method = SharedUserStorage.retrieve(forKey: .installMethod, as: String.self) {
            mixpanel.people.set(property: "install_method", to: method)
        }
        if let source = SharedUserStorage.retrieve(forKey: .installSource, as: String.self) {
            mixpanel.people.set(property: "install_source", to: source)
        }
        if let version = SharedUserStorage.retrieve(forKey: .installAppVersion, as: String.self) {
            mixpanel.people.set(property: "install_app_version", to: version)
        }

        if isAuthenticated, let email = Auth.auth().currentUser?.email {
            let hash = email.data(using: .utf8)?.base64EncodedString() ?? ""
            mixpanel.people.set(property: "user_email_hash", to: hash)
        }

        mixpanel.flush()
    }

    // MARK: - Private: Entitlements

    private func syncEntitlementsAfterLogin(uid: String) {
        guard Purchases.isConfigured else {
            log("ID:VENDOR", "RevenueCat not configured — skipping entitlement sync")
            return
        }
        Purchases.shared.logIn(uid) { info, _, error in
            if let error = error {
                UserIdentityManager.log("ID:VENDOR", "Entitlement sync error: \(error.localizedDescription)")
                return
            }
            let hasActive = info?.entitlements.active.isEmpty == false
            if hasActive {
                UserIdentityManager.log("ID:VENDOR", "Active entitlements found")
                NotificationCenter.default.post(name: .subscriptionStatusUpdated, object: nil)
            } else {
                UserIdentityManager.log("ID:VENDOR", "No active entitlements — restoring")
                Purchases.shared.restorePurchases { restoredInfo, error in
                    let restored = restoredInfo?.entitlements.active.isEmpty == false
                    UserIdentityManager.log("ID:VENDOR", "Restore complete: \(restored)")
                    NotificationCenter.default.post(name: .subscriptionStatusUpdated, object: nil)
                }
            }
        }
    }

    // MARK: - Private: Subscription Listener

    private func setupSubscriptionListenerIfNeeded() {
        guard !hasSetUpSubscriptionListener else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSubscriptionStatusUpdate),
            name: .subscriptionStatusUpdated,
            object: nil
        )
        hasSetUpSubscriptionListener = true
        log("ID:VENDOR", "Subscription listener set up")
    }

    @objc private func handleSubscriptionStatusUpdate() {
        subscriptionDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Self.log("ID:VENDOR", "Subscription status changed — updating Mixpanel")
            self?.updateMixpanelSubscriptionProperties()
        }
        subscriptionDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func updateMixpanelSubscriptionProperties() {
        let mixpanel = Mixpanel.mainInstance()
        guard Purchases.isConfigured else {
            let isSubscribed = SharedUserStorage.retrieve(forKey: .isUserSubscribed, as: Bool.self) ?? false
            mixpanel.people.set(property: "is_subscribed", to: isSubscribed)
            mixpanel.flush()
            return
        }
        Purchases.shared.getCustomerInfo { customerInfo, _ in
            let isSubscribed = customerInfo?.entitlements.active.isEmpty == false
            let subscriptionType: String
            let isTrial: Bool

            if let entitlement = customerInfo?.entitlements.active.first?.value {
                let id = entitlement.productIdentifier.lowercased()
                subscriptionType = id.contains("monthly") ? "monthly" : id.contains("yearly") ? "yearly" : "unknown"
                isTrial = entitlement.periodType == .trial
            } else {
                subscriptionType = "none"
                isTrial = false
            }

            DispatchQueue.main.async {
                mixpanel.people.set(property: "is_subscribed", to: isSubscribed)
                mixpanel.people.set(property: "subscription_type", to: subscriptionType)
                mixpanel.people.set(property: "is_trial", to: isTrial)
                mixpanel.people.set(property: "subscription_last_updated", to: Date())
                mixpanel.flush()
                SharedUserStorage.save(value: isSubscribed, forKey: .isUserSubscribed)
                UserIdentityManager.log("ID:VENDOR", "Subscription updated: subscribed=\(isSubscribed) type=\(subscriptionType) trial=\(isTrial)")
            }
        }
    }

    // MARK: - Private: Lifecycle Events

    private func trackLifecycleEvents() {
        let uid = currentUserId
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let hasTrackedInstall = SharedUserStorage.retrieve(forKey: .hasTrackedInstall, as: Bool.self) ?? false
        let hasTrackedReinstall = SharedUserStorage.retrieve(forKey: .hasTrackedReinstall, as: Bool.self) ?? false

        log("ID:LIFECYCLE", "hasTrackedInstall=\(hasTrackedInstall) hasTrackedReinstall=\(hasTrackedReinstall)")

        if !hasTrackedInstall {
            log("ID:LIFECYCLE", "First install — firing install event")
            trackInstall(uid: uid, version: version, build: build)
            SharedUserStorage.save(value: true, forKey: .hasTrackedInstall)
            SharedUserStorage.save(value: false, forKey: .hasTrackedReinstall)
            SharedUserStorage.save(value: Date(), forKey: .firstInstallDate)
            SharedUserStorage.save(value: build, forKey: .lastTrackedBuildNumber)
        } else if !hasTrackedReinstall && wasAppReinstalled() {
            log("ID:LIFECYCLE", "Reinstall detected — firing reinstall event")
            trackReinstall(uid: uid, version: version, build: build)
            SharedUserStorage.save(value: true, forKey: .hasTrackedReinstall)
        } else {
            log("ID:LIFECYCLE", "Returning user — no lifecycle event needed")
        }

        SharedUserStorage.save(value: build, forKey: .lastTrackedBuildNumber)
    }

    private func wasAppReinstalled() -> Bool {
        let lastBuild = SharedUserStorage.retrieve(forKey: .lastTrackedBuildNumber, as: String.self)
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        if lastBuild == nil { return true }
        guard lastBuild != currentBuild else { return false }

        if let firstInstall = SharedUserStorage.retrieve(forKey: .firstInstallDate, as: Date.self) {
            if Date().timeIntervalSince(firstInstall) < 60 { return false }
        }
        return true
    }

    private func trackInstall(uid: String, version: String, build: String) {
        let params: [String: Any] = [
            "user_id": uid,
            "app_version": version,
            "build_number": build,
            "platform": "iOS",
            "device_model": UIDevice.current.model,
            "os_version": UIDevice.current.systemVersion,
            "tracking_method": "local_lifecycle",
            "timestamp": Date().timeIntervalSince1970,
            "is_genuine_first_install": true
        ]
        AnalyticsManager.shared.logEvent("install", parameters: params)
        log("ID:LIFECYCLE", "✅ install event sent uid=\(uid)")

        let mixpanel = Mixpanel.mainInstance()
        if !isAnonymous {
            mixpanel.people.set(property: "first_seen", to: Date())
            mixpanel.people.set(property: "install_method", to: "local_lifecycle")
            mixpanel.people.set(property: "install_app_version", to: version)
        }
        SharedUserStorage.save(value: Date(), forKey: .firstSeenDate)
        SharedUserStorage.save(value: "local_lifecycle", forKey: .installMethod)
        SharedUserStorage.save(value: version, forKey: .installAppVersion)
    }

    private func trackReinstall(uid: String, version: String, build: String) {
        var params: [String: Any] = [
            "user_id": uid,
            "app_version": version,
            "build_number": build,
            "platform": "iOS",
            "device_model": UIDevice.current.model,
            "os_version": UIDevice.current.systemVersion,
            "tracking_method": "local_lifecycle",
            "timestamp": Date().timeIntervalSince1970,
            "is_genuine_first_install": false
        ]
        if let first = SharedUserStorage.retrieve(forKey: .firstInstallDate, as: Date.self) {
            params["days_since_first_install"] = Int(Date().timeIntervalSince(first) / 86400)
        }
        if let last = SharedUserStorage.retrieve(forKey: .lastTrackedBuildNumber, as: String.self) {
            params["previous_build"] = last
        }
        AnalyticsManager.shared.logEvent("reinstall", parameters: params)
        log("ID:LIFECYCLE", "✅ reinstall event sent uid=\(uid)")
    }

    // MARK: - Private: Attribution

    func enrichInstallWithAttribution(_ conversionInfo: [AnyHashable: Any]) {
        log("ID:LIFECYCLE", "AppsFlyer attribution received")
        guard let isFirstLaunchAF = conversionInfo["is_first_launch"] as? Bool else { return }

        let eventName = isFirstLaunchAF ? "install_attribution" : "reinstall_attribution"
        var params: [String: Any] = [
            "user_id": currentUserId,
            "is_first_launch_af": isFirstLaunchAF,
            "tracking_method": "appsflyer_attribution"
        ]
        if let src = conversionInfo["media_source"] as? String { params["media_source"] = src }
        if let cmp = conversionInfo["campaign"] as? String { params["campaign"] = cmp }
        if let ch = conversionInfo["channel"] as? String { params["channel"] = ch }
        if let t = conversionInfo["install_time"] as? String { params["install_time"] = t }
        if let ag = conversionInfo["adgroup"] as? String { params["adgroup"] = ag }
        if let as_ = conversionInfo["adset"] as? String { params["adset"] = as_ }

        AnalyticsManager.shared.logEvent(eventName, parameters: params)

        let localInstall = SharedUserStorage.retrieve(forKey: .hasTrackedInstall, as: Bool.self) ?? false
        let localReinstall = SharedUserStorage.retrieve(forKey: .hasTrackedReinstall, as: Bool.self) ?? false
        if isFirstLaunchAF && localReinstall {
            log("ID:LIFECYCLE", "⚠️ Mismatch: AppsFlyer=first_launch, Local=reinstall")
        } else if !isFirstLaunchAF && !localReinstall && localInstall {
            log("ID:LIFECYCLE", "⚠️ Mismatch: AppsFlyer=returning, Local=first_install")
        }

        let mixpanel = Mixpanel.mainInstance()
        let src = params["media_source"] as? String ?? "organic"
        if !isAnonymous {
            mixpanel.people.set(property: "install_source", to: src)
            if let c = params["campaign"] as? String { mixpanel.people.set(property: "install_campaign", to: c) }
            mixpanel.people.set(property: "is_first_launch_af", to: isFirstLaunchAF)
        }
        SharedUserStorage.save(value: src, forKey: .installSource)
    }

    // MARK: - Private: Invalid Cached User Recovery

    private func handleInvalidCachedUser(completion: @escaping (Bool) -> Void) {
        log("ID:BOOT", "Clearing invalid cached user and creating fresh anonymous user")
        do {
            try Auth.auth().signOut()
            Auth.auth().signInAnonymously { [weak self] result, error in
                if let error = error {
                    Self.log("ID:BOOT", "Failed to create fresh anonymous user: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                guard let user = result?.user else { completion(false); return }
                Self.log("ID:BOOT", "Fresh anonymous user created: uid=\(user.uid)")
                self?.pendingAnonymousUser = user
                self?.finalizeBoot(with: user)
                completion(true)
            }
        } catch {
            log("ID:BOOT", "Sign-out error: \(error.localizedDescription)")
            completion(false)
        }
    }

    // MARK: - Sign Out

    func signOut(getNewAnonymousUser: Bool = false) {
        log("ID:SIGNOUT", "Signing out uid=\(currentUserId)")
        pendingAnonymousUser = nil

        do {
            try Auth.auth().signOut()
            log("ID:SIGNOUT", "✅ Signed out")

            if getNewAnonymousUser {
                Auth.auth().signInAnonymously { [weak self] result, error in
                    if let error = error {
                        Self.log("ID:SIGNOUT", "Anonymous sign-in after logout failed: \(error.localizedDescription)")
                        return
                    }
                    if let user = result?.user {
                        Self.log("ID:SIGNOUT", "New anonymous user after logout: uid=\(user.uid)")
                        self?.pendingAnonymousUser = user
                        self?.finalizeBoot(with: user)
                    }
                }
            }
        } catch {
            log("ID:SIGNOUT", "Sign-out error: \(error.localizedDescription)")
        }
    }

    func forceSignOut() {
        signOut(getNewAnonymousUser: false)
    }

    // MARK: - Debug Helpers

    #if DEBUG
    func debugResetForFreshInstall() {
        log("ID:BOOT", "[DEBUG] Full reset for fresh install testing")

        SharedUserStorage.delete(forKey: .isAuthenticated)
        SharedUserStorage.delete(forKey: .isGuest)
        SharedUserStorage.delete(forKey: .authenticationMethod)
        SharedUserStorage.delete(forKey: .userName)
        SharedUserStorage.delete(forKey: .lastUsedEmail)
        SharedUserStorage.delete(forKey: .isUserSubscribed)
        SharedUserStorage.delete(forKey: .appVersion)
        SharedUserStorage.delete(forKey: .hasTrackedInstall)
        SharedUserStorage.delete(forKey: .hasTrackedReinstall)
        SharedUserStorage.delete(forKey: .lastTrackedBuildNumber)
        SharedUserStorage.delete(forKey: .firstInstallDate)
        SharedUserStorage.delete(forKey: .firstSeenDate)
        SharedUserStorage.delete(forKey: .installMethod)
        SharedUserStorage.delete(forKey: .installSource)

        hasBootstrapped = false

        do {
            try Auth.auth().signOut()
        } catch {
            log("ID:BOOT", "[DEBUG] Sign-out error: \(error.localizedDescription)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.boot()
            Self.log("ID:BOOT", "[DEBUG] Fresh install reset complete")
        }
    }

    func resetForTesting() {
        log("ID:BOOT", "[TESTING] Reset for testing")

        hasSetUpSubscriptionListener = false
        pendingAnonymousUser = nil

        Mixpanel.mainInstance().reset()

        do {
            try Auth.auth().signOut()
        } catch {
            log("ID:BOOT", "[TESTING] Sign-out error: \(error.localizedDescription)")
        }

        boot()
        log("ID:BOOT", "[TESTING] ✅ Reset complete")
    }

    func prepareForUninstallTest() {
        print("📊 [ID:BOOT] ═══════════════════════════════════════════════════")
        print("📊 [ID:BOOT] [UNINSTALL_TEST] Starting full reset")
        print("📊 [ID:BOOT] ═══════════════════════════════════════════════════")

        SharedUserStorage.delete(forKey: .hasTrackedInstall)
        SharedUserStorage.delete(forKey: .hasTrackedReinstall)
        SharedUserStorage.delete(forKey: .lastTrackedBuildNumber)
        SharedUserStorage.delete(forKey: .firstInstallDate)
        SharedUserStorage.delete(forKey: .firstSeenDate)
        SharedUserStorage.delete(forKey: .installMethod)
        SharedUserStorage.delete(forKey: .installSource)
        SharedUserStorage.delete(forKey: .installAppVersion)
        SharedUserStorage.delete(forKey: .isAuthenticated)
        SharedUserStorage.delete(forKey: .isGuest)
        SharedUserStorage.delete(forKey: .authenticationMethod)
        SharedUserStorage.delete(forKey: .userName)
        SharedUserStorage.delete(forKey: .lastUsedEmail)
        SharedUserStorage.delete(forKey: .isUserSubscribed)
        SharedUserStorage.delete(forKey: .appVersion)

        SenseiOnboardingState.shared.resetForCurrentUser()
        SessionHistoryManager.shared.clearHistory()
        SharedUserStorage.delete(forKey: .completedPractices)

        Task { @MainActor in
            ProductJourneyManager.shared.resetJourney(includePreAppPhases: true, skipAnalytics: true)
        }

        OnboardingState.shared.reset()
        SubscriptionState.shared.reset()

        SharedUserStorage.delete(forKey: .cachedJourneyPhase)
        SharedUserStorage.delete(forKey: .loggedPhaseEntries)
        SharedUserStorage.delete(forKey: .loggedSessionMilestones)
        SharedUserStorage.delete(forKey: .loggedFirstSessionStarted)
        SharedUserStorage.delete(forKey: .hasLoggedInitialPhaseEntry)

        hasSetUpSubscriptionListener = false
        hasBootstrapped = false
        isIdentityReady = false
        pendingAnonymousUser = nil

        Mixpanel.mainInstance().reset()

        do {
            try Auth.auth().signOut()
            print("📊 [ID:BOOT] [UNINSTALL_TEST] ✓ Signed out")
        } catch {
            print("📊 [ID:BOOT] [UNINSTALL_TEST] ❌ Sign-out error: \(error.localizedDescription)")
        }

        print("📊 [ID:BOOT] ═══════════════════════════════════════════════════")
        print("📊 [ID:BOOT] [UNINSTALL_TEST] ✅ Ready — delete app now")
        print("📊 [ID:BOOT] ═══════════════════════════════════════════════════")
    }
    #endif
}
