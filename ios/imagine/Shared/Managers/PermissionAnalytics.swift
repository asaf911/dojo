//
//  PermissionAnalytics.swift
//  imagine
//
//  Created by Cursor on 2/5/26.
//
//  Unified permission tracking. Fires a single "permission_result" event
//  for every permission request (ATT, HealthKit, push notifications) so
//  that all permission outcomes can be queried from one Mixpanel event.
//

import Foundation
import Mixpanel

// MARK: - Permission Analytics

struct PermissionAnalytics {
    
    /// Log a permission request result to Mixpanel.
    ///
    /// - Parameters:
    ///   - permission: The permission type ("att", "mindful_minutes", "heart_rate", "push_notifications")
    ///   - result: The outcome ("authorized", "denied", "skipped", "prompted", "restricted", "not_determined", "already_authorized")
    ///   - source: Where in the app the request was triggered ("sign_up", "onboarding", "subscription_complete", "subscription_auto_complete")
    static func log(permission: String, result: String, source: String) {
        AnalyticsManager.shared.logEvent("permission_result", parameters: [
            "permission": permission,
            "result": result,
            "source": source
        ])
        
        // Set People property for user-level segmentation (e.g. "att_permission" = "authorized")
        Mixpanel.mainInstance().people.set(
            property: "\(permission)_permission",
            to: result
        )
        
        #if DEBUG
        print("📊 PERMISSION_ANALYTICS: permission=\(permission) result=\(result) source=\(source)")
        #endif
    }
}
