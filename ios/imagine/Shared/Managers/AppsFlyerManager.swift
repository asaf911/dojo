//
//  AppsFlyerManager.swift
//  imagine
//
//  Centralized AppsFlyer SDK management.
//  Handles attribution, ATT consent, SKAN, deep linking, and event tracking.
//
//  ═══════════════════════════════════════════════════════════════════
//  AppsFlyer Event Tracking Architecture
//  ═══════════════════════════════════════════════════════════════════
//
//  Revenue is tracked server-side by RevenueCat (rc_ events with price/currency).
//  Client-side events are non-revenue funnel signals only.
//
//  ┌─────────────────────────┬──────────────────────┬──────────────────────────────────────┐
//  │ AppsFlyer Event         │ Internal Trigger      │ When It Fires                        │
//  ├─────────────────────────┼──────────────────────┼──────────────────────────────────────┤
//  │ af_complete_registration│ sign_up / user_signup │ User creates account                 │
//  │ onboarding_started      │ (passthrough)         │ User begins onboarding               │
//  │ af_tutorial_completion  │ onboarding_completed  │ User finishes onboarding              │
//  │ af_start_trial          │ trial_started         │ User starts free trial (no revenue)   │
//  │ af_subscribe            │ subscription_success  │ User becomes paying subscriber        │
//  │                         │                       │  • direct purchase → purchase callback │
//  │                         │                       │  • trial converted → PurchasesDelegate │
//  │ session_start           │ (passthrough)         │ User starts meditation                │
//  │ session_complete        │ (passthrough)         │ User completes meditation             │
//  │ af_level_achieved       │ logLevelAchieved()    │ Journey phase or session milestone    │
//  └─────────────────────────┴──────────────────────┴──────────────────────────────────────┘
//
//  Subscription rules:
//   • af_start_trial fires ONLY when trial begins — no af_subscribe alongside it.
//   • af_subscribe fires ONLY when user is in paid state (periodType == .normal):
//       1. Direct purchase: purchase callback, periodType is .normal immediately.
//       2. Trial converted: PurchasesDelegate update, periodType transitions trial→normal.
//   • Deduplication is handled via SharedUserStorage.lastKnownPeriodType.
//
//  ═══════════════════════════════════════════════════════════════════

import Foundation
import AppsFlyerLib
import AppTrackingTransparency
import AdSupport
import UIKit

/// Singleton manager for all AppsFlyer SDK interactions.
final class AppsFlyerManager: NSObject {
    
    static let shared = AppsFlyerManager()
    
    // MARK: - Configuration
    
    private let devKey = "eLUB6YrwUiT9stNvVy5BRh"
    private let appleAppID = "6503365052"
    
    // MARK: - State
    
    private var isConfigured = false
    private var customerUserID: String?
    private var hasStartedThisSession = false
    
    @Published private(set) var attStatus: ATTStatus = .notDetermined
    
    var onATTFlowComplete: (() -> Void)?
    
    // MARK: - Event Allow-List
    //
    // Only marketing-relevant events pass through to AppsFlyer.
    // All other events logged via AnalyticsManager are silently dropped here.
    // Revenue events (af_purchase) are handled server-side by RevenueCat.
    
    private let allowedEvents: Set<String> = [
        "af_complete_registration",
        "af_tutorial_completion",
        "af_subscribe",
        "af_start_trial",
        "af_level_achieved",
        "session_start",
        "session_complete",
        "onboarding_started"
    ]
    
    // MARK: - ATT Status Enum
    
    enum ATTStatus {
        case notDetermined
        case authorized
        case denied
        case restricted
        
        @available(iOS 14, *)
        static func from(_ status: ATTrackingManager.AuthorizationStatus) -> ATTStatus {
            switch status {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            @unknown default: return .denied
            }
        }
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - SDK Lifecycle
    
