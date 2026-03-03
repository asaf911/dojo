import Foundation
import HealthKit
import WatchConnectivity

/// Minimal watch-side service to start/stop HKWorkoutSession and stream throttled HR
final class WatchSensorService: NSObject {
    static let shared = WatchSensorService()

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var lastSentAt: TimeInterval = 0
    private var isStopping: Bool = false
    private var pendingStartSessionId: String?
    private var activeSessionId: String?
    private var isStreaming: Bool = false
    private var firstSampleSent: Bool = false
    private var noDataWatchdog: Timer?
    private var watchdogAttempts: Int = 0
    private var runningStateWatchdog: Timer?
    private var hasEnteredRunning: Bool = false
    private var inactivityWatchdog: Timer?  // Auto-stop if iPhone stops communicating
    private let inactivityTimeoutSeconds: TimeInterval = 30  // 30 seconds - faster cleanup when iPhone disconnects

    func start(sessionId: String) {
        // Gate by feature flag
        guard WatchFeatureFlags.shared.isHRFeatureEnabled else {
            print("[HR] Watch: Feature disabled - ignoring start")
            return
        }
        print("[HR] Watch: Starting HR session \(sessionId)")
        activeSessionId = sessionId
        // If a stop is in progress, defer start
        if isStopping {
            pendingStartSessionId = sessionId
            return
        }
        isStreaming = true
        firstSampleSent = false
        watchdogAttempts = 0
        hasEnteredRunning = false
        runningStateWatchdog?.invalidate()
        DispatchQueue.main.async {
            WatchHealthKitManager.shared.isMeasuringHR = true
        }
        requestAuthorizationIfNeeded { [weak self] in
            self?.startWorkoutSession()
            self?.scheduleNoDataWatchdog()
            self?.scheduleRunningStateWatchdog()
            self?.scheduleInactivityWatchdog()
        }
    }
    
    /// Reset inactivity timer - call when iPhone sends any command
    func resetInactivityTimer() {
        scheduleInactivityWatchdog()
    }

    func stop(sessionId: String) {
        let normalizedSessionId = sessionId.isEmpty ? nil : sessionId
        if let active = activeSessionId, let incoming = normalizedSessionId, active != incoming {
            print("[HR] Watch: Ignoring stop for mismatched sessionId=\(sessionId) active=\(active)")
            return
        }
        print("[HR] Watch: Stopping HR session")
        isStreaming = false
        firstSampleSent = false
        watchdogAttempts = 0
        noDataWatchdog?.invalidate()
        noDataWatchdog = nil
        runningStateWatchdog?.invalidate()
        runningStateWatchdog = nil
        inactivityWatchdog?.invalidate()
        inactivityWatchdog = nil
        DispatchQueue.main.async {
            WatchHealthKitManager.shared.isMeasuringHR = false
        }
        activeSessionId = nil
        stopWorkoutSession()
    }

