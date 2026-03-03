import Foundation
import WatchConnectivity

/// Secondary heart rate provider using Apple Watch via WatchConnectivity.
/// Thin wrapper that sends fire-and-forget commands to the Watch app.
final class WatchHRProvider: HeartRateProvider {
    
    // MARK: - HeartRateProvider
    
    let priority: Int = 2
    
    var isAvailable: Bool {
        WCSession.isSupported() && WatchPairingManager.shared.isWatchPaired
    }
    
    private(set) var lastSampleDate: Date?
    
    // MARK: - Private Properties
    
    private let connectivity = PhoneConnectivityManager.shared
    private var isRunning = false
    private var retryTimer: Timer?
    private var retryCount = 0
    private let maxRetries = 2
    private var activeSessionId: String?
    
    // MARK: - HeartRateProvider Methods
    
    func start(sessionId: String) {
        guard isAvailable else {
            HRDebugLogger.warn(.watch, "Watch not available (paired=\(WatchPairingManager.shared.isWatchPaired))")
            return
        }
        
        guard !isRunning else {
            HRDebugLogger.log(.watch, "Already running - ignoring start")
            return
        }
        
        HRDebugLogger.log(.watch, "Starting for session \(sessionId)")
        
        isRunning = true
        activeSessionId = sessionId
        retryCount = 0
        
        // Send start command to Watch
        sendStartCommand(sessionId: sessionId)
        
        // Schedule retry if no data arrives
        scheduleRetry(sessionId: sessionId)
    }
    
    func stop(sessionId: String) {
        guard isRunning else {
            HRDebugLogger.log(.watch, "Not running - ignoring stop")
            return
        }
        
        HRDebugLogger.log(.watch, "Stopping")
        
        retryTimer?.invalidate()
        retryTimer = nil
        
        // Send stop command to Watch
        connectivity.notifyPracticeEnded(sessionId: sessionId)
        HRDebugLogger.logCommand("stopLiveMode", sessionId: sessionId)
        
        isRunning = false
        activeSessionId = nil
        retryCount = 0
        
        HRDebugLogger.log(.watch, "Stopped")
    }
    
    // MARK: - Watch Communication
    
    private func sendStartCommand(sessionId: String) {
        // Command logging is done inside PhoneConnectivityManager.sendCommand()
        connectivity.notifyPracticePreloaded(sessionId: sessionId, context: "meditation")
    }
    
    private func scheduleRetry(sessionId: String) {
        // Don't bother with retries if Watch is clearly not reachable
        // This avoids wasting 30+ seconds when user only has AirPods
        // Do NOT skip retries when Watch is not reachable.
        // Each retry calls forceStartHeartRateNudge() which updates updateApplicationContext
        // with lastCommandType = "startLiveMode". When the user opens the Dojo Watch app
        // at any point during the session, didReceiveApplicationContext fires immediately
        // and WatchSensorService.start() is called — regardless of when in the session
        // the app was opened. Skipping retries here made the context go stale, causing
        // Watch HR to fail even when the app was opened mid-session.
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isRunning else { return }

            let hasWatchData = HeartRateRouter.shared.currentSource == .watch

            if !hasWatchData && self.retryCount < self.maxRetries {
                self.retryCount += 1
                let reachable = WCSession.default.isReachable
                HRDebugLogger.warn(.watch, "No data — nudging Watch (attempt \(self.retryCount)/\(self.maxRetries), reachable=\(reachable))")
                self.connectivity.forceStartHeartRateNudge()
                self.scheduleRetry(sessionId: sessionId)
            } else if !hasWatchData {
                HRDebugLogger.warn(.watch, "Max retries reached — open Dojo Watch app to activate HR")
            }
        }
    }
    
    /// Called when heart rate data is received from Watch.
    /// This allows the provider to track its last sample date.
    func didReceiveHeartRate(bpm: Double, at date: Date) {
        lastSampleDate = date
    }
}

