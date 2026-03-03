//
//  WatchConnectivityManager.swift
//  Dojo
//

import WatchConnectivity
import Foundation
import Combine

// MARK: - Notification Names
extension Notification.Name {
    static let watchHeartRateMonitoringStarted = Notification.Name("watchHeartRateMonitoringStarted")
    static let watchHeartRateMonitoringStopped = Notification.Name("watchHeartRateMonitoringStopped")
}

/// Manages WatchConnectivity on the watch side for simplified heart rate monitoring.
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var isConnected = false
    
    private let session = WCSession.default
    
    override init() {
        super.init()
        startSession()
    }
    
    private func startSession() {
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
            print("🧠 AI_DEBUG WatchConnectivityManager: session activated")
        }
    }
    
    // MARK: - Send Messages to iPhone
    
    func sendHeartRateUpdate(_ heartRate: Double, sessionId: String? = nil) {
        var message: [String: Any] = [
            "type": "heartRateUpdate",
            "heartRate": heartRate,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let id = sessionId {
            message["sessionId"] = id
        }
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("🧠 AI_DEBUG WatchConnectivityManager: sendMessage error: \(error.localizedDescription)")
            }
        } else {
            // Use background transfer when iPhone not reachable
            session.transferUserInfo(message)
            print("🧠 AI_DEBUG WatchConnectivityManager: transferUserInfo bpm=\(Int(heartRate))")
        }
    }
    
    func notifyWatchAppDidBecomeActive() {
        let message = [
            "type": "watchAppDidBecomeActive",
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("WatchConnectivityManager: ❌ Failed to notify app became active: \(error.localizedDescription)")
            }
        } else {
            // Use background transfer when iPhone not reachable
            session.transferUserInfo(message)
        }
        
    }
    
    func notifyWatchAppDidEnterBackground() {
        let message = [
            "type": "watchAppDidEnterBackground", 
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("WatchConnectivityManager: ❌ Failed to notify app entered background: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = activationState == .activated
            print("WatchConnectivityManager: Session activated - connected: \(self.isConnected)")
            
            if let error = error {
                print("WatchConnectivityManager: ❌ Activation error: \(error.localizedDescription)")
            }
        }
    }
    

    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.handleMessage(message)
        }
    }

    // Handle messages that expect a reply to avoid WCSession delivery failures
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        DispatchQueue.main.async {
            self.handleMessage(message)
            replyHandler(["status": "ok"]) // acknowledge to clear delivery errors
        }
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        DispatchQueue.main.async {
            self.handleMessage(userInfo)
        }
    }
    
    // MARK: - Message Handling
    
    private func handleMessage(_ message: [String : Any]) {
        let messageType = message["type"] as? String ?? "unknown"
        let sessionId = message["sessionId"] as? String ?? "none"
        let hrEnabled = WatchFeatureFlags.shared.isHRFeatureEnabled
        print("🧠 AI_DEBUG WatchConnectivityManager: received message type=\(messageType) sessionId=\(sessionId) hrEnabled=\(hrEnabled) reachable=\(session.isReachable) payload=\(message)")

        guard let type = message["type"] as? String else {
            print("WatchConnectivityManager: ⚠️ Message missing type field")
            return
        }
        
        switch type {
        case "startLiveMode":
            // Gate by feature flag
            guard WatchFeatureFlags.shared.isHRFeatureEnabled else {
                print("🧠 AI_DEBUG WatchConnectivityManager: HR feature disabled - ignoring startLiveMode command")
                return
            }
            print("WatchConnectivityManager: 🟢 Received start live mode command from iPhone")
            let sessionId = message["sessionId"] as? String ?? UUID().uuidString
            WatchSensorService.shared.start(sessionId: sessionId)
            WatchSensorService.shared.resetInactivityTimer()  // Reset watchdog
            NotificationCenter.default.post(name: .watchHeartRateMonitoringStarted, object: nil)
        case "stopLiveMode":
            print("WatchConnectivityManager: 🔴 Received stop live mode command from iPhone")
            let sessionId = message["sessionId"] as? String ?? ""
            WatchSensorService.shared.stop(sessionId: sessionId)
            NotificationCenter.default.post(name: .watchHeartRateMonitoringStopped, object: nil)
        case "meditationCompleted", "meditationDismissed":
            print("🧠 AI_DEBUG WatchConnectivityManager: received \(messageType) → stopping HR")
            let sessionId = message["sessionId"] as? String ?? ""
            WatchSensorService.shared.stop(sessionId: sessionId)
            NotificationCenter.default.post(name: .watchHeartRateMonitoringStopped, object: nil)
        default:
            print("WatchConnectivityManager: ❓ Unknown message type: \(type)")
        }
    }

    // Handle application context pushes for idle wake hints
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("🧠 AI_DEBUG WatchConnectivityManager: received applicationContext: \(applicationContext) hrEnabledBefore=\(WatchFeatureFlags.shared.isHRFeatureEnabled)")
        // Persist hr feature flag if provided
        if let hrEnabled = applicationContext["hrFeatureEnabled"] as? Bool {
            WatchFeatureFlags.shared.setHRFeatureEnabled(hrEnabled)
            print("🧠 AI_DEBUG WatchConnectivityManager: hrFeatureEnabled=\(hrEnabled)")
        }
        if let last = applicationContext["lastCommandType"] as? String, last == "startLiveMode" {
            // Gate by feature flag before nudging start
            guard WatchFeatureFlags.shared.isHRFeatureEnabled else {
                print("🧠 AI_DEBUG WatchConnectivityManager: HR feature disabled - ignoring context nudge startLiveMode")
                return
            }
            
            // Start HR - WatchSensorService handles duplicate starts gracefully
            // Note: Removed staleness check as it prevented legitimate wake-ups
            // The iPhone clears the context when session ends, so stale commands won't persist
            let sessionId = applicationContext["sessionId"] as? String ?? UUID().uuidString
            print("🧠 AI_DEBUG WatchConnectivityManager: Starting HR from applicationContext")
            WatchSensorService.shared.start(sessionId: sessionId)
            WatchSensorService.shared.resetInactivityTimer()
        } else if let last = applicationContext["lastCommandType"] as? String, last == "stopLiveMode" {
            // Handle stop command from context (in case sendMessage didn't deliver)
            print("🧠 AI_DEBUG WatchConnectivityManager: Stopping HR from applicationContext")
            let sessionId = applicationContext["sessionId"] as? String ?? ""
            WatchSensorService.shared.stop(sessionId: sessionId)
        }
    }
}


