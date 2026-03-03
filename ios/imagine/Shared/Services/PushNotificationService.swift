//
//  PushNotificationService.swift
//  imagine
//
//  Created by Asaf Shamir on 2025-12-25
//

import Foundation
import UIKit

// MARK: - Protocol

/// Protocol defining push notification service capabilities.
/// This abstraction allows easy switching between providers (OneSignal, Firebase, etc.)
/// and enables mock implementations for Xcode Previews and testing.
protocol PushNotificationService {
    /// Initialize the push notification service
    func initialize(appId: String, launchOptions: [UIApplication.LaunchOptionsKey: Any]?)
    
    /// Login user with their unique identifier
    func login(userId: String)
    
    /// Associate an email with the current user
    func setEmail(_ email: String)
    
    /// Request push notification permission from the user
    func requestPermission(completion: @escaping (Bool) -> Void)
    
    /// Opt the user into push notifications
    func optInToPush()
    
    /// Set a tag for user segmentation
    func setTag(key: String, value: String)
    
    /// Remove a tag from the user
    func removeTag(_ key: String)
}

// MARK: - Service Provider

/// Singleton that provides the appropriate push notification service
/// based on the current environment (production vs previews/tests).
final class PushNotificationServiceProvider {
    static let shared = PushNotificationServiceProvider()
    
    private(set) var service: PushNotificationService
    
    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            service = MockPushService()
        } else {
            service = OneSignalPushService()
        }
        #else
        service = OneSignalPushService()
        #endif
    }
}

// MARK: - Convenience Accessor

/// Global convenience accessor for the push notification service.
/// Usage: `pushService.login(uid)` instead of `PushNotificationServiceProvider.shared.service.login(uid)`
var pushService: PushNotificationService {
    PushNotificationServiceProvider.shared.service
}

