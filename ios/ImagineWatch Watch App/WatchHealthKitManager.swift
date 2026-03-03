import HealthKit
import Combine
import UserNotifications
import WatchKit

class WatchHealthKitManager: NSObject, ObservableObject {
    static let shared = WatchHealthKitManager()

    @Published var latestBPM: Double? = nil
    @Published var lastHeartRateUpdate: Date?
    @Published var statusMessage: String = "Ready"
    @Published var isMeasuringHR: Bool = false

    private let healthStore = HKHealthStore()
    
    // SIMPLIFIED: Single timer for live mode
    private var liveTimer: Timer?
    private var freshnessTimer: Timer?
    
    // Live heart rate monitoring components
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    
    // SIMPLIFIED: Binary state - live or not live
    @Published var isLiveMode: Bool = false
    
    // Constants
    private let liveInterval: TimeInterval = 10 // 10 seconds for live mode
    private let maxDataAge: TimeInterval = 45 // Clear stale data after 45 seconds

    override private init() {
        super.init()
        print("WatchHealthKitManager: 💓 Initialized simplified heart rate manager")
        // Gate HK auth - do not request on init
        startFreshnessMonitoring()
        updateStatus("Ready for heart rate monitoring")
        // Observe watch HR monitoring lifecycle
        NotificationCenter.default.addObserver(self, selector: #selector(onHRStarted), name: .watchHeartRateMonitoringStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onHRStopped), name: .watchHeartRateMonitoringStopped, object: nil)
    }
    
    // MARK: - HealthKit Authorization
    
    private func requestHealthKitAuthorization() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            print("WatchHealthKitManager: ❌ Cannot create heart rate type")
            return
        }
        
        let workoutType = HKObjectType.workoutType()
        
        // Types to read
        let typesToRead: Set<HKObjectType> = [heartRateType]
        
        // Types to share (needed for workout sessions)
        let typesToShare: Set<HKSampleType> = [workoutType, heartRateType]
        
