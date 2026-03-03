import Foundation
import Combine
import WatchConnectivity

/// Unified heart rate service - single entry point for all HR functionality.
/// Manages AirPods and Watch providers for LIVE heart rate only.
/// HeartRateRouter arbitrates which source to use based on data freshness.
final class HeartRateService: ObservableObject {
    static let shared = HeartRateService()
    
    // MARK: - Status
    
    enum Status: Equatable {
        case idle
        case starting
        case active(source: String)
        case waiting
        case error(String)
        
        var description: String {
            switch self {
            case .idle: return "idle"
            case .starting: return "starting"
            case .active(let source): return "active(\(source))"
            case .waiting: return "waiting"
            case .error(let msg): return "error(\(msg))"
            }
        }
    }
    
    // MARK: - Published State
    
    @Published private(set) var status: Status = .idle
    @Published private(set) var isActive: Bool = false
    @Published private(set) var activeProvider: String?
    @Published private(set) var airPodsAudioStatus: String = ""
    @Published private(set) var areAirPodsProActive: Bool = false
    @Published private(set) var isWatchReachable: Bool = false
    @Published private(set) var isWatchPaired: Bool = false

    /// True when FitbitHRProvider has an active BLE connection to the Charge 6 this session.
    /// Computed on the fly — the 1-second timer in LiveHeartRateCard causes re-evaluation.
    var isFitbitBLEConnected: Bool {
        providers.first { $0 is FitbitHRProvider }?.isBLEConnected ?? false
    }
    
    // MARK: - Providers (Live HR only - no passive listening)
    
    private lazy var providers: [HeartRateProvider] = [
        AirPodsHRProvider(),  // Starts first - simpler setup
        WatchHRProvider(),    // Starts simultaneously - fallback if AirPods unavailable
        FitbitHRProvider()    // BLE provider — isAvailable = false unless device UUID is stored
    ]
    
    // MARK: - Private State
    
    private var activeSessionId: String?
    private var freshnessTimer: Timer?
    private var routerSubscription: AnyCancellable?
    private let router = HeartRateRouter.shared
    
    // MARK: - Feature Flag
    
