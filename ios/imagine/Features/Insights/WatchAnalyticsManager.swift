import Foundation
import WatchConnectivity
import Mixpanel

// MARK: - Debug Logging

private let ANALYTICS_TAG = "📊 ANALYTICS:"

private func analyticsLog(_ message: String) {
    print("\(ANALYTICS_TAG) [HeartRate] \(message)")
}

/// Dedicated analytics manager for watch and heart rate insights
class WatchAnalyticsManager {
    static let shared = WatchAnalyticsManager()

    private init() {}

    // MARK: - Core Analytics Methods

    /// Track overall watch status and capabilities
    func trackWatchStatus() {
        let watchPaired = WatchPairingManager.shared.isWatchPaired
        let session = WCSession.default

        var parameters: [String: Any] = [
            "watch_paired": watchPaired,
            "watch_connectivity_supported": WCSession.isSupported()
        ]

        if watchPaired && WCSession.isSupported() {
            parameters["watch_app_installed"] = session.isWatchAppInstalled
            parameters["watch_reachable"] = session.isReachable
            parameters["watch_session_activated"] = session.activationState == .activated
        }

        AnalyticsManager.shared.logEvent("watch_status_checked", parameters: parameters)
    }

    // MARK: - Simplified Heart Rate Session Tracking

    /// Single comprehensive event that tracks complete heart rate session results.
    /// Linked to session_start / session_complete via shared session_id.
    /// - Note: Pass captured practice details and contentType; context may be cleared by the time this runs (async).
    func trackHeartRateSession(
        sessionId: String? = nil,
        practiceTitle: String? = nil,
        practiceCategory: String? = nil,
        practiceDuration: Int? = nil,
        contentType: String? = nil,
        heartRateResults: (startBPM: Double, endBPM: Double, avgBPM: Double, sampleCount: Int, duration: TimeInterval)? = nil,
        error: HeartRateError? = nil
    ) {

        let watchPaired = WatchPairingManager.shared.isWatchPaired
        let connectivityManager = PhoneConnectivityManager.shared

        let routerSnapshot = HeartRateRouter.shared.snapshot()
        var parameters: [String: Any] = [
            "watch_paired": watchPaired
        ]

        // Add session_id to link with session_start / session_complete
        if let sessionId = sessionId {
            parameters["session_id"] = sessionId
        }

        // Add practice details (use passed-in values; caller must capture before context is cleared)
        if let title = practiceTitle {
            parameters["practice_title"] = title
        }
        if let category = practiceCategory {
            parameters["practice_category"] = category
        }
        if let duration = practiceDuration {
            parameters["practice_duration_minutes"] = duration
        }

        // Add content_type for Mixpanel segmentation (pre_recorded, path_step, custom_meditation)
        if let contentType = contentType {
            parameters["content_type"] = contentType
        }

        // Add watch connectivity status
        if watchPaired {
            parameters["watch_status"] = getWatchStatusString(connectivityManager.heartRateStatus)
            parameters["watch_connected"] = connectivityManager.isWatchConnected
            parameters["live_mode_active"] = connectivityManager.isLiveMode
        }

        if let results = heartRateResults {
            // Successful measurement
            let changePercent = results.startBPM > 0 ? ((results.endBPM - results.startBPM) / results.startBPM) * 100 : 0

            parameters.merge([
                "measurement_success": true,
                "start_heart_rate": Int(round(results.startBPM)),
                "end_heart_rate": Int(round(results.endBPM)),
                "average_heart_rate": Int(round(results.avgBPM)),
                "heart_rate_change_percent": round(changePercent * 10) / 10, // 1 decimal place
                "heart_rate_impact": getHeartRateImpact(percentageChange: changePercent),
                "sample_count": results.sampleCount,
                "measurement_duration_seconds": Int(results.duration),
                "heart_rate_range": getHeartRateRange(results.avgBPM),
                "measurement_quality": getMeasurementQuality(sampleCount: results.sampleCount, duration: results.duration)
            ]) { _, new in new }

            // Add hr_session_number (1-indexed: this is the Nth successful HR session)
            let currentHRCount = SharedUserStorage.retrieve(forKey: .totalHRSessions, as: Int.self) ?? 0
            parameters["hr_session_number"] = currentHRCount + 1

            if let snapshot = routerSnapshot {
                var extra: [String: Any] = [
                    "primary_source": analyticsSourceValue(snapshot.currentSource),
                    "preferred_source": analyticsSourceValue(snapshot.preferredSource),
                    "sources_used": snapshot.availableSources,
                    "fallback_used": snapshot.hasSwitchedSource
                ]
                if let latency = snapshot.firstSampleLatencyMs {
                    extra["first_sample_latency_ms"] = latency
                }
                parameters.merge(extra) { _, new in new }
                updateMixpanelPeopleAfterSuccess(primarySource: snapshot.currentSource, fallbackUsed: snapshot.hasSwitchedSource, startBPM: results.startBPM)
            }
            
            // Log success with analytics tag
            analyticsLog("═══════════════════════════════════════════")
            analyticsLog("💓 EVENT: heart_rate_session_complete")
            analyticsLog("───────────────────────────────────────────")
            analyticsLog("   measurement_success: true")
            analyticsLog("   start_heart_rate: \(Int(round(results.startBPM))) BPM")
            analyticsLog("   end_heart_rate: \(Int(round(results.endBPM))) BPM")
            analyticsLog("   average_heart_rate: \(Int(round(results.avgBPM))) BPM")
            analyticsLog("   heart_rate_change: \(String(format: "%.1f", changePercent))%")
            analyticsLog("   heart_rate_impact: \(getHeartRateImpact(percentageChange: changePercent))")
            analyticsLog("   sample_count: \(results.sampleCount)")
            if let title = practiceTitle {
                analyticsLog("   practice_title: \(title)")
            }
            if let contentType = contentType {
                analyticsLog("   content_type: \(contentType)")
            }
            analyticsLog("───────────────────────────────────────────")
            analyticsLog("📤 Sending to: Mixpanel only")
            analyticsLog("═══════════════════════════════════════════")

        } else {
            // Failed measurement
            let errorReason = error?.rawValue ?? getHeartRateErrorReason()
            parameters.merge([
                "measurement_success": false,
                "error_reason": errorReason
            ]) { _, new in new }

            if let snapshot = routerSnapshot {
                var extra: [String: Any] = [
                    "primary_source": analyticsSourceValue(snapshot.currentSource),
                    "preferred_source": analyticsSourceValue(snapshot.preferredSource),
                    "sources_used": snapshot.availableSources,
                    "fallback_used": snapshot.hasSwitchedSource
                ]
                if let latency = snapshot.firstSampleLatencyMs {
                    extra["first_sample_latency_ms"] = latency
                }
                parameters.merge(extra) { _, new in new }
            }
            
            // Log failure with analytics tag
            analyticsLog("═══════════════════════════════════════════")
            analyticsLog("💔 EVENT: heart_rate_session_complete (failed)")
            analyticsLog("───────────────────────────────────────────")
            analyticsLog("   measurement_success: false")
            analyticsLog("   error_reason: \(errorReason)")
            analyticsLog("   watch_paired: \(watchPaired)")
            if let title = practiceTitle {
                analyticsLog("   practice_title: \(title)")
            }
            if let contentType = contentType {
                analyticsLog("   content_type: \(contentType)")
            }
            analyticsLog("───────────────────────────────────────────")
            analyticsLog("📤 Sending to: Mixpanel only")
            analyticsLog("═══════════════════════════════════════════")
        }

        AnalyticsManager.shared.logEvent("heart_rate_session_complete", parameters: parameters)
    }

