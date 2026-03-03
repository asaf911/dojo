//
//  AppDelegate.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-27
//

import UIKit
import SwiftUI
import FirebaseCore
import RevenueCat
import Mixpanel
import GoogleSignIn
import AuthenticationServices
import FirebaseAuth
import FirebaseAnalytics
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, ASAuthorizationControllerPresentationContextProviding {

    var window: UIWindow?
    var navigationCoordinator: NavigationCoordinator?
    var pendingPushNotificationURL: URL?

    // references to both audio and timer managers
    var audioPlayerManager: AudioPlayerManager?
    var timerManager: MeditationSessionTimer?

    private let connectivityManager = PhoneConnectivityManager.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Migrate legacy storage key for existing beta users (one-time, safe to remove after a few releases)
        migrateHRStorageKeyIfNeeded()
        
        // Pre-warm haptic generators to avoid Core Haptics initialization timeouts
        let _ = HapticManager.shared
        
        // Initialize Firebase
        FirebaseApp.configure()
        
        #if DEBUG
        // Disable Firebase Analytics in DEBUG to prevent blocking StoreKit transaction spam
        // (100+ "Purchase is a duplicate" messages that slow down Xcode debugging)
        Analytics.setAnalyticsCollectionEnabled(false)
        #endif

        // AppsFlyer - Configure via centralized manager
        // SDK will NOT start here - it starts after ATT and customerUserID are set
        AppsFlyerManager.shared.configure()

        // Mixpanel - Initialize with proper token and disable automatic events for control
        Mixpanel.initialize(token: Config.mixpanelToken, trackAutomaticEvents: false)
        
        // Verify Mixpanel initialization
        let mixpanelInstance = Mixpanel.mainInstance()
        let token = mixpanelInstance.apiToken
        if !token.isEmpty {
            logger.debugMessage("Mixpanel initialized successfully with token: \(String(token.prefix(8)))...")
            
            // Set super properties that should be included with all events
            if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                mixpanelInstance.registerSuperProperties(["app_version": appVersion])
            }
            if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                mixpanelInstance.registerSuperProperties(["build_number": build])
            }
            
        } else {
            logger.errorMessage("Mixpanel initialization failed - token is empty!")
        }
        
        // RevenueCat
        #if DEBUG
        // Reduce RevenueCat logging verbosity in DEBUG to speed up Xcode console
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: Config.applePurchasesApiKey)
        
        // Initialize user identity system AFTER RevenueCat is configured
        print("📊 TRACKING: [INIT] Starting bootstrap after all vendors are configured")
        UserIdentityManager.shared.bootstrapIfNeeded()

        // OneSignal + Firebase Messaging
        PushNotificationManager.shared.configure(
            application: application,
            oneSignalAppID: Config.oneSignalAppID,
            analyticsManager: AnalyticsManager.shared
        )
        PushNotificationManager.shared.setup(withLaunchOptions: launchOptions)

        // Load audio files at launch
        // In DEBUG, don't force fetch to avoid blocking network calls during startup
        #if DEBUG
        let forceFetch = false
        #else
        let forceFetch = true
        #endif
        AppFunctions.loadAudioFiles(forceFetch: forceFetch) { audioFiles in
            DispatchQueue.main.async {
                PracticeManager.shared.loadAudioFiles(from: audioFiles)
                NotificationCenter.default.post(name: .didUpdateAudioFiles, object: nil)
            }
        }

        // Initialize PhoneConnectivityManager early to establish watch connection
        // In DEBUG, defer to avoid blocking on WCSession network calls
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let _ = PhoneConnectivityManager.shared
        }
        #else
        let _ = PhoneConnectivityManager.shared
        #endif

        logger.debugMessage("App finished launching.")
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        print("📊 TRACKING: [LIFECYCLE] App became active")

        // CRITICAL: Handle AppsFlyer session tracking on every foreground
        // This ensures sessions are tracked for returning users who already completed ATT
        AppsFlyerManager.shared.handleAppForeground()
        
        // Initialize Path Engagement Manager for OneSignal journey automation
        let _ = PathEngagementManager.shared

        // If we have an in-memory pending URL, handle it
        if let pendingURL = self.pendingPushNotificationURL {
            logger.eventMessage("Handling pendingPushNotificationURL in AppDelegate: \(pendingURL.absoluteString)")
            self.handleDeepLink(pendingURL)
            self.pendingPushNotificationURL = nil
        }

        // Also check if there's a link in UserDefaults
        if let storedLink = SharedUserStorage.retrieve(forKey: .pendingPushNotificationLink, as: String.self),
           let storedURL = URL(string: storedLink) {
            logger.eventMessage("Found pendingPushNotificationLink in UserDefaults (AppDelegate): \(storedLink)")
            self.handleDeepLink(storedURL)
            SharedUserStorage.delete(forKey: .pendingPushNotificationLink)
        }

        // Audio session reactivation is handled by AppAudioLifecycleController.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        print("AppDelegate: App entered background")
        // Audio lifecycle is handled by AppAudioLifecycleController.
        // Watch connectivity is handled by PhoneConnectivityManager.
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("AppDelegate: App will enter foreground")
        // Audio lifecycle is handled by AppAudioLifecycleController.
        // Watch connectivity is handled by PhoneConnectivityManager.
    }

    // MARK: - Deep Link Handling

    func handleDeepLink(_ url: URL) {
        logger.debugMessage("AppDelegate handling deep link: \(url.absoluteString)")
        
        // Let AppsFlyerManager handle deep link attribution
        AppsFlyerManager.shared.handlePushNotification(url)

        // If our SwiftUI coordinator is ready, navigate
        if let nav = self.navigationCoordinator {
            logger.debugMessage("navigationCoordinator is ready, calling handleDeepLinkFromPushNotification.")
            DeepLinkHandler.handleDeepLinkFromPushNotification(url, navigationCoordinator: nav)
        } else {
            logger.debugMessage("navigationCoordinator is nil, storing in memory for next time: \(url.absoluteString)")
            self.pendingPushNotificationURL = url
        }
    }

    // MARK: - Custom URL & Universal Links

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        logger.eventMessage("App opened via URL: \(url.absoluteString)")
        GIDSignIn.sharedInstance.handle(url)
        
        // Let AppsFlyerManager handle URL attribution
        AppsFlyerManager.shared.handleOpenURL(url, options: options)

        if let nav = self.navigationCoordinator {
            DeepLinkHandler.handleIncomingURL(url, source: "universalLink", navigationCoordinator: nav)
        } else {
            logger.debugMessage("navigationCoordinator is nil in open url, storing pending URL: \(url.absoluteString)")
            self.pendingPushNotificationURL = url
        }
        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        logger.eventMessage("application(_:continue:restorationHandler:) called")

        if let url = userActivity.webpageURL {
            logger.eventMessage("App launched via universal link: \(url.absoluteString)")
            
            // Let AppsFlyerManager handle universal link attribution
            AppsFlyerManager.shared.handleUniversalLink(userActivity)

            if let nav = self.navigationCoordinator {
                DeepLinkHandler.handleIncomingURL(
                    url,
                    source: "universalLink",
                    navigationCoordinator: nav
                )
            } else {
                logger.debugMessage("navigationCoordinator is nil in continue userActivity, storing pending URL: \(url.absoluteString)")
                self.pendingPushNotificationURL = url
            }
            return true
        } else {
            logger.eventMessage("App launched via other user activity: \(userActivity.activityType)")
            return false
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        // Apple Sign-in logic ...
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        logger.eventMessage("Authorization failed: \(error.localizedDescription)")
    }

    // MARK: - ASPresentationAnchor
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        return UIWindow()
    }
    
    // MARK: - Storage Migration
    
    /// One-time migration: copies the legacy "hrWatchBetaEnabled" UserDefaults value
    /// to the new "hrMonitoringEnabled" key so existing beta users keep HR enabled.
    private func migrateHRStorageKeyIfNeeded() {
        let defaults = UserDefaults.standard
        let oldKey = "hrWatchBetaEnabled"
        let newKey = UserStorageKey.hrMonitoringEnabled.rawValue
        
        // Only migrate if the old key has a stored value and the new key has not been set yet
        if defaults.object(forKey: oldKey) != nil && defaults.object(forKey: newKey) == nil {
            let oldValue = defaults.bool(forKey: oldKey)
            defaults.set(oldValue, forKey: newKey)
            defaults.removeObject(forKey: oldKey)
            
            #if DEBUG
            print("🔄 Migrated hrWatchBetaEnabled(\(oldValue)) -> hrMonitoringEnabled")
            #endif
        }
    }
}
