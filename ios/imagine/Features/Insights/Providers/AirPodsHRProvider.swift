import Foundation
import HealthKit
import AVFoundation

/// Primary heart rate provider using direct HealthKit access.
/// Works with AirPods Pro 3 (only Pro 3 has HR sensor - Pro 2 does NOT).
/// 
/// On iOS 26+: Starts an HKWorkoutSession on iPhone to enable continuous HR from AirPods Pro.
/// On iOS 25 and earlier: Uses observer/anchored queries to catch HR data from HealthKit
/// (requires Watch workout or other app measuring HR).
final class AirPodsHRProvider: NSObject, HeartRateProvider {
    
    // MARK: - HeartRateProvider
    
    let priority: Int = 1
    
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    private(set) var lastSampleDate: Date?
    
    // MARK: - Private Properties
    
    private let healthStore = HKHealthStore()
    private var anchor: HKQueryAnchor?
    private var anchoredQuery: HKAnchoredObjectQuery?
    private var observerQuery: HKObserverQuery?
    
    // Type-erased for iOS 26+ availability (iPhone HKWorkoutSession)
    private var workoutSession: AnyObject?
    private var workoutBuilder: AnyObject?
    
    private var isRunning = false
    private var pollTimer: Timer?
    private var lastProcessedDate: Date?
    private var diagnosticTimer: Timer?
    
    // MARK: - HeartRateProvider Methods
    
    func start(sessionId: String) {
        guard !isRunning else {
            HRDebugLogger.log(.airpods, "Already running - ignoring start")
            return
        }
        
        guard isAvailable else {
            HRDebugLogger.error(.airpods, "HealthKit not available on this device")
            return
        }
        
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            HRDebugLogger.error(.airpods, "Heart rate type not available")
            return
        }
        
        HRDebugLogger.log(.airpods, "Starting for session \(sessionId)")
        
        let workoutType = HKObjectType.workoutType()
        