    // MARK: - Heart Rate Impact Categorization (based on PostPracticeHeartRateCard logic)

    private func getHeartRateImpact(percentageChange: Double) -> String {
        let absPercentage = abs(percentageChange)

        if absPercentage < 3.0 {
            return "steady" // No significant change (< 3%)
        } else if percentageChange < 0 && absPercentage >= 15.0 {
            return "deep_relaxation" // Major decrease ≥15%
        } else if percentageChange < 0 && absPercentage >= 5.0 {
            return "regular_relaxation" // Moderate decrease 5-15%
        } else if percentageChange > 0 {
            return "increased" // Heart rate increase
        } else {
            return "subtle_relaxation" // Small decrease <5%
        }
    }

    // MARK: - Error Tracking

    enum HeartRateError: String {
        case watchNotPaired = "watch_not_paired"
        case watchNotConnected = "watch_not_connected"
        case permissionDenied = "permission_denied"
        case noDataReceived = "no_data_received"
        case insufficientSamples = "insufficient_samples"
        case sessionTimeout = "session_timeout"
        case watchAppNotInstalled = "watch_app_not_installed"
        case liveModeNotActive = "live_mode_not_active"
        case unknownError = "unknown_error"
    }


    // MARK: - Helper Methods

    /// Get practice details for heart rate analytics. Call SYNCHRONOUSLY before any async dispatch.
    /// SessionContextManager is preferred (source of truth for current session); AudioPlayerManager may hold stale data.
    func getPracticeDetailsForHeartRate() -> (title: String?, category: String?, duration: Int?, contentType: String?) {
        // Prefer SessionContextManager—it's set for ALL session types and is cleared after session end.
        // Must capture before DispatchQueue.main.async or context may already be nil.
        if let context = SessionContextManager.shared.currentContext {
            return (
                context.practiceTitle,
                context.category ?? "custom",
                context.plannedDurationMinutes,
                context.contentType.rawValue
            )
        }

        // Fallback: AudioPlayerManager (pre-recorded/path). Only used when context was cleared before capture.
        if let audioPlayerManager = AudioPlayerManager.shared,
           let selectedFile = audioPlayerManager.selectedFile {
            let ct: String = selectedFile.tags.contains("path") ? SessionContentType.pathStep.rawValue : SessionContentType.preRecorded.rawValue
            return (
                selectedFile.title,
                selectedFile.category.rawValue,
                Int(ceil(audioPlayerManager.totalDuration / 60)),
                ct
            )
        }

        return (nil, nil, nil, nil)
    }

