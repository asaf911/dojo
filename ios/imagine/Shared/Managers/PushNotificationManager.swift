//
//  PushNotificationManager.swift
//  imagine
//

import Foundation
import UserNotifications
import UIKit

class PushNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()

    private var analyticsManager: AnalyticsManager!
    private var oneSignalAppID: String!
    private var application: UIApplication!

    private override init() {
        super.init()
    }

    func configure(
        application: UIApplication,
        oneSignalAppID: String,
        analyticsManager: AnalyticsManager
    ) {
        self.application = application
        self.oneSignalAppID = oneSignalAppID
        self.analyticsManager = analyticsManager
    }

    func setup(withLaunchOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        pushService.initialize(appId: self.oneSignalAppID, launchOptions: launchOptions)
        UNUserNotificationCenter.current().delegate = self
        // We're not requesting permissions automatically here
        // Permissions are requested at an appropriate point during the subscription flow
    }

    /// Request push notification permission from the user.
    /// Uses OneSignal.Notifications.requestPermission() which tracks the request on OneSignal's dashboard.
    /// If permission is granted, automatically opts the user into push notifications.
    /// - Parameter source: Analytics source identifier (e.g., "subscription_complete")
    func requestNotificationPermission(source: String) {
        pushService.requestPermission { accepted in
            logger.eventMessage("Notification permission granted: \(accepted)")
            PermissionAnalytics.log(
                permission: "push_notifications",
                result: accepted ? "authorized" : "denied",
                source: source
            )
            
            // Opt in to push notifications if user granted permission
            if accepted {
                pushService.optInToPush()
                logger.eventMessage("User opted into push notifications")
            }
        }
    }

    // MARK: - Handling Notifications
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        logger.eventMessage("Notification received: \(response.notification.request.content.userInfo)")

        let userInfo = response.notification.request.content.userInfo

        // 1) OneSignal payload
        if let customData = userInfo["custom"] as? [String: Any],
           let additionalData = customData["a"] as? [String: Any],
           let deepLink = additionalData["af_push_link"] as? String,
           let url = URL(string: deepLink) {
            handleDeepLink(url)
        } else {
            logger.eventMessage("No valid af_push_link found in push notification payload.")
        }

        // 2) AppsFlyer push link - the SDK handles this directly for push attribution
        if let urlString = userInfo["af_push_link"] as? String,
           let url = URL(string: urlString) {
            handleDeepLink(url)
        }

        completionHandler()
    }

    private func handleDeepLink(_ url: URL) {
        logger.eventMessage("Handling deep link: \(url.absoluteString)")
        // Let AppsFlyerManager handle attribution
        AppsFlyerManager.shared.handlePushNotification(url)

        // Attempt to retrieve main app
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                logger.eventMessage("AppDelegate found, calling handleDeepLink(...)")
                appDelegate.handleDeepLink(url)
            } else {
                logger.eventMessage("[PushNotificationManager] Could not retrieve AppDelegate. Storing link in UserDefaults for next app launch.")
                // Store link in user defaults so main app can handle on next active
                SharedUserStorage.save(value: url.absoluteString, forKey: .pendingPushNotificationLink)
            }
        }
    }
}