    /// Configure SDK - call in didFinishLaunchingWithOptions
    /// Starts the SDK immediately to queue install event before ATT timer expires
    func configure() {
        guard !isConfigured else {
            print("📊 [APPSFLYER] Already configured, skipping")
            return
        }
        
        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.appsFlyerDevKey = devKey
        appsFlyer.appleAppID = appleAppID
        appsFlyer.delegate = self
        
        #if DEBUG
        appsFlyer.isDebug = true
        // Note: Keep SKAN enabled even in debug for testing
        // Only disable if causing issues: appsFlyer.disableSKAdNetwork = true
        #endif
        
        // Wait for ATT before sending data (iOS 14+)
        appsFlyer.waitForATTUserAuthorization(timeoutInterval: 60)
        
        isConfigured = true
        print("📊 [APPSFLYER] SDK configured (devKey: \(String(devKey.prefix(8)))...)")
        
        // START IMMEDIATELY to queue the install event
        // The waitForATTUserAuthorization ensures data waits for ATT resolution
        // customerUserID will be attached when set later
        appsFlyer.start()
        hasStartedThisSession = true
        print("📊 [APPSFLYER] ✅ SDK started immediately (install event queued, waiting for ATT)")
    }
    
    /// Set customer user ID - call when Firebase UID is available
    /// This MUST be called before start() for proper attribution
    func setCustomerUserID(_ uid: String) {
        guard !uid.isEmpty else {
            print("📊 [APPSFLYER] ⚠️ Attempted to set empty customerUserID")
            return
        }
        
        customerUserID = uid
        AppsFlyerLib.shared().customerUserID = uid
        print("📊 [APPSFLYER] CustomerUserID set: \(uid)")
        
        // Start SDK immediately after setting customerUserID
        // The waitForATTUserAuthorization will handle ATT waiting internally
        // This ensures the install event is queued BEFORE the ATT timeout expires
        startSDKIfReady()
    }
    
    /// Check if we have a customer user ID set
    var hasCustomerUserID: Bool {
        return customerUserID != nil && !customerUserID!.isEmpty
    }
    
    // MARK: - App Foreground Handling
    
    /// Call on every applicationDidBecomeActive
    /// This ensures proper session tracking for returning users
    func handleAppForeground() {
        guard isConfigured else {
            print("📊 [APPSFLYER] ⚠️ handleAppForeground called but SDK not configured")
            return
        }
        
        print("📊 [APPSFLYER] handleAppForeground called")
        
        // Update ATT status
        updateATTStatus()
        
        // Always try to start - the SDK's waitForATTUserAuthorization handles ATT waiting internally
        // This ensures session pings for returning users work correctly
        startSDKIfReady()
    }
    
    // MARK: - ATT Flow
    
    /// Update the current ATT status
    private func updateATTStatus() {
        if #available(iOS 14, *) {
            attStatus = ATTStatus.from(ATTrackingManager.trackingAuthorizationStatus)
        } else {
            attStatus = .authorized // Pre-iOS 14, tracking is allowed
        }
    }
    
