import WatchConnectivity
import Foundation
import Combine
import UIKit

/// Manages WatchConnectivity for heart rate communication with Apple Watch.
/// Simplified to fire-and-forget command pattern - HeartRateService orchestrates providers.
class PhoneConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneConnectivityManager()
    
    // MARK: - Published State
    
    @Published var isWatchConnected: Bool = false
    @Published var lastHeartRate: Double?
    @Published var lastUpdateTime: Date?
    @Published var isLiveMode: Bool = false
    
    // MARK: - Private State
    
    private let session = WCSession.default
    private var connectivityCheckTimer: Timer?
    private var activeSessionId: String?
    private var activeSessionContext: String?
    private var hasLoggedPermissionWarning = false  // Prevent duplicate permission warnings
    private var hasReceivedWatchHR = false  // Track if Watch is actually sending HR
    private var hasLoggedStreamingAck = false  // Prevent duplicate streaming ack logs
    
    // MARK: - Status for UI
    
    var heartRateStatus: HeartRateStatus {
        if isLiveMode {
            return .live
        }
        if WatchPairingManager.shared.isWatchPaired {
            return isWatchConnected ? .notLive : .notConnected
        }
        return .notPaired
    }
    
    enum HeartRateStatus {
        case notPaired
        case notConnected
        case notLive
        case live
    }
    
    // MARK: - Feature Flag
    
    private var isHRFeatureEnabled: Bool {
        SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false)
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupWatchConnectivity()
        startConnectivityMonitoring()
    }
    
    // MARK: - Public API
    
    /// Notify Watch that a practice is starting - sends start command.
    func notifyPracticePreloaded(sessionId: String? = nil, context: String? = nil) {
        guard isHRFeatureEnabled else {
            HRDebugLogger.warn(.watch, "Feature disabled - ignoring practice preload")
            return
        }
        
        if let id = sessionId {
            activeSessionId = id
        }
        if let ctx = context {
            activeSessionContext = ctx
        }
        
        HRDebugLogger.log(.watch, "Practice preloaded - starting live mode")
        startLiveMode()
    }
    
    /// Notify Watch that a practice has ended - sends stop command.
    func notifyPracticeEnded(sessionId: String? = nil) {
        HRDebugLogger.log(.watch, "Practice ended - stopping live mode")
        stopLiveMode()
        
        activeSessionId = nil
        activeSessionContext = nil
    }
    
    /// Force re-send start command to nudge Watch after idle.
    func forceStartHeartRateNudge() {
        guard isHRFeatureEnabled else { return }
        
        HRDebugLogger.log(.watch, "Force nudge - resending start command")
        sendCommand(type: "startLiveMode")
    }
    
    /// Update HR feature flag and sync to Watch.
    func updateHRFeatureEnabled(_ enabled: Bool) {
        SharedUserStorage.save(value: enabled, forKey: .hrMonitoringEnabled)
        pushHRFeatureFlagToWatch()
        
        if !enabled {
            stopLiveMode()
        }
    }
    
    // MARK: - Private Methods
    
    private func startLiveMode() {
        // Reset session flags for new live mode
        hasLoggedPermissionWarning = false
        hasReceivedWatchHR = false
        hasLoggedStreamingAck = false
        
        guard !isLiveMode else {
            HRDebugLogger.log(.watch, "Already in live mode")
            return
        }
        
        DispatchQueue.main.async {
            self.isLiveMode = true
        }
        
        if WatchPairingManager.shared.isWatchPaired {
            sendCommand(type: "startLiveMode")
        }
    }
    
    private func stopLiveMode() {
        guard isLiveMode else { return }
        
        DispatchQueue.main.async {
            self.isLiveMode = false
        }
        
        if WatchPairingManager.shared.isWatchPaired {
            sendCommand(type: "stopLiveMode")
        }
        
        // Clear lastCommandType to prevent Watch from auto-starting on next app launch
        clearApplicationContextCommand()
    }
    
    /// Clear the lastCommandType from applicationContext to prevent Watch auto-wake
    private func clearApplicationContextCommand() {
        var context = session.applicationContext
        context.removeValue(forKey: "lastCommandType")
        context.removeValue(forKey: "sessionId")
        context.removeValue(forKey: "sessionContext")
        context["timestamp"] = Date().timeIntervalSince1970
        try? session.updateApplicationContext(context)
    }
    
    private func sendCommand(type: String) {
        var command: [String: Any] = [
            "type": type,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let id = activeSessionId {
            command["sessionId"] = id
        }
        if let ctx = activeSessionContext {
            command["sessionContext"] = ctx
        }
        
        HRDebugLogger.logCommand(type, sessionId: activeSessionId)
        
        // Use multiple delivery methods for reliability
        session.transferUserInfo(command)
        
        // Update application context to help wake Watch
        var context = session.applicationContext
        context["lastCommandType"] = type
        context["timestamp"] = Date().timeIntervalSince1970
        if let id = activeSessionId { context["sessionId"] = id }
        if let ctx = activeSessionContext { context["sessionContext"] = ctx }
        try? session.updateApplicationContext(context)
        
        // Direct message if reachable
        if session.isReachable {
            session.sendMessage(command, replyHandler: nil) { error in
                HRDebugLogger.warn(.watch, "sendMessage error: \(error.localizedDescription)")
            }
        }
    }
    
    func pushHRFeatureFlagToWatch() {
        var context = session.applicationContext
        context["hrFeatureEnabled"] = isHRFeatureEnabled
        context["timestamp"] = Date().timeIntervalSince1970
        try? session.updateApplicationContext(context)
    }
    
    // MARK: - Heart Rate Processing
    
    private func processHeartRateUpdate(_ bpm: Double, sessionId: String?) {
        guard isHRFeatureEnabled else { return }
        
        // Mark that Watch is actually sending HR data
        hasReceivedWatchHR = true
        
        // De-duplicate
        if let lastTs = lastUpdateTime {
            let age = Date().timeIntervalSince(lastTs)
            if age < 1.0, let last = lastHeartRate, Int(last) == Int(bpm) {
                return
            }
        }
        
        let now = Date()
        
        DispatchQueue.main.async {
            self.lastHeartRate = bpm
            self.lastUpdateTime = now
        }
        
        HRDebugLogger.logBPM(.watch, bpm: bpm, age: 0, source: "WatchApp")
        
        // Forward to router
        HeartRateRouter.shared.ingestWatch(bpm: bpm, at: now)
    }
    
    // MARK: - Connectivity Setup
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        
        session.delegate = self
        session.activate()
        
        HRDebugLogger.log(.watch, "WCSession activated")
        
        // Push initial context
        let context: [String: Any] = [
            "type": "phoneReady",
            "timestamp": Date().timeIntervalSince1970,
            "hrFeatureEnabled": isHRFeatureEnabled
        ]
        try? session.updateApplicationContext(context)
    }
    
    private func startConnectivityMonitoring() {
        connectivityCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateConnectivityStatus()
        }
        updateConnectivityStatus()
    }
    
    private func updateConnectivityStatus() {
        let connected = session.isPaired && session.isWatchAppInstalled
        DispatchQueue.main.async {
            self.isWatchConnected = connected
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            let isConnected = activationState == .activated && session.isPaired && session.isWatchAppInstalled
            self.isWatchConnected = isConnected
            
            if let error = error {
                HRDebugLogger.error(.watch, "Activation error: \(error.localizedDescription)")
            } else {
                HRDebugLogger.log(.watch, "Session activated - connected=\(isConnected)")
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
        }
        HRDebugLogger.log(.watch, "Session inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
        }
        HRDebugLogger.log(.watch, "Session deactivated - reactivating")
        session.activate()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        updateConnectivityStatus()
        HRDebugLogger.log(.watch, "Reachability changed - reachable=\(session.isReachable)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncomingMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        handleIncomingMessage(userInfo)
    }
    
    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "heartRateUpdate":
            if let hr = message["heartRate"] as? Double {
                let sessionId = message["sessionId"] as? String
                processHeartRateUpdate(hr, sessionId: sessionId)
            }
            
        case "hrStreamingStarted":
            guard isHRFeatureEnabled else { return }
            let ackSessionId = message["sessionId"] as? String
            // Only log once per session to reduce spam
            if !hasLoggedStreamingAck {
                hasLoggedStreamingAck = true
                HRDebugLogger.log(.watch, "Streaming started ack received sessionId=\(ackSessionId ?? "none")")
            }
            NotificationCenter.default.post(name: .hrStreamingStartedAck, object: nil, userInfo: ackSessionId.map { ["sessionId": $0] })
            
        case "hrPermissionMissing":
            // Only warn once per session and only if Watch isn't actually sending HR
            if !hasReceivedWatchHR && !hasLoggedPermissionWarning {
                hasLoggedPermissionWarning = true
                HRDebugLogger.warn(.watch, "Watch reports HR permission missing")
            }
            
        case "watchAppDidBecomeActive":
            HRDebugLogger.log(.watch, "Watch app became active")
            
        case "watchAppDidEnterBackground":
            HRDebugLogger.log(.watch, "Watch app entered background")
            
        default:
            HRDebugLogger.log(.watch, "Unknown message type: \(type)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let hrStreamingStartedAck = Notification.Name("hrStreamingStartedAck")
}
