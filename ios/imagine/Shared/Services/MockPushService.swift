//
//  MockPushService.swift
//  imagine
//
//  Created by Asaf Shamir on 2025-12-25
//

import Foundation
import UIKit

/// Mock implementation of PushNotificationService for Xcode Previews and testing.
/// All methods are no-ops to prevent SDK initialization during previews.
final class MockPushService: PushNotificationService {
    
    func initialize(appId: String, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        // No-op for previews
    }
    
    func login(userId: String) {
        // No-op for previews
    }
    
    func setEmail(_ email: String) {
        // No-op for previews
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        // Simulate permission granted for previews
        DispatchQueue.main.async {
            completion(true)
        }
    }
    
    func optInToPush() {
        // No-op for previews
    }
    
    func setTag(key: String, value: String) {
        // No-op for previews
    }
    
    func removeTag(_ key: String) {
        // No-op for previews
    }
}