    /// Check if ATT prompt is needed (status is notDetermined)
    var needsATTPrompt: Bool {
        if #available(iOS 14, *) {
            return ATTrackingManager.trackingAuthorizationStatus == .notDetermined
        }
        return false
    }
    
    /// Request ATT authorization - call after pre-permission screen
    /// This triggers the native iOS ATT dialog
    func requestATTAuthorization(completion: ((ATTStatus) -> Void)? = nil) {
        if #available(iOS 14, *) {
            print("📊 [APPSFLYER] Requesting ATT authorization...")
            
            ATTrackingManager.requestTrackingAuthorization { [weak self] status in
                let attStatus = ATTStatus.from(status)
                
                DispatchQueue.main.async {
                    self?.attStatus = attStatus
                    
                    let statusName: String
                    switch status {
                    case .notDetermined: statusName = "notDetermined"
                    case .restricted: statusName = "restricted"
                    case .denied: statusName = "denied"
                    case .authorized: statusName = "authorized"
                    @unknown default: statusName = "unknown"
                    }
                    
                    print("📊 [APPSFLYER] ATT authorization result: \(statusName)")
                    
                    // Track ATT permission result via unified event
                    PermissionAnalytics.log(permission: "att", result: statusName, source: "sign_up")
                    
                    if status == .authorized {
                        print("📊 [APPSFLYER] IDFA access granted - full attribution available")
                    } else {
                        print("📊 [APPSFLYER] IDFA access denied/restricted - attribution may be limited")
                    }
                    
                    // Start SDK after ATT resolves
                    self?.startSDKIfReady()
                    
                    // Notify completion
                    completion?(attStatus)
                    self?.onATTFlowComplete?()
                }
            }
        } else {
            // iOS 13 - no ATT needed
            print("📊 [APPSFLYER] iOS 13 - no ATT needed")
            startSDKIfReady()
            completion?(.authorized)
            onATTFlowComplete?()
        }
    }
    
    /// Trigger the ATT flow - requests native ATT authorization if needed
    /// Call this when identity is ready and user has seen initial UI
    func triggerATTFlowIfNeeded() {
        guard needsATTPrompt else {
            print("📊 [APPSFLYER] ATT already resolved, no prompt needed")
            // SDK should already be started via setCustomerUserID(), but ensure it is
            startSDKIfReady()
            return
        }
        
        print("📊 [APPSFLYER] ATT prompt needed - requesting authorization")
        // Note: SDK start() is already called via setCustomerUserID()
        // The waitForATTUserAuthorization ensures data waits for ATT
        requestATTAuthorization()
    }
    
    // MARK: - SDK Start
    
    /// Internal method to start SDK if all conditions are met
    private func startSDKIfReady() {
        guard isConfigured else {
            print("📊 [APPSFLYER] Cannot start - SDK not configured")
            return
        }
        
        guard hasCustomerUserID else {
            print("📊 [APPSFLYER] Cannot start - no customerUserID set")
            return
        }
        
        // Always call start() for session tracking, even if already started this session
        // AppsFlyer SDK handles deduplication internally
        AppsFlyerLib.shared().start()
        
        if !hasStartedThisSession {
            hasStartedThisSession = true
            print("📊 [APPSFLYER] ✅ SDK started (first time this session)")
        } else {
            print("📊 [APPSFLYER] SDK start() called (session ping)")
        }
    }
    
    /// Force start SDK - use only when you're certain conditions are met
    func forceStart() {
        guard isConfigured else {
            print("📊 [APPSFLYER] Cannot force start - SDK not configured")
            return
        }
        
        AppsFlyerLib.shared().start()
        hasStartedThisSession = true
        print("📊 [APPSFLYER] ✅ SDK force started")
    }
    
    // MARK: - Event Tracking
    
    /// Log event to AppsFlyer if it's in the allow-list
    /// Handles event name mapping automatically
    func logEvent(_ name: String, parameters: [String: Any]?) {
        let afEventName = mapToAppsFlyerEvent(name)
        
        guard allowedEvents.contains(afEventName) || allowedEvents.contains(name) else {
            // Not a marketing event, skip silently
            return
        }
        
        let params = parameters ?? [:]
        
        AppsFlyerLib.shared().logEvent(afEventName, withValues: params)
        print("📊 [APPSFLYER] Event logged: \(afEventName)")
    }
    
    /// Log level achieved event for journey phase completion.
    /// Maps to AppsFlyer's standard af_level_achieved event.
    ///
    /// - Parameters:
    ///   - level: The numeric level/order of the phase (for ad network compatibility)
    ///   - contentId: The stable phase identifier (for historical analysis)
    ///   - description: Optional human-readable name for the phase
    func logLevelAchieved(level: Int, contentId: String, description: String? = nil) {
        var params: [String: Any] = [
            "af_level": level,
            "af_content_id": contentId
        ]
        
        if let desc = description {
            params["af_description"] = desc
        }
        
        AppsFlyerLib.shared().logEvent("af_level_achieved", withValues: params)
        print("📊 [APPSFLYER] Level achieved: level=\(level), contentId=\(contentId)")
    }
    
    // MARK: - Deep Linking
    
    /// Handle URL scheme deep links
    func handleOpenURL(_ url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        AppsFlyerLib.shared().handleOpen(url, options: options)
        print("📊 [APPSFLYER] Handled open URL: \(url.absoluteString)")
    }
    
    /// Handle universal links
    func handleUniversalLink(_ userActivity: NSUserActivity) {
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
        if let url = userActivity.webpageURL {
            print("📊 [APPSFLYER] Handled universal link: \(url.absoluteString)")
        }
    }
    
    /// Handle push notification deep links
    func handlePushNotification(_ url: URL) {
        AppsFlyerLib.shared().performOnAppAttribution(with: url)
        print("📊 [APPSFLYER] Handled push notification URL: \(url.absoluteString)")
    }
    
    // MARK: - Event Name Mapping

    /// Maps internal analytics event names to AppsFlyer standard event names.
    /// Events that don't match a mapping pass through unchanged and are checked
    /// against the allow-list in ``logEvent(_:parameters:)``.
    private func mapToAppsFlyerEvent(_ name: String) -> String {
        switch name {
        case "sign_up", "user_signup":       return "af_complete_registration"
        case "onboarding_complete",
             "onboarding_completed":         return "af_tutorial_completion"
        case "subscription_success":         return "af_subscribe"
        case "trial_started":                return "af_start_trial"
        case "journey_phase_completed":      return "af_level_achieved"
        default:                             return name
        }
    }
    
    // MARK: - Session Reset (for testing)
    
    #if DEBUG
    func resetForTesting() {
        hasStartedThisSession = false
        customerUserID = nil
        print("📊 [APPSFLYER] Reset for testing")
    }
    #endif
}

