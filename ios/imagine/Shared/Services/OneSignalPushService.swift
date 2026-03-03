//
//  OneSignalPushService.swift
//  imagine
//
//  Created by Asaf Shamir on 2025-12-25
//

import Foundation
import UIKit
import OneSignalFramework

/// OneSignal implementation of the PushNotificationService protocol.
/// This is the only file in the app that should import OneSignalFramework.
final class OneSignalPushService: PushNotificationService {
    
    func initialize(appId: String, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        OneSignal.initialize(appId, withLaunchOptions: launchOptions)
    }
    
    func login(userId: String) {
        OneSignal.login(userId)
    }
    
    func setEmail(_ email: String) {
        OneSignal.User.addEmail(email)
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        OneSignal.Notifications.requestPermission({ accepted in
            completion(accepted)
        }, fallbackToSettings: true)
    }
    
    func optInToPush() {
        OneSignal.User.pushSubscription.optIn()
    }
    
    func setTag(key: String, value: String) {
        OneSignal.User.addTag(key: key, value: value)
    }
    
    func removeTag(_ key: String) {
        OneSignal.User.removeTag(key)
    }
}

