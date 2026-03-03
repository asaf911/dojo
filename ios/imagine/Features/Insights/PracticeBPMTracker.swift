import Foundation
import Combine

// MARK: - Analytics Debug Logging

private let ANALYTICS_TAG = "📊 ANALYTICS:"

private func analyticsLog(_ message: String) {
    print("\(ANALYTICS_TAG) [HeartRate] \(message)")
}

// MARK: - Heart Rate Sample for Graphing
struct HeartRateSamplePoint: Codable, Equatable {
    let minuteOffset: Double  // Minutes since session start
    let bpm: Double
}

class PracticeBPMTracker: ObservableObject {
    static let shared = PracticeBPMTracker()
    
    // MARK: - Core Data
    @Published var currentBPM: Double = 0
    @Published var lastUpdateTime: Date?
    
    // MARK: - Live Session Results (Updates During Practice)
    @Published var firstThreeAverage: Double = 0      // Average of first 3 readings
    @Published var lastThreeAverage: Double = 0       // Average of last 3 readings  
    @Published var overallAverage: Double = 0         // Average of all readings
    @Published var heartRateChange: Double = 0        // Percentage change (first3 to last3)
    @Published var sampleCount: Int = 0
    
    // MARK: - Final Session Results (Locked After Practice Ends)
    @Published var finalFirstThreeAverage: Double = 0
    @Published var finalLastThreeAverage: Double = 0
    @Published var finalOverallAverage: Double = 0
    @Published var finalHeartRateChange: Double = 0
    @Published var finalSampleCount: Int = 0
    @Published var hasLockedResults: Bool = false     // True when final results are locked
    
    // MARK: - Internal Tracking
    private var allReadings: [(bpm: Double, timestamp: Date)] = []
    private var isTracking = false
    private var sessionStartTime: Date?
    private var routerCancellable: AnyCancellable?
    private var hasLoggedSessionAnalytics = false  // Prevents duplicate heart_rate_session_complete events
    
    private init() {}
    
    // MARK: - Heart Rate Data Processing
    
    func receivedHeartRate(_ bpm: Double, timestamp: Date) {
        DispatchQueue.main.async {
            self.currentBPM = bpm
            self.lastUpdateTime = timestamp
            
            // Only add readings if we're actively tracking a practice session
            // Don't automatically start tracking just because heart rate data arrives
            if self.isTracking {
                self.allReadings.append((bpm: bpm, timestamp: timestamp))
                self.sampleCount = self.allReadings.count
                self.calculateMetrics()
                
                HRDebugLogger.log(.bpmTracker, "Received \(Int(bpm)) BPM (total: \(self.sampleCount) readings)")
            } else {
                // Heart rate data received but no active practice session - just update current BPM
                HRDebugLogger.log(.bpmTracker, "Received \(Int(bpm)) BPM (not tracking)")
            }
        }
    }
    
    // MARK: - Session Management
    
    /// Explicitly start a new heart rate tracking session
    /// This should be called when a new practice begins to ensure clean state
    func startNewSession() {
        DispatchQueue.main.async {
            HRDebugLogger.log(.bpmTracker, "Starting new session - clearing previous data")
            self.resetFinalResults()
            self.resetMetrics()
            self.allReadings.removeAll()
            self.currentBPM = 0
            self.lastUpdateTime = nil
            self.isTracking = true
            self.sessionStartTime = Date()
            self.hasLoggedSessionAnalytics = false  // Reset for new session
            HRDebugLogger.log(.bpmTracker, "Session active - ready for heart rate data")

            // Subscribe to unified router stream
            // NOTE: Router session is managed by HeartRateService - do NOT call startSession() here
            self.routerCancellable = HeartRateRouter.shared.$currentBPM
                .receive(on: DispatchQueue.main)
                .sink { [weak self] (bpm: Double) in
                    guard let self = self else { return }
                    guard bpm > 0 else { return }
                    self.receivedHeartRate(bpm, timestamp: Date())
                }
        }
    }
    