// MARK: - AppsFlyerLibDelegate

extension AppsFlyerManager: AppsFlyerLibDelegate {
    
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        print("📊 [APPSFLYER] ========== CONVERSION DATA RECEIVED ==========")
        print("📊 [APPSFLYER] Raw data: \(conversionInfo)")
        
        let isFirstLaunch = conversionInfo["is_first_launch"] as? Bool ?? false
        let mediaSource = conversionInfo["media_source"] as? String ?? "organic"
        let campaign = conversionInfo["campaign"] as? String
        
        print("📊 [APPSFLYER] is_first_launch: \(isFirstLaunch)")
        print("📊 [APPSFLYER] media_source: \(mediaSource)")
        if let campaign = campaign {
            print("📊 [APPSFLYER] campaign: \(campaign)")
        }
        
        // Post notification for other parts of the app to consume
        NotificationCenter.default.post(
            name: .appsFlyerConversionDataReceived,
            object: nil,
            userInfo: [
                "isFirstLaunch": isFirstLaunch,
                "mediaSource": mediaSource,
                "campaign": campaign as Any,
                "rawData": conversionInfo
            ]
        )
        
        print("📊 [APPSFLYER] ✅ Conversion data processed")
        print("📊 [APPSFLYER] ================================================")
    }
    
    func onConversionDataFail(_ error: Error) {
        let nsError = error as NSError
        
        // Empty data is expected for organic installs (Xcode, App Store direct, no attribution link)
        // NSCocoaErrorDomain code 3840 = JSON parsing error, often due to empty response
        if nsError.code == 3840,
           let debugDesc = nsError.userInfo["NSDebugDescription"] as? String,
           debugDesc.contains("empty data") {
            print("📊 [APPSFLYER] ℹ️ No attribution data (organic install)")
            return
        }
        
        // Log actual errors
        print("📊 [APPSFLYER] ❌ Conversion data FAILED")
        print("📊 [APPSFLYER] Error: \(error.localizedDescription)")
        print("📊 [APPSFLYER] Error domain: \(nsError.domain), code: \(nsError.code)")
    }
    
    func onAppOpenAttribution(_ attributionData: [AnyHashable: Any]) {
        print("📊 [APPSFLYER] ========== APP OPEN ATTRIBUTION ==========")
        print("📊 [APPSFLYER] Attribution data: \(attributionData)")
        
        // Handle deferred deep link
        let deepLinkValue = attributionData["deep_link_value"] as? String
        let isRetargeting = (attributionData["is_retargeting"] as? String) == "true"
        
        if isRetargeting {
            print("📊 [APPSFLYER] Retargeting campaign detected")
        }
        
        // Post notification for deep link handling
        NotificationCenter.default.post(
            name: .appsFlyerDeepLink,
            object: nil,
            userInfo: [
                "deepLinkValue": deepLinkValue as Any,
                "isRetargeting": isRetargeting,
                "data": attributionData
            ]
        )
        
        print("📊 [APPSFLYER] ================================================")
    }
    
    func onAppOpenAttributionFailure(_ error: Error) {
        print("📊 [APPSFLYER] App open attribution failed: \(error.localizedDescription)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let appsFlyerConversionDataReceived = Notification.Name("appsFlyerConversionDataReceived")
    static let appsFlyerDeepLink = Notification.Name("appsFlyerDeepLink")
}