        healthStore.requestAuthorization(toShare: [workoutType], read: [hrType]) { [weak self] success, error in
            guard let self = self else { return }
            
            if success {
                HRDebugLogger.log(.airpods, "Authorization granted")
                DispatchQueue.main.async {
                    self.setupAfterAuth(hrType: hrType)
                }
            } else {
                HRDebugLogger.error(.airpods, "Authorization failed: \(error?.localizedDescription ?? "unknown")")
            }
        }
    }
    
    func stop(sessionId: String) {
        guard isRunning else {
            HRDebugLogger.log(.airpods, "Not running - ignoring stop")
            return
        }
        
        HRDebugLogger.log(.airpods, "Stopping")
        
        // Stop queries
        if let q = anchoredQuery { healthStore.stop(q) }
        if let q = observerQuery { healthStore.stop(q) }
        anchoredQuery = nil
        observerQuery = nil
        
        // Stop polling and diagnostics
        pollTimer?.invalidate()
        pollTimer = nil
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil
        
        // Stop workout session (iOS 26+)
        stopWorkoutSession()
        
        // Reset state
        anchor = nil
        lastProcessedDate = nil
        isRunning = false
        
        HRDebugLogger.log(.airpods, "Stopped")
    }
    
    // MARK: - Private Setup
    
    private func setupAfterAuth(hrType: HKQuantityType) {
        // Enable background delivery
        healthStore.enableBackgroundDelivery(for: hrType, frequency: .immediate) { success, error in
            if !success {
                HRDebugLogger.warn(.airpods, "Background delivery failed: \(error?.localizedDescription ?? "unknown")")
            }
        }
        
        // Start workout session for AirPods Pro HR (iOS 26+)
        startWorkoutSessionIfPossible()
        
        // Start queries
        startQueries(hrType: hrType)
        
        // Start polling as safety net
        startPolling(hrType: hrType)
        
        // Immediate sweep for any recent samples
        fetchRecentSamples(hrType: hrType, lookbackSeconds: 60)
        
        isRunning = true
        HRDebugLogger.log(.airpods, "Queries started")
        
        // Schedule diagnostic check after 10 seconds
        scheduleDiagnosticCheck()
    }
    
    private func scheduleDiagnosticCheck() {
        diagnosticTimer?.invalidate()
        diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            
            if self.lastSampleDate == nil {
                // Use improved connection detection
                let proConnected = Self.areAirPodsProConnected()
                let proActive = Self.areAirPodsProActiveAudioOutput
                
                if proConnected && !proActive {
                    // AirPods Pro connected to iPhone but audio not playing through them
                    HRDebugLogger.log(.airpods, "Waiting for audio playback - AirPods Pro connected but not active")
                } else if !proConnected {
                    // AirPods may be connected to another device - this is normal
                    // HR will activate when user taps play (auto-switch)
                    HRDebugLogger.log(.airpods, "Waiting for audio - AirPods may be on another device")
                    HRDebugLogger.log(.airpods, "HR will activate when audio plays from this iPhone")
                }
                
                // Log workout session state for debugging
                if #available(iOS 26.0, *) {
                    if let session = self.workoutSession as? HKWorkoutSession {
                        HRDebugLogger.log(.airpods, "Workout session state: \(session.state.rawValue)")
                    }
                }
            } else {
                HRDebugLogger.log(.airpods, "AirPods HR active ✓")
            }
        }
    }
    
    // MARK: - AirPods Connection Detection
    
    /// Check if AirPods Pro are CONNECTED to this iPhone (via Bluetooth).
    /// This works even before audio playback starts.
    /// NOTE: `availableInputs` shows connected Bluetooth devices even when not active.
    static func areAirPodsProConnected() -> Bool {
        let session = AVAudioSession.sharedInstance()
        
        // Check available inputs (connected Bluetooth devices)
        if let inputs = session.availableInputs {
            for input in inputs {
                let name = input.portName.lowercased()
                if name.contains("airpods") && name.contains("pro") {
                    return true
                }
            }
        }
        
        // Also check current route outputs (if audio is playing)
        for output in session.currentRoute.outputs {
            let name = output.portName.lowercased()
            if name.contains("airpods") && name.contains("pro") {
                return true
            }
        }
        
        return false
    }
    
    /// Check if any AirPods (Pro or not) are connected.
    static func areAnyAirPodsConnected() -> Bool {
        let session = AVAudioSession.sharedInstance()
        
        if let inputs = session.availableInputs {
            for input in inputs {
                let name = input.portName.lowercased()
                if name.contains("airpods") {
                    return true
                }
            }
        }
        
        for output in session.currentRoute.outputs {
            let name = output.portName.lowercased()
            if name.contains("airpods") {
                return true
            }
        }
        
        return false
    }
    
    /// Get a human-readable status for AirPods connection.
    /// Uses `availableInputs` to detect connected devices (not just active audio).
    static func checkAirPodsAudioConnection() -> String {
        let session = AVAudioSession.sharedInstance()
        
        // First check if AirPods Pro are connected (via available inputs)
        if let inputs = session.availableInputs {
            for input in inputs {
                let name = input.portName.lowercased()
                if name.contains("airpods") && name.contains("pro") {
                    // Check if also active audio output
                    if areAirPodsProActiveAudioOutput {
                        return "AirPods Pro connected & active ✓"
                    } else {
                        return "AirPods Pro connected (play audio to activate HR)"
                    }
                } else if name.contains("airpods") {
                    return "AirPods connected (only Pro 3 has HR)"
                }
            }
        }
        
        // Check current route outputs (for when audio is playing)
        for output in session.currentRoute.outputs {
            let name = output.portName.lowercased()
            if name.contains("airpods") && name.contains("pro") {
                return "AirPods Pro connected & active ✓"
            } else if name.contains("airpods") {
                return "AirPods connected (only Pro 3 has HR)"
            }
        }
        
        return "No AirPods detected"
    }
    
    /// Check if AirPods Pro are actively connected for audio playback.
    /// This only returns true when audio is actually playing through them.
    static var areAirPodsProActiveAudioOutput: Bool {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        
        for output in outputs {
            let name = output.portName.lowercased()
            let type = output.portType
            
            if (type == .bluetoothA2DP || type == .bluetoothLE || type == .bluetoothHFP) &&
               name.contains("airpods") && name.contains("pro") {
                return true
            }
        }
        return false
    }
    
    // MARK: - Queries
    
    private func startQueries(hrType: HKQuantityType) {
        // Anchored query for incremental updates
        let anchored = HKAnchoredObjectQuery(
            type: hrType,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.processSamples(samples)
        }
        
        anchored.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.processSamples(samples)
        }
        
        anchoredQuery = anchored
        healthStore.execute(anchored)
        
        // Observer query to wake app
        let observer = HKObserverQuery(sampleType: hrType, predicate: nil) { [weak self] _, completion, _ in
            self?.fetchRecentSamples(hrType: hrType, lookbackSeconds: 30) {
                completion()
            }
        }
        
        observerQuery = observer
        healthStore.execute(observer)
    }
    
    private func startPolling(hrType: HKQuantityType) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.fetchRecentSamples(hrType: hrType, lookbackSeconds: 60)
        }
    }
    
    private func fetchRecentSamples(hrType: HKQuantityType, lookbackSeconds: TimeInterval, completion: (() -> Void)? = nil) {
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-lookbackSeconds),
            end: now,
            options: .strictEndDate
        )
        
        let query = HKSampleQuery(
            sampleType: hrType,
            predicate: predicate,
            limit: 10,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        ) { [weak self] _, results, _ in
            self?.processSamples(results)
            completion?()
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Sample Processing
    
    private func processSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], let latest = quantitySamples.last else {
            return
        }
        
        let age = Date().timeIntervalSince(latest.startDate)
        
        // Drop stale samples (> 30s old)
        guard age <= 30 else { return }
        
        let sourceName = latest.sourceRevision.source.name
        
        // Skip samples from Apple Watch - those should come through WatchConnectivity
        // This prevents HealthKit from routing old Watch data as "AirPods" data
        if sourceName.lowercased().contains("watch") {
            return
        }
        
        // De-duplicate by sample date
        if let lastDate = lastProcessedDate, latest.startDate <= lastDate {
            return
        }
        lastProcessedDate = latest.startDate
        lastSampleDate = latest.startDate
        
        let bpm = latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        
        HRDebugLogger.logBPM(.airpods, bpm: bpm, age: age, source: sourceName)
        
        // Forward to router
        HeartRateRouter.shared.ingestHealthKit(bpm: bpm, sourceName: sourceName, at: latest.startDate)
    }
    
    // MARK: - Workout Session (enables active AirPods Pro HR measurement)
    
    private func startWorkoutSessionIfPossible() {
        // iPhone HKWorkoutSession requires iOS 26+
        guard #available(iOS 26.0, *) else {
            HRDebugLogger.log(.airpods, "iPhone workout session requires iOS 26+ - update iOS to enable AirPods Pro HR")
            return
        }
        
        HRDebugLogger.log(.airpods, "Starting iPhone workout session for AirPods Pro HR...")
        
        // Check workout share authorization
        let shareStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        let statusDesc = switch shareStatus {
            case .notDetermined: "notDetermined"
            case .sharingDenied: "denied"
            case .sharingAuthorized: "authorized"
            @unknown default: "unknown"
        }
        HRDebugLogger.log(.airpods, "Workout share authorization: \(statusDesc)")
        
        guard shareStatus == .sharingAuthorized else {
            HRDebugLogger.warn(.airpods, "Workout share not authorized - cannot start workout session")
            HRDebugLogger.warn(.airpods, "User may need to grant workout permission in Health app")
            return
        }
        
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            session.delegate = self // Add session delegate for state changes
            
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            builder.delegate = self
            
            let startDate = Date()
            HRDebugLogger.log(.airpods, "Starting workout activity...")
            session.startActivity(with: startDate)
            
            builder.beginCollection(withStart: startDate) { [weak self] success, error in
                if success {
                    HRDebugLogger.log(.airpods, "Workout session started (enables AirPods Pro HR)")
                    HRDebugLogger.log(.airpods, "Waiting for HR data from AirPods Pro...")
                } else {
                    HRDebugLogger.error(.airpods, "Workout collection failed: \(error?.localizedDescription ?? "unknown")")
                    // Try to clean up on failure
                    self?.stopWorkoutSession()
                }
            }
            
            workoutSession = session
            workoutBuilder = builder
            HRDebugLogger.log(.airpods, "Workout session created - listening for HR data")
        } catch {
            HRDebugLogger.error(.airpods, "Could not create workout session: \(error.localizedDescription)")
        }
    }
    
    private func stopWorkoutSession() {
        guard #available(iOS 26.0, *) else { return }
        
        if let builder = workoutBuilder as? HKLiveWorkoutBuilder {
            builder.endCollection(withEnd: Date()) { _, _ in }
        }
        
        if let session = workoutSession as? HKWorkoutSession {
            session.stopActivity(with: Date())
            session.end()
        }
        
        workoutSession = nil
        workoutBuilder = nil
    }
}