    func stopTracking() {
        // CRITICAL: Lock results synchronously so they're immediately available
        // This ensures recordPracticeCompletion() gets the correct values
        isTracking = false
        routerCancellable?.cancel()
        routerCancellable = nil
        // NOTE: Router session is managed by HeartRateService - do NOT call endSession() here
        lockFinalResults()
        
        HRDebugLogger.log(.bpmTracker, "Stopped tracking - \(finalSummaryString)")
        
        // Guard against duplicate analytics - only log once per session
        // (stopTracking may be called multiple times: at 95%, 100%, and on view disappear)
        guard !hasLoggedSessionAnalytics else {
            analyticsLog("⏭️ Skipping duplicate heart_rate_session_complete (already logged)")
            return
        }
        hasLoggedSessionAnalytics = true
        
        // CRITICAL: Capture practice details SYNCHRONOUSLY before any async.
        // SessionContextManager is cleared in endSession(); by the time main.async runs, context may be nil.
        let practiceDetails = WatchAnalyticsManager.shared.getPracticeDetailsForHeartRate()
        
        // Analytics tracking can be async (non-blocking)
        let startTime = sessionStartTime
        let hasValid = hasValidData
        let finalFirst = finalFirstThreeAverage
        let finalLast = finalLastThreeAverage
        let finalAvg = finalOverallAverage
        let finalCount = finalSampleCount
        
        // Capture session_id to link heart_rate_session_complete with session_start/session_complete
        let sessionId = SessionContextManager.shared.currentContext?.sessionId
        
        DispatchQueue.main.async {
            if let startTime = startTime, hasValid {
                let duration = Date().timeIntervalSince(startTime)
                
                WatchAnalyticsManager.shared.trackHeartRateSession(
                    sessionId: sessionId,
                    practiceTitle: practiceDetails.title,
                    practiceCategory: practiceDetails.category,
                    practiceDuration: practiceDetails.duration,
                    contentType: practiceDetails.contentType,
                    heartRateResults: (
                        startBPM: finalFirst,
                        endBPM: finalLast,
                        avgBPM: finalAvg,
                        sampleCount: finalCount,
                        duration: duration
                    ),
                    error: nil
                )
            } else {
                let error: WatchAnalyticsManager.HeartRateError = hasValid ? .insufficientSamples : .noDataReceived
                
                WatchAnalyticsManager.shared.trackHeartRateSession(
                    sessionId: sessionId,
                    practiceTitle: practiceDetails.title,
                    practiceCategory: practiceDetails.category,
                    practiceDuration: practiceDetails.duration,
                    contentType: practiceDetails.contentType,
                    heartRateResults: nil,
                    error: error
                )
            }
        }
    }
    
    func resetData() {
        DispatchQueue.main.async {
            self.currentBPM = 0
            self.lastUpdateTime = nil
            self.allReadings.removeAll()
            self.resetMetrics()
            self.resetFinalResults()
            self.isTracking = false
            self.sessionStartTime = nil
            self.hasLoggedSessionAnalytics = false
            HRDebugLogger.log(.bpmTracker, "Reset all data")
        }
    }
    
    // MARK: - Calculations (Simple & Bulletproof)
    
    private func resetMetrics() {
        firstThreeAverage = 0
        lastThreeAverage = 0
        overallAverage = 0
        heartRateChange = 0
        sampleCount = 0
    }
    
    private func resetFinalResults() {
        finalFirstThreeAverage = 0
        finalLastThreeAverage = 0
        finalOverallAverage = 0
        finalHeartRateChange = 0
        finalSampleCount = 0
        hasLockedResults = false
    }
    
    /// Lock the current metrics as final session results
    private func lockFinalResults() {
        calculateMetrics() // Ensure final calculation
        
        finalFirstThreeAverage = firstThreeAverage
        finalLastThreeAverage = lastThreeAverage
        finalOverallAverage = overallAverage
        finalHeartRateChange = heartRateChange
        finalSampleCount = sampleCount
        hasLockedResults = true
        
        HRDebugLogger.log(.bpmTracker, "Final results LOCKED: \(finalSampleCount) readings, first3=\(String(format: "%.0f", finalFirstThreeAverage)), last3=\(String(format: "%.0f", finalLastThreeAverage)), avg=\(String(format: "%.0f", finalOverallAverage)), change=\(String(format: "%.1f", finalHeartRateChange))%")
    }
    
    /// Calculate metrics as readings come in (for live updates)
    private func calculateMetrics() {
        guard !allReadings.isEmpty else { return }
        
        let bpmValues = allReadings.map { $0.bpm }
        
        // Overall average (always calculated)
        overallAverage = bpmValues.reduce(0, +) / Double(bpmValues.count)
        
        // Handle different sample counts for first/last averages
        switch bpmValues.count {
        case 1:
            // Single reading: use it for both start and end
            firstThreeAverage = bpmValues[0]
            lastThreeAverage = bpmValues[0]
            
        case 2:
            // Two readings: first is start, last is end
            firstThreeAverage = bpmValues[0]
            lastThreeAverage = bpmValues[1]
            
        default:
            // 3+ readings: use first 3 and last 3 averages
            let first3 = Array(bpmValues.prefix(3))
            firstThreeAverage = first3.reduce(0, +) / Double(first3.count)
            
            let last3 = Array(bpmValues.suffix(3))
            lastThreeAverage = last3.reduce(0, +) / Double(last3.count)
        }
        
        // Calculate percentage change
        if firstThreeAverage > 0 {
            heartRateChange = ((lastThreeAverage - firstThreeAverage) / firstThreeAverage) * 100
        }
    }
    