    private var isFeatureEnabled: Bool {
        SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false)
    }
    
    // MARK: - Initialization
    
    private init() {
        // Subscribe to router changes to track active source
        routerSubscription = router.$currentSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                self?.handleSourceChange(source)
            }
    }
    
    // MARK: - Public API
    
    /// Start heart rate monitoring for the given session.
    /// All available providers start simultaneously - the router arbitrates.
    func start(sessionId: String) {
        guard isFeatureEnabled else {
            HRDebugLogger.warn(.service, "HR feature disabled - ignoring start")
            return
        }
        
        // If already running with same session, just ensure state is correct
        if activeSessionId == sessionId && isActive {
            HRDebugLogger.log(.service, "Already running for session \(sessionId)")
            return
        }
        
        // Stop any existing session first
        if let existingSession = activeSessionId, existingSession != sessionId {
            HRDebugLogger.log(.service, "Stopping stale session \(existingSession)")
            stopInternal(sessionId: existingSession)
        }
        
        activeSessionId = sessionId
        isActive = true
        updateStatus(.starting)
        
        // Check AirPods audio connection status (only log if relevant)
        checkAirPodsStatus()
        
        // Check Watch reachability - if not reachable, user may need to open Watch app
        checkWatchReachability()
        
        HRDebugLogger.log(.service, "Starting session \(sessionId)")
        
        // Start router session
        router.startSession()
        
        // Log all provider availability with reasons for skipped ones
        for provider in providers {
            let name = String(describing: type(of: provider))
            if provider.isAvailable {
                HRDebugLogger.log(.service, "Provider \(name) — available ✓")
            } else {
                let reason: String
                switch provider {
                case is FitbitHRProvider:
                    reason = "Fitbit app not installed or HR monitoring disabled"
                default:
                    reason = "isAvailable=false"
                }
                HRDebugLogger.warn(.service, "Provider \(name) — SKIPPED: \(reason)")
            }
        }

        // Start ALL available providers simultaneously
        for provider in providers where provider.isAvailable {
            provider.start(sessionId: sessionId)
        }
        
        // Start freshness monitoring
        startFreshnessMonitor()
    }
    
    /// Stop heart rate monitoring.
    func stop(sessionId: String) {
        guard activeSessionId == sessionId else {
            HRDebugLogger.log(.service, "Ignoring stop for mismatched session \(sessionId)")
            return
        }
        
        stopInternal(sessionId: sessionId)
    }
    
    /// Force stop regardless of session ID.
    func forceStop() {
        if let session = activeSessionId {
            stopInternal(sessionId: session)
        }
    }
    
    // MARK: - Private Methods
    
    private func stopInternal(sessionId: String) {
        HRDebugLogger.log(.service, "Stopping session \(sessionId)")
        
        // Stop all providers
        for provider in providers {
            provider.stop(sessionId: sessionId)
        }
        
        // Stop router session
        router.endSession()
        
        // Stop freshness monitoring
        freshnessTimer?.invalidate()
        freshnessTimer = nil
        
        // Persist the active source so the next session's UI can show the right hint.
        // Only save when a source actually provided data — ignore idle/none sessions.
        let lastSource: String?
        switch router.currentSource {
        case .watch:   lastSource = "watch"
        case .airpods: lastSource = "airpods"
        case .fitbit:  lastSource = "fitbit"
        case .none:    lastSource = nil
        }
        if let src = lastSource {
            SharedUserStorage.save(value: src, forKey: .lastHRSource)
            HRDebugLogger.log(.service, "Last HR source saved: \(src)")
        }

        // Reset state
        activeSessionId = nil
        isActive = false
        activeProvider = nil
        updateStatus(.idle)
        
        HRDebugLogger.log(.service, "Session stopped")
    }
    
    private func startFreshnessMonitor() {
        freshnessTimer?.invalidate()
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkFreshness()
        }
    }
    
    private func checkFreshness() {
        guard isActive else { return }
        
        let currentBPM = router.currentBPM
        let lastUpdate = router.lastUpdate
        let source = router.currentSource
        
        // Check if data is recent (lastUpdate is throttled at 1Hz, so allow some slack)
        let isFresh = lastUpdate.map { Date().timeIntervalSince($0) < 15 } ?? false
        
        // Trust the router's currentSource as the primary indicator:
        // - If source != .none, the router is actively receiving from that source
        // - Only fall back to freshness check when source is none
        if source != .none && currentBPM > 0 {
            updateStatus(.active(source: source.rawValue))
        } else if currentBPM > 0 && isFresh {
            // Source might be stale but we have recent data
            updateStatus(.active(source: "Unknown"))
        } else if status != .starting {
            updateStatus(.waiting)
        }
    }
    
    private func handleSourceChange(_ source: HeartRateRouter.Source) {
        guard isActive else { return }
        
        let previousProvider = activeProvider
        activeProvider = source == .none ? nil : source.rawValue
        
        if let prev = previousProvider, let current = activeProvider, prev != current {
            HRDebugLogger.logSourceSwitch(from: prev, to: current)
        }
        
        if source != .none {
            updateStatus(.active(source: source.rawValue))
        }
    }
    
    private func updateStatus(_ newStatus: Status) {
        guard status != newStatus else { return }
        
        let oldDescription = status.description
        status = newStatus
        
        HRDebugLogger.logStatus(.service, from: oldDescription, to: newStatus.description)
    }
    
    /// Check if AirPods Pro are connected (not just active audio).
    /// Note: AirPods may be connected to another device and will auto-switch when audio plays.
    private func checkAirPodsStatus() {
        airPodsAudioStatus = AirPodsHRProvider.checkAirPodsAudioConnection()
        areAirPodsProActive = AirPodsHRProvider.areAirPodsProActiveAudioOutput
        
        // Only log when we positively detect AirPods
        // Don't log "not detected" - they might be on another device and will auto-switch
        let airPodsProConnected = AirPodsHRProvider.areAirPodsProConnected()
        
        if airPodsProConnected {
            if areAirPodsProActive {
                HRDebugLogger.log(.service, "AirPods Pro connected & active ✓")
            } else {
                HRDebugLogger.log(.service, "AirPods Pro connected - HR activates when audio plays")
            }
        }
        // Don't log "not detected" - AirPods might be on another device and will auto-switch
    }
    
    /// Recheck AirPods status (e.g., after audio starts playing).
    func recheckAirPodsStatus() {
        checkAirPodsStatus()
    }
    
    /// Check Watch reachability - only log positive confirmations.
    /// Don't log "not reachable" warnings as it confuses users who have AirPods.
    private func checkWatchReachability() {
        let session = WCSession.default
        isWatchPaired = WatchPairingManager.shared.isWatchPaired
        isWatchReachable = session.isReachable
        
        // Only log positive confirmations - avoid confusing warnings
        if isWatchPaired && isWatchReachable {
            HRDebugLogger.log(.service, "Watch paired and reachable ✓")
        }
    }
}

// MARK: - Combine Publisher

extension HeartRateService {
    /// Publisher for status changes.
    var statusPublisher: AnyPublisher<Status, Never> {
        $status.eraseToAnyPublisher()
    }
}