// MARK: - HKWorkoutSessionDelegate (iOS 26+)

@available(iOS 26.0, *)
extension AirPodsHRProvider: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        let stateNames: [HKWorkoutSessionState: String] = [
            .notStarted: "notStarted",
            .running: "running",
            .ended: "ended",
            .paused: "paused",
            .prepared: "prepared",
            .stopped: "stopped"
        ]
        let fromName = stateNames[fromState] ?? "unknown"
        let toName = stateNames[toState] ?? "unknown"
        HRDebugLogger.log(.airpods, "Workout state: \(fromName) -> \(toName)")
        
        if toState == .running {
            HRDebugLogger.log(.airpods, "Workout running - AirPods Pro HR sensor should be active")
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        HRDebugLogger.error(.airpods, "Workout session failed: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate (iOS 26+)

@available(iOS 26.0, *)
extension AirPodsHRProvider: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        HRDebugLogger.log(.airpods, "Workout builder collected event")
    }
    
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        
        // Always log what types were collected for debugging
        let typeNames = collectedTypes.map { 
            $0.identifier.replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
        }
        HRDebugLogger.log(.airpods, "Workout collected: [\(typeNames.joined(separator: ", "))]")
        
        if collectedTypes.contains(hrType) {
            if let stats = workoutBuilder.statistics(for: hrType),
               let quantity = stats.mostRecentQuantity() {
                let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                let now = Date()
                
                HRDebugLogger.logBPM(.airpods, bpm: bpm, age: 0, source: "AirPods Pro")
                
                lastSampleDate = now
                HeartRateRouter.shared.ingestHealthKit(bpm: bpm, sourceName: "AirPods Pro", at: now)
            } else {
                HRDebugLogger.warn(.airpods, "HR type in collection but no statistics - sensor may not be reading")
            }
        }
    }
}

