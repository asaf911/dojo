import Foundation
import Combine

/// Arbitrates among multiple heart rate sources (Watch, AirPods) and
/// publishes a unified, smoothed BPM at ≤ 1 Hz.
/// 
/// Priority Logic:
/// - Both providers start simultaneously (AirPods is simpler, Watch is fallback)
/// - If BOTH have fresh data: prefer Watch (better accuracy)
/// - If only one has fresh data: use that one
final class HeartRateRouter: ObservableObject {
    static let shared = HeartRateRouter()

    enum Source: String {
        case none = "None"
        case watch = "Apple Watch"
        case airpods = "AirPods"
        case fitbit = "Fitbit"
    }

    // Published unified stream
    @Published private(set) var currentBPM: Double = 0
    @Published private(set) var currentSource: Source = .none
    @Published private(set) var lastUpdate: Date?

    struct Snapshot {
        let currentSource: Source
        let availableSources: [String]
        let preferredSource: Source
        let lastKnownBPM: Double?
        let firstSampleAt: Date?
        let firstSampleLatencyMs: Double?
        let hasSwitchedSource: Bool
    }

    // Freshness thresholds
    let freshnessSeconds: TimeInterval = 30
    private let switchIfStaleSeconds: TimeInterval = 15
    private let switchBackHysteresisSeconds: TimeInterval = 10

    // Smoothing
    private let emaAlpha: Double = 0.3
    private var emaValue: Double = 0
    private var hasEma = false

    // Outlier rejection
    private let maxJumpBPM: Double = 30
    private var lastRawBPM: Double = 0
    private var lastRawAt: Date?

    // Throttle publisher to ≤ 1 Hz
    private var throttleTimer: Timer?
    private var pendingPublish: (bpm: Double, at: Date, source: Source)?

    // Source states
    private var lastWatch: (bpm: Double, at: Date)?
    private var lastHK: (bpm: Double, at: Date, srcLabel: String)?
    private var lastFitbit: (bpm: Double, at: Date)?
    private var lastSwitchAt: Date = .distantPast
    private var firstSampleAt: Date?
    private var sessionStartedAt: Date?
    private var hasSwitchedSource = false
    private var lastLoggedSourceSwitch: (from: Source, to: Source)?  // Prevent duplicate logs

    // First-to-win: once a source sends data, it's locked for the session
    private var lockedSource: Source = .none

    private init() {
        startThrottle()
    }

    func startSession() {
        sessionStartedAt = Date()
        reset()
        startThrottle()
        HRDebugLogger.log(.router, "Session started")
    }

    func endSession() {
        throttleTimer?.invalidate()
        throttleTimer = nil
        HRDebugLogger.log(.router, "Session ended")
    }

    func ingestWatch(bpm: Double, at: Date) {
        // Ignore data if no session is active
        guard sessionStartedAt != nil else {
            return
        }
        
        let age = Date().timeIntervalSince(at)
        HRDebugLogger.logBPM(.router, bpm: bpm, age: age, source: "Watch")
        lastWatch = (bpm, at)
        route()
    }

    func ingestHealthKit(bpm: Double, sourceName: String?, at: Date) {
        // Ignore data if no session is active
        guard sessionStartedAt != nil else {
            return
        }
        
        let age = Date().timeIntervalSince(at)
        HRDebugLogger.logBPM(.router, bpm: bpm, age: age, source: sourceName)
        lastHK = (bpm, at, sourceName ?? "HealthKit")
        route()
    }

    func ingestFitbit(bpm: Double, at: Date) {
        guard sessionStartedAt != nil else { return }
        let age = Date().timeIntervalSince(at)
        HRDebugLogger.logBPM(.router, bpm: bpm, age: age, source: "Fitbit")
        lastFitbit = (bpm, at)
        route()
    }