        print("WatchHealthKitManager: 🔐 Requesting HealthKit authorization for workout sessions...")
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    print("WatchHealthKitManager: ✅ HealthKit authorization granted (including workout sharing)")
                    self?.updateStatus("HealthKit authorized")
                    self?.checkDetailedAuthorizationStatus()
                } else {
                    print("WatchHealthKitManager: ❌ HealthKit authorization failed: \(error?.localizedDescription ?? "Unknown error")")
                    self?.updateStatus("HealthKit authorization required")
                }
            }
        }
    }
    
    private func checkDetailedAuthorizationStatus() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let workoutType = HKObjectType.workoutType()
        
        let readStatus = healthStore.authorizationStatus(for: heartRateType)
        let shareWorkoutStatus = healthStore.authorizationStatus(for: workoutType)
        let shareHeartRateStatus = healthStore.authorizationStatus(for: heartRateType)
        
        print("WatchHealthKitManager: 📊 Authorization Status:")
        print("  - Heart Rate Read: \(authorizationStatusString(readStatus))")
        print("  - Workout Share: \(authorizationStatusString(shareWorkoutStatus))")
        print("  - Heart Rate Share: \(authorizationStatusString(shareHeartRateStatus))")
        
        if readStatus == .sharingAuthorized && shareWorkoutStatus == .sharingAuthorized {
            print("WatchHealthKitManager: ✅ All required permissions granted")
        } else {
            print("WatchHealthKitManager: ⚠️ Some permissions missing - workout sessions may fail")
        }
    }
    
    private func authorizationStatusString(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Determined"
        case .sharingDenied: return "Denied"
        case .sharingAuthorized: return "Authorized"
        @unknown default: return "Unknown"
        }
    }
    
    // MARK: - Simplified Heart Rate Control
    
    /// Start live heart rate monitoring with workout session (triggers actual sensor)
    func startLiveMode() {
        // Gate by feature flag
        guard WatchFeatureFlags.shared.isHRFeatureEnabled else {
            print("🧠 AI_DEBUG WatchHealthKitManager: HR feature disabled - ignoring startLiveMode")
            return
        }
        guard !isLiveMode else {
            print("WatchHealthKitManager: ⚠️ Live mode already active")
            return
        }
        
        DispatchQueue.main.async {
            self.isLiveMode = true
            self.updateStatus("Starting live heart rate monitoring...")
        }
        
        print("WatchHealthKitManager: 🟢 Starting live heart rate mode with workout session")
        
        // Ensure HealthKit authorization requested lazily
        requestHealthKitAuthorization()
        startWorkoutSession()
    }
    
    /// Stop live heart rate monitoring
    func stopLiveMode() {
        guard isLiveMode else {
            print("WatchHealthKitManager: ⚠️ Live mode not active")
            return
        }
        
        DispatchQueue.main.async {
            self.isLiveMode = false
            self.updateStatus("Heart rate monitoring stopped")
        }
        
        print("WatchHealthKitManager: 🔴 Stopping live heart rate mode")
        
        stopWorkoutSession()
        
        // Stop live timer
        liveTimer?.invalidate()
        liveTimer = nil
    }
    
    // MARK: - Data Freshness Management
    
    /// Start monitoring data freshness to clear stale readings
    private func startFreshnessMonitoring() {
        // Check freshness every 10 seconds for responsive UI
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkDataFreshness()
        }
        print("WatchHealthKitManager: 🕐 Started freshness monitoring")
    }
    
    /// Check if current heart rate data is stale and clear it if necessary
    private func checkDataFreshness() {
        guard let lastUpdate = lastHeartRateUpdate else { return }
        
        let dataAge = Date().timeIntervalSince(lastUpdate)
        
        if dataAge > maxDataAge && latestBPM != nil {
            print("WatchHealthKitManager: 🗑️ Clearing stale heart rate data (age: \(Int(dataAge))s)")
            DispatchQueue.main.async {
                self.latestBPM = nil
                self.updateStatus("No recent heart rate data")
            }
        }
    }
    
    /// Check if current data is considered fresh
    private var isDataFresh: Bool {
        guard let lastUpdate = lastHeartRateUpdate else { return false }
        let dataAge = Date().timeIntervalSince(lastUpdate)
        return dataAge <= maxDataAge
    }
    
    private func updateStatus(_ message: String) {
        DispatchQueue.main.async {
            self.statusMessage = message
            print("WatchHealthKitManager: 📱 Status: \(message)")
        }
    }

    /// Ingest BPM updates coming from external sources (e.g., WatchSensorService)
    func ingestExternalBPM(_ bpm: Double, source: String = "sensorService") {
        print("🧠 AI_DEBUG WatchHealthKitManager: ingestExternalBPM bpm=\(Int(bpm)) source=\(source)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.latestBPM = bpm
            self.lastHeartRateUpdate = Date()
            self.updateStatus("Heart rate: \(Int(bpm)) BPM")
        }
    }

    @objc private func onHRStarted() {
        DispatchQueue.main.async {
            self.isMeasuringHR = true
        }
    }

    @objc private func onHRStopped() {
        DispatchQueue.main.async {
            self.isMeasuringHR = false
        }
    }

    // MARK: - Workout Session Management
    
    private func startWorkoutSession() {
        // First check if we have the required permissions
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            print("WatchHealthKitManager: ❌ Cannot create heart rate type")
            updateStatus("Heart rate type unavailable")
            return
        }
        
        let workoutType = HKObjectType.workoutType()
        
        let readStatus = healthStore.authorizationStatus(for: heartRateType)
        let shareWorkoutStatus = healthStore.authorizationStatus(for: workoutType)
        
        print("WatchHealthKitManager: 🔍 Pre-workout permission check:")
        print("  - Heart Rate Read: \(authorizationStatusString(readStatus))")
        print("  - Workout Share: \(authorizationStatusString(shareWorkoutStatus))")
        
        if shareWorkoutStatus != .sharingAuthorized {
            print("WatchHealthKitManager: ⚠️ Workout sharing not authorized - trying fallback method")
            startFallbackHeartRateMonitoring()
            return
        }
        
        // Create workout configuration for mindfulness (triggers heart rate sensor)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody // Closest to meditation
        configuration.locationType = .indoor
        
        do {
            // Create workout session
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession?.delegate = self
            
            // Create live workout builder
            builder = workoutSession?.associatedWorkoutBuilder()
            builder?.delegate = self
            
            // Set data source for live data
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            print("WatchHealthKitManager: 🏃‍♂️ Starting workout session...")
            
            // Start the session (this will trigger heart rate sensor)
            workoutSession?.startActivity(with: Date())
            builder?.beginCollection(withStart: Date()) { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        print("WatchHealthKitManager: ✅ Workout session started - sensor should be active")
                        self?.updateStatus("Live heart rate monitoring active")
                        self?.startLiveHeartRateQuery()
                    } else {
                        print("WatchHealthKitManager: ❌ Failed to start workout session: \(error?.localizedDescription ?? "Unknown error")")
                        print("WatchHealthKitManager: 🔄 Trying fallback method...")
                        self?.startFallbackHeartRateMonitoring()
                    }
                }
            }
            
        } catch {
            print("WatchHealthKitManager: ❌ Error creating workout session: \(error.localizedDescription)")
            print("WatchHealthKitManager: 🔄 Trying fallback method...")
            startFallbackHeartRateMonitoring()
        }
    }
    
    private func startFallbackHeartRateMonitoring() {
        print("WatchHealthKitManager: 🔄 Starting fallback heart rate monitoring...")
        updateStatus("Using fallback heart rate monitoring")
        
        // Start immediate query and timer-based monitoring as fallback
        startLiveHeartRateQuery()
        
        // Also start a timer to periodically check for new data
        liveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.requestCurrentHeartRate()
        }
        
        // Request immediate reading
        requestCurrentHeartRate()
    }
    
    private func requestCurrentHeartRate() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        // Query for very recent heart rate data
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let predicate = HKQuery.predicateForSamples(withStart: oneMinuteAgo, end: now, options: .strictStartDate)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            
            if let error = error {
                print("WatchHealthKitManager: ❌ Fallback heart rate query error: \(error.localizedDescription)")
                return
            }
            
            if let sample = samples?.first as? HKQuantitySample {
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                let sampleDate = sample.startDate
                let dataAge = Date().timeIntervalSince(sampleDate)
                
                print("WatchHealthKitManager: 💓 Fallback heart rate: \(Int(bpm)) BPM (age: \(Int(dataAge))s)")
                
                DispatchQueue.main.async {
                    self?.latestBPM = bpm
                    self?.lastHeartRateUpdate = Date()
                    self?.updateStatus("Heart rate: \(Int(bpm)) BPM (fallback)")
                }
                
                self?.sendHeartRateToPhone(bpm)
            } else {
                print("WatchHealthKitManager: ⚠️ No recent heart rate data in fallback mode")
            }
        }
        
        healthStore.execute(query)
    }
    
    private func stopWorkoutSession() {
        // Stop live heart rate query
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        
        // End workout session
        workoutSession?.end()
        
        builder?.endCollection(withEnd: Date()) { success, error in
            if success {
                print("WatchHealthKitManager: ✅ Workout session ended")
            } else {
                print("WatchHealthKitManager: ⚠️ Error ending workout session: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
        
        workoutSession = nil
        builder = nil
    }
    
    private func startLiveHeartRateQuery() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            print("WatchHealthKitManager: ❌ Cannot create heart rate type for query")
            return
        }
        
        // Create anchored object query for live heart rate data
        heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in
            
            if let error = error {
                print("WatchHealthKitManager: ❌ Live heart rate query error: \(error.localizedDescription)")
                return
            }
            
            self?.processHeartRateSamples(samples)
        }
        
        // Set update handler for continuous updates
        heartRateQuery?.updateHandler = { [weak self] query, samples, deletedObjects, anchor, error in
            
            if let error = error {
                print("WatchHealthKitManager: ❌ Live heart rate update error: \(error.localizedDescription)")
                return
            }
            
            self?.processHeartRateSamples(samples)
        }
        
        // Execute the query
        if let query = heartRateQuery {
            healthStore.execute(query)
            print("WatchHealthKitManager: 📡 Started live heart rate query")
        }
    }
    
    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let heartRateSamples = samples as? [HKQuantitySample],
              let latestSample = heartRateSamples.last else {
            return
        }
        
        let bpm = latestSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let sampleDate = latestSample.startDate
        let dataAge = Date().timeIntervalSince(sampleDate)
        
        print("WatchHealthKitManager: 💓 Live heart rate: \(Int(bpm)) BPM (age: \(Int(dataAge))s)")
        
        DispatchQueue.main.async {
            self.latestBPM = bpm
            self.lastHeartRateUpdate = Date()
            self.updateStatus("Heart rate: \(Int(bpm)) BPM")
        }
        
        // Send to iPhone
        sendHeartRateToPhone(bpm)
    }
    
    /// Send heart rate data to iPhone
    private func sendHeartRateToPhone(_ bpm: Double) {
        WatchConnectivityManager.shared.sendHeartRateUpdate(bpm)
    }
    
    // MARK: - Legacy Compatibility
    
    /// DEPRECATED: Use startLiveMode() instead
    func startMonitoring() {
        print("WatchHealthKitManager: ⚠️ Using deprecated startMonitoring - use startLiveMode()")
        startLiveMode()
    }
    
    /// DEPRECATED: Use stopLiveMode() instead
    func stopMonitoring() {
        print("WatchHealthKitManager: ⚠️ Using deprecated stopMonitoring - use stopLiveMode()")
        stopLiveMode()
    }
    
    /// DEPRECATED: No longer needed with simplified system
    func startIntensiveMonitoring() {
        print("WatchHealthKitManager: ⚠️ Using deprecated startIntensiveMonitoring - use startLiveMode()")
        startLiveMode()
    }
    
    /// DEPRECATED: No longer needed with simplified system
    func startBackgroundMonitoring() {
        print("WatchHealthKitManager: ⚠️ Using deprecated startBackgroundMonitoring - now handled automatically")
    }
    
    /// DEPRECATED: Use stopLiveMode() instead
    func stopAllMonitoring() {
        print("WatchHealthKitManager: ⚠️ Using deprecated stopAllMonitoring - use stopLiveMode()")
        stopLiveMode()
    }
    
    deinit {
        liveTimer?.invalidate()
        freshnessTimer?.invalidate()
        
        // Clean up workout session if still active
        if let session = workoutSession {
            session.end()
        }
        
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchHealthKitManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            switch toState {
            case .running:
                print("WatchHealthKitManager: ✅ Workout session is running - heart rate sensor active")
                self.updateStatus("Heart rate sensor active")
            case .ended:
                print("WatchHealthKitManager: 🛑 Workout session ended")
                self.updateStatus("Heart rate monitoring stopped")
            case .paused:
                print("WatchHealthKitManager: ⏸️ Workout session paused")
            case .prepared:
                print("WatchHealthKitManager: 🔄 Workout session prepared")
            case .notStarted:
                print("WatchHealthKitManager: ⚪ Workout session not started")
            case .stopped:
                print("WatchHealthKitManager: 🛑 Workout session stopped")
            @unknown default:
                print("WatchHealthKitManager: ❓ Unknown workout session state")
            }
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("WatchHealthKitManager: ❌ Workout session failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.updateStatus("Heart rate monitoring failed")
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchHealthKitManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // This delegate method is called when new data is collected
        // Heart rate data will be handled by our HKAnchoredObjectQuery
        print("WatchHealthKitManager: 📊 Workout builder collected data for types: \(collectedTypes)")
    }
    
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}