    // MARK: - Graph Data
    
    /// Returns samples formatted for graphing with minute offsets
    var graphSamples: [HeartRateSamplePoint] {
        guard let startTime = sessionStartTime else { return [] }
        return allReadings.map { reading in
            let minuteOffset = reading.timestamp.timeIntervalSince(startTime) / 60.0
            return HeartRateSamplePoint(minuteOffset: minuteOffset, bpm: reading.bpm)
        }
    }
    
    // MARK: - Data Access (Simple & Reliable)
    
    /// Valid data: 2+ samples with computable start/end values (can show graph)
    var hasValidData: Bool {
        if hasLockedResults {
            return finalSampleCount >= 2 && finalFirstThreeAverage > 0 && finalLastThreeAverage > 0
        }
        return sampleCount >= 2 && firstThreeAverage > 0 && lastThreeAverage > 0
    }
    
    /// Minimal data: exactly 1 sample (can show average but no graph)
    var hasMinimalData: Bool {
        if hasLockedResults {
            return finalSampleCount == 1 && finalOverallAverage > 0
        }
        return sampleCount == 1 && overallAverage > 0
    }
    
    var hasAnyData: Bool {
        if hasLockedResults {
            return finalSampleCount > 0 && finalOverallAverage > 0
        }
        return sampleCount > 0 && overallAverage > 0
    }
    
    var isReceivingData: Bool {
        guard let lastUpdate = lastUpdateTime else { return false }
        return Date().timeIntervalSince(lastUpdate) < 60
    }
    
    var summaryString: String {
        if hasLockedResults {
            return "FINAL - First3: \(String(format: "%.1f", finalFirstThreeAverage)), Last3: \(String(format: "%.1f", finalLastThreeAverage)), Change: \(String(format: "%.1f", finalHeartRateChange))%"
        }
        return "LIVE - First3: \(String(format: "%.1f", firstThreeAverage)), Last3: \(String(format: "%.1f", lastThreeAverage)), Change: \(String(format: "%.1f", heartRateChange))%"
    }
    
    var finalSummaryString: String {
        return "First3: \(String(format: "%.1f", finalFirstThreeAverage)), Last3: \(String(format: "%.1f", finalLastThreeAverage)), Change: \(String(format: "%.1f", finalHeartRateChange))%"
    }
    
    // MARK: - Results Access (Use Final Results if Available)
    
    /// Get the appropriate first three average (final if locked, otherwise live)
    var bestFirstThreeAverage: Double {
        return hasLockedResults ? finalFirstThreeAverage : firstThreeAverage
    }
    
    /// Get the appropriate last three average (final if locked, otherwise live)
    var bestLastThreeAverage: Double {
        return hasLockedResults ? finalLastThreeAverage : lastThreeAverage
    }
    
    /// Get the appropriate heart rate change (final if locked, otherwise live)
    var bestHeartRateChange: Double {
        return hasLockedResults ? finalHeartRateChange : heartRateChange
    }
    
    /// Get the appropriate overall average (final if locked, otherwise live)
    var bestOverallAverage: Double {
        return hasLockedResults ? finalOverallAverage : overallAverage
    }
    
    // MARK: - Legacy Compatibility (for existing code)
    
    var hasData: Bool { hasAnyData }
    var hasReliableData: Bool { hasValidData }
    var startBPM: Double { bestFirstThreeAverage } 
    var endBPM: Double { bestLastThreeAverage }
    var averageBPM: Double { bestOverallAverage }
    var averagedStartBPM: Double { bestFirstThreeAverage }
    var averagedEndBPM: Double { bestLastThreeAverage }
    
    // Legacy methods (now simple and reliable)
    func getReliableAveragedStartBPM() -> Double { bestFirstThreeAverage }
    func getReliableAveragedEndBPM() -> Double { bestLastThreeAverage }
    func getReliableHeartRateChange() -> Double { bestHeartRateChange }
    func updateAveragedValuesNow() { calculateMetrics() }
    
    // Legacy method for external summary (no longer needed but kept for compatibility)
    func receivedSessionSummary(startBPM: Double, endBPM: Double, averageBPM: Double, sampleCount: Int, duration: TimeInterval) {
        // No-op: We now rely entirely on our own calculations
        HRDebugLogger.log(.bpmTracker, "Ignoring external summary - using internal calculations")
    }
} 