    private func route() {
        let now = Date()

        // Compute freshness for each source
        let watchFresh = lastWatch.map { now.timeIntervalSince($0.at) <= freshnessSeconds } ?? false
        let airpodsFresh = lastHK.map { now.timeIntervalSince($0.at) <= freshnessSeconds } ?? false
        let fitbitFresh = lastFitbit.map { now.timeIntervalSince($0.at) <= freshnessSeconds } ?? false

        // FIRST-TO-WIN LOGIC:
        // Once a source sends data, it's locked for the entire session.
        // We only accept a new source if lockedSource is .none or stale.
        
        // Check if locked source is still fresh
        let lockedIsFresh: Bool
        switch lockedSource {
        case .watch: lockedIsFresh = watchFresh
        case .airpods: lockedIsFresh = airpodsFresh
        case .fitbit: lockedIsFresh = fitbitFresh
        case .none: lockedIsFresh = false
        }
        
        // If locked source has fresh data, stay with it
        if lockedSource != .none && lockedIsFresh {
            // Ensure currentSource matches locked source
            if currentSource != lockedSource {
                let fromSource = currentSource
                DispatchQueue.main.async { [weak self] in
                    self?.currentSource = self?.lockedSource ?? .none
                }
                if lastLoggedSourceSwitch?.from != fromSource || lastLoggedSourceSwitch?.to != lockedSource {
                    lastLoggedSourceSwitch = (from: fromSource, to: lockedSource)
                    HRDebugLogger.logSourceSwitch(from: fromSource.rawValue, to: lockedSource.rawValue)
                }
            }
        } else {
            // No locked source or locked source is stale - accept first fresh source
            var newSource: Source = .none
            
            // Check which source has fresh data (first one wins)
            if airpodsFresh {
                newSource = .airpods
            } else if watchFresh {
                newSource = .watch
            } else if fitbitFresh {
                newSource = .fitbit
            }
            
            // Lock and switch to new source if available
            if newSource != .none && newSource != lockedSource {
                let fromSource = currentSource
                lockedSource = newSource
                lastSwitchAt = now
                
                if firstSampleAt == nil {
                    firstSampleAt = now
                } else if currentSource != .none {
                    hasSwitchedSource = true
                }
                hasEma = false
                
                DispatchQueue.main.async { [weak self] in
                    self?.currentSource = newSource
                }
                
                // Log the lock
                if lastLoggedSourceSwitch?.from != fromSource || lastLoggedSourceSwitch?.to != newSource {
                    lastLoggedSourceSwitch = (from: fromSource, to: newSource)
                    HRDebugLogger.logSourceSwitch(from: fromSource.rawValue, to: newSource.rawValue)
                    HRDebugLogger.log(.router, "Source locked: \(newSource.rawValue) (first to send wins)")
                }
            }
        }

        // Select sample based on current source (use lockedSource for consistency)
        let activeSource = lockedSource != .none ? lockedSource : currentSource
        var sample: (bpm: Double, at: Date)?
        switch activeSource {
        case .watch:
            sample = lastWatch
        case .airpods:
            if let hk = lastHK { sample = (hk.bpm, hk.at) }
        case .fitbit:
            sample = lastFitbit
        case .none:
            sample = nil
        }

        guard let s = sample else { return }
        publishSmoothed(bpm: s.bpm, at: s.at)
    }

    private func publishSmoothed(bpm: Double, at: Date) {
        // Outlier filter
        if let lastAt = lastRawAt {
            let dt = at.timeIntervalSince(lastAt)
            if dt <= 2.5 && abs(bpm - lastRawBPM) > maxJumpBPM {
                // wait for confirmation; drop this sample
                HRDebugLogger.warn(.router, "Dropped outlier bpm=\(Int(bpm)) dt=\(String(format: "%.1f", dt))s")
                return
            }
        }
        lastRawBPM = bpm
        lastRawAt = at

        // EMA smoothing
        if !hasEma {
            emaValue = bpm
            hasEma = true
        } else {
            emaValue = emaAlpha * bpm + (1 - emaAlpha) * emaValue
        }

        // Enqueue for throttled publish (≤1 Hz steady-state)
        pendingPublish = (emaValue, at, currentSource)

        // First reading: publish immediately instead of waiting up to 1s for the timer tick.
        // This removes the visible "connecting → showing BPM" lag on initial lock.
        if currentBPM == 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self, let pending = self.pendingPublish else { return }
                self.pendingPublish = nil
                self.currentBPM = pending.bpm
                self.lastUpdate = pending.at
            }
        }
    }

    private func startThrottle() {
        throttleTimer?.invalidate()
        throttleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let pending = self.pendingPublish else { return }
            self.pendingPublish = nil
            DispatchQueue.main.async {
                self.currentBPM = pending.bpm
                self.lastUpdate = pending.at
                // keep self.currentSource as set in route()
            }
        }
    }

    private func reset() {
        lastWatch = nil
        lastHK = nil
        lastFitbit = nil
        // Dispatch published property updates to main thread
        DispatchQueue.main.async { [weak self] in
            self?.currentBPM = 0
            self?.currentSource = .none
            self?.lastUpdate = nil
        }
        hasEma = false
        emaValue = 0
        lastRawBPM = 0
        lastRawAt = nil
        pendingPublish = nil
        firstSampleAt = nil
        hasSwitchedSource = false
        lastLoggedSourceSwitch = nil  // Reset duplicate log tracker
        lockedSource = .none  // Reset source lock for new session
    }

    func snapshot() -> Snapshot? {
        let sources = [lastWatch != nil ? "watch" : nil, lastHK != nil ? "airpods" : nil, lastFitbit != nil ? "fitbit" : nil].compactMap { $0 }
        let preferred: Source = lastWatch != nil ? .watch : (lastHK != nil ? .airpods : (lastFitbit != nil ? .fitbit : .none))
        let latency: Double?
        if let start = sessionStartedAt, let first = firstSampleAt {
            latency = first.timeIntervalSince(start) * 1000
        } else {
            latency = nil
        }
        return Snapshot(
            currentSource: currentSource,
            availableSources: sources,
            preferredSource: preferred,
            lastKnownBPM: currentBPM > 0 ? currentBPM : nil,
            firstSampleAt: firstSampleAt,
            firstSampleLatencyMs: latency,
            hasSwitchedSource: hasSwitchedSource
        )
    }
}