    private func startWorkoutSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            workoutSession?.delegate = self
            builder = workoutSession?.associatedWorkoutBuilder()
            builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            let startDate = Date()
            print("[HR] Watch: Starting workout activity")
            workoutSession?.startActivity(with: startDate)
            builder?.beginCollection(withStart: Date()) { [weak self] success, _ in
                guard success else { return }
                // Notify iPhone that streaming started (helps wake after idle)
                self?.sendStreamingAck()
                // HR query will be started in session delegate when .running
            }
        } catch {
            // Fallback: still try to stream
            startLiveHeartRateQuery()
            requestImmediateSample()
            sendStreamingAck()
        }
    }

    private func requestAuthorizationIfNeeded(completion: @escaping () -> Void) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { completion(); return }
        let workoutType = HKObjectType.workoutType()
        
        // Check current authorization status for diagnostics
        let hrReadStatus = healthStore.authorizationStatus(for: hrType)
        let workoutShareStatus = healthStore.authorizationStatus(for: workoutType)
        print("[HR] Watch: Current auth status - HR read: \(hrReadStatus.rawValue), Workout share: \(workoutShareStatus.rawValue)")
        
        // If already denied, notify and still attempt (might work with fallback)
        if workoutShareStatus == .sharingDenied {
            print("[HR] Watch: ⚠️ Workout sharing DENIED - HR monitoring may fail. User needs to enable in Settings.")
            sendPermissionMissingSignal()
        }
        
        // Always attempt enabling background delivery
        healthStore.enableBackgroundDelivery(for: hrType, frequency: .immediate) { success, error in
            if !success {
                print("[HR] Watch: Background delivery failed: \(error?.localizedDescription ?? "unknown")")
            }
        }
        
        healthStore.getRequestStatusForAuthorization(toShare: [workoutType], read: [hrType]) { [weak self] status, _ in
            guard let self = self else { return }
            print("[HR] Watch: Auth request status=\(status.rawValue) (0=unknown, 1=shouldRequest, 2=unnecessary)")
            
            switch status {
            case .shouldRequest:
                print("[HR] Watch: Requesting HealthKit authorization...")
                self.healthStore.requestAuthorization(toShare: [workoutType], read: [hrType]) { success, error in
                    if success {
                        print("[HR] Watch: Authorization granted")
                    } else {
                        print("[HR] Watch: Authorization failed: \(error?.localizedDescription ?? "unknown")")
                        self.sendPermissionMissingSignal()
                    }
                    completion()
                }
            case .unnecessary:
                // Auth already determined - check if it was granted or denied
                if workoutShareStatus == .sharingAuthorized {
                    print("[HR] Watch: Authorization already granted - continuing")
                } else {
                    print("[HR] Watch: ⚠️ Authorization was determined but not granted")
                }
                completion()
            default:
                print("[HR] Watch: Unknown auth status - attempting anyway")
                completion()
            }
        }
    }

    private func scheduleNoDataWatchdog() {
        noDataWatchdog?.invalidate()
        noDataWatchdog = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.isStreaming && !self.firstSampleSent && self.watchdogAttempts < 2 {
                self.watchdogAttempts += 1
                print("[HR] Watch: ⚠️ No HR samples after 15s - restarting (attempt \(self.watchdogAttempts)/2)")
                self.stopWorkoutSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard self.isStreaming else { return }
                    self.startWorkoutSession()
                    self.scheduleNoDataWatchdog()
                }
            }
        }
    }

    private func stopWorkoutSession() {
        print("[HR] Watch: 🛑 Stopping and discarding workout session")
        isStopping = true
        if let q = heartRateQuery { healthStore.stop(q) }
        heartRateQuery = nil
        let now = Date()
        
        // DISCARD the workout instead of ending it
        // This prevents saving to HealthKit and clears the system workout indicator immediately
        builder?.discardWorkout()
        
        // Stop the workout activity before ending to ensure sensor shuts down
        workoutSession?.stopActivity(with: now)
        workoutSession?.end()
        
        let hadPendingStart = pendingStartSessionId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            self.workoutSession = nil
            self.builder = nil
            self.isStopping = false
            print("[HR] Watch: Workout session cleaned up")
            if let nextId = hadPendingStart {
                self.pendingStartSessionId = nil
                self.start(sessionId: nextId)
            }
        }
    }

    private func startLiveHeartRateQuery() {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        // Use nil predicate; freshness enforced in process()
        let predicate: NSPredicate? = nil
        let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            self?.process(samples)
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.process(samples)
        }
        heartRateQuery = query
        print("[HR] Watch: HR query started")
        healthStore.execute(query)
    }

    private func process(_ samples: [HKSample]?) {
        guard isStreaming else { return }
        guard let qs = samples as? [HKQuantitySample], let s = qs.last else { return }
        let bpm = s.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let ts = s.startDate.timeIntervalSince1970
        // Drop stale samples (> 10s old)
        if Date().timeIntervalSince(s.startDate) > 10 { return }
        // Throttle to ~1 Hz
        if ts - lastSentAt < 0.9 { return }
        lastSentAt = ts
        if !firstSampleSent { firstSampleSent = true }
        print("[HR] Watch: BPM=\(Int(bpm)) age=\(Int(Date().timeIntervalSince(s.startDate)))s")
        // Reflect into UI state so BPM is visible in the watch app
        WatchHealthKitManager.shared.ingestExternalBPM(bpm, source: "liveQuery")
        WatchConnectivityManager.shared.sendHeartRateUpdate(bpm, sessionId: activeSessionId)
        
        // Keep inactivity watchdog alive while data is flowing
        scheduleInactivityWatchdog()
    }

    private func requestImmediateSample() {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let now = Date()
        let pred = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-60), end: now, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 1, sortDescriptors: [sort]) { [weak self] _, results, _ in
            guard let s = results?.first as? HKQuantitySample else { return }
            let bpm = s.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            guard let self = self, self.isStreaming else { return }
            self.lastSentAt = 0
            // Reflect into UI state so BPM is visible immediately
            WatchHealthKitManager.shared.ingestExternalBPM(bpm, source: "immediateSample")
            WatchConnectivityManager.shared.sendHeartRateUpdate(bpm, sessionId: self.activeSessionId)
        }
        print("[HR] Watch: Requesting immediate HR sample")
        healthStore.execute(q)
    }

    private func scheduleRunningStateWatchdog() {
        runningStateWatchdog?.invalidate()
        runningStateWatchdog = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.isStreaming && !self.hasEnteredRunning {
                print("[HR] Watch: ⚠️ Session not running after 8s - restarting")
                self.stopWorkoutSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard self.isStreaming else { return }
                    self.startWorkoutSession()
                    self.scheduleRunningStateWatchdog()
                }
            }
        }
    }
    
    /// Auto-stop if iPhone hasn't sent any commands for a while
    private func scheduleInactivityWatchdog() {
        inactivityWatchdog?.invalidate()
        inactivityWatchdog = Timer.scheduledTimer(withTimeInterval: inactivityTimeoutSeconds, repeats: false) { [weak self] _ in
            guard let self = self, self.isStreaming else { return }
            print("[HR] Watch: ⚠️ No iPhone activity for \(Int(self.inactivityTimeoutSeconds))s - auto-stopping")
            self.stop(sessionId: self.activeSessionId ?? "")
        }
    }

    private func sendStreamingAck() {
        var info: [String: Any] = [
            "type": "hrStreamingStarted",
            "timestamp": Date().timeIntervalSince1970
        ]
        if let id = activeSessionId {
            info["sessionId"] = id
        }
        let s = WCSession.default
        if s.isReachable { s.sendMessage(info, replyHandler: nil, errorHandler: nil) }
        s.transferUserInfo(info)
    }

    private func sendPermissionMissingSignal() {
        var info: [String: Any] = [
            "type": "hrPermissionMissing",
            "timestamp": Date().timeIntervalSince1970
        ]
        if let id = activeSessionId {
            info["sessionId"] = id
        }
        let s = WCSession.default
        if s.isReachable { s.sendMessage(info, replyHandler: nil, errorHandler: nil) }
        s.transferUserInfo(info)
    }
}

extension WatchSensorService: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    // MARK: - HKWorkoutSessionDelegate
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        print("[HR] Watch: Workout state \(fromState.rawValue) -> \(toState.rawValue)")
        switch toState {
        case .running:
            hasEnteredRunning = true
            startLiveHeartRateQuery()
            requestImmediateSample()
        case .ended, .stopped:
            if let q = heartRateQuery { healthStore.stop(q) }
            heartRateQuery = nil
        default:
            break
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[HR] Watch: ❌ Workout failed: \(error.localizedDescription)")
        sendPermissionMissingSignal()
    }

    // MARK: - HKLiveWorkoutBuilderDelegate
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // no-op
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        // no-op
    }
}