    /// Get current practice details (for trackHeartRateRetry etc.). Prefers SessionContextManager.
    func getCurrentPracticeDetails() -> (title: String?, category: String?, duration: Int?) {
        let details = getPracticeDetailsForHeartRate()
        return (details.title, details.category, details.duration)
    }

    private func getWatchStatusString(_ status: PhoneConnectivityManager.HeartRateStatus) -> String {
        switch status {
        case .notPaired: return "not_paired"
        case .notConnected: return "not_connected"
        case .notLive: return "not_live"
        case .live: return "live_mode"
        }
    }

    private func getHeartRateRange(_ bpm: Double) -> String {
        switch bpm {
        case 0..<60: return "below_60"
        case 60..<100: return "60_to_100"
        case 100..<140: return "100_to_140"
        case 140..<180: return "140_to_180"
        default: return "above_180"
        }
    }

    private func getHeartRateErrorReason() -> String {
        let connectivityManager = PhoneConnectivityManager.shared

        if !WatchPairingManager.shared.isWatchPaired {
            return "watch_not_paired"
        } else if !connectivityManager.isWatchConnected {
            return "watch_not_connected"
        } else if !connectivityManager.isLiveMode {
            return "live_mode_not_active"
        } else {
            return "unknown_error"
        }
    }

    private func getMeasurementQuality(sampleCount: Int, duration: TimeInterval) -> String {
        let samplesPerMinute = Double(sampleCount) / (duration / 60.0)

        switch samplesPerMinute {
        case 0..<2: return "poor"
        case 2..<4: return "fair"
        case 4..<6: return "good"
        default: return "excellent"
        }
    }

    private func analyticsSourceValue(_ source: HeartRateRouter.Source) -> String {
        switch source {
        case .watch: return "watch"
        case .airpods: return "airpods"
        case .fitbit: return "fitbit"
        case .none: return "none"
        }
    }

    private func updateMixpanelPeopleAfterSuccess(primarySource: HeartRateRouter.Source, fallbackUsed: Bool, startBPM: Double) {
        let mixpanel = Mixpanel.mainInstance()
        mixpanel.people.setOnce(properties: [
            "has_measured_hr": true,
            "first_session_start_hr": Int(round(startBPM))
        ])

        mixpanel.people.set(properties: [
            "last_hr_primary_source": analyticsSourceValue(primarySource),
            "last_hr_measurement_at": Date(),
            "latest_session_start_hr": Int(round(startBPM))
        ])

        mixpanel.people.increment(properties: [
            "total_hr_sessions": 1
        ])

        switch primarySource {
        case .watch:
            mixpanel.people.increment(properties: ["total_hr_watch_sessions": 1])
        case .airpods:
            mixpanel.people.increment(properties: ["total_hr_airpods_sessions": 1])
        case .fitbit:
            mixpanel.people.increment(properties: ["total_hr_fitbit_sessions": 1])
        case .none:
            break
        }

        if fallbackUsed {
            mixpanel.people.increment(properties: ["total_hr_fallback_sessions": 1])
        }
        
        // Increment local HR session counter (mirrors Mixpanel for event enrichment)
        let currentCount = SharedUserStorage.retrieve(forKey: .totalHRSessions, as: Int.self) ?? 0
        SharedUserStorage.save(value: currentCount + 1, forKey: .totalHRSessions)
    }

}

// MARK: - Convenient Extension for Manual Tracking

extension WatchAnalyticsManager {

    /// Call this when user manually retries heart rate monitoring
    func trackHeartRateRetry(practiceTitle: String? = nil, practiceCategory: String? = nil, practiceDuration: Int? = nil) {
        var parameters: [String: Any] = [
            "watch_paired": WatchPairingManager.shared.isWatchPaired,
            "watch_connected": PhoneConnectivityManager.shared.isWatchConnected,
            "retry_initiated_by_user": true
        ]

        // Add practice details if available
        if let title = practiceTitle {
            parameters["practice_title"] = title
        }
        if let category = practiceCategory {
            parameters["practice_category"] = category
        }
        if let duration = practiceDuration {
            parameters["practice_duration_minutes"] = duration
        }

        AnalyticsManager.shared.logEvent("watch_heart_rate_retry", parameters: parameters)
    }

}