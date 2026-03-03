//
//  LiveHeartRateCard.swift
//  Dojo
//

import SwiftUI
import WatchConnectivity

struct LiveHeartRateCard: View {
    @ObservedObject private var connectivityManager = PhoneConnectivityManager.shared
    @ObservedObject private var router = HeartRateRouter.shared
    @ObservedObject private var heartRateService = HeartRateService.shared
    @State private var monitoringStartTime: Date?
    @State private var currentTime = Date()
    @State private var hasLoggedTimeout = false
    @State private var lastLoggedState: String = ""  // Track last logged state to prevent spam
    
    // Timer to update current time for timeout detection
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if !SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false) {
            return AnyView(EmptyView())
        }
    return AnyView(HStack(alignment: .top, spacing: 10) {
            // Heart icon - original color when active, recolored when waiting/error
            statusHeartIcon
            
            // Two-line text content
            VStack(alignment: .leading, spacing: 2) {
                // Title row
                Text(titleText)
                    .font(Font.custom("Nunito", size: 12).weight(.semibold))
                    .foregroundColor(.fontsGray)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                // Subtitle row - different layout for active vs waiting/error
                if hasRecentHeartRateData {
                    // Active: BPM number + "bpm" text
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(round(router.currentBPM)))")
                            .font(Font.custom("Nunito", size: 24).weight(.semibold))
                            .foregroundColor(.fontsGray)
                        
                        Text("bpm")
                            .font(Font.custom("Nunito", size: 16).italic())
                            .foregroundColor(.fontsGray)
                    }
                } else {
                    // Waiting/Error: action message
                    Text(subtitleText)
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(.fontsGray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(timer) { _ in
            currentTime = Date()
            
            // Log state changes only when they actually change (prevents spam)
            let currentStateKey = computeStateKey()
            if currentStateKey != lastLoggedState {
                lastLoggedState = currentStateKey
                HRDebugLogger.log(.ui, "State: \(currentStateKey)")
            }
            
            // Track timeout error analytically (only once per session)
            if isWaitingTooLong && !hasLoggedTimeout {
                hasLoggedTimeout = true
                let practiceDetails = WatchAnalyticsManager.shared.getCurrentPracticeDetails()
                WatchAnalyticsManager.shared.trackHeartRateSession(
                    practiceTitle: practiceDetails.title,
                    practiceCategory: practiceDetails.category,
                    practiceDuration: practiceDetails.duration,
                    heartRateResults: nil,
                    error: .sessionTimeout
                )
            }
        }
        .onChange(of: connectivityManager.isLiveMode) { _, isActive in
            if isActive && monitoringStartTime == nil {
                monitoringStartTime = Date()
                hasLoggedTimeout = false
            } else if !isActive && !heartRateService.isActive {
                // Only clear if the HR service is also done — prevents Watch stopping isLiveMode
                // from resetting the timer while Fitbit/AirPods are still running
                monitoringStartTime = nil
                hasLoggedTimeout = false
            }
        }
        .onChange(of: heartRateService.isActive) { _, isActive in
            // Universal start signal — covers Fitbit and AirPods which never set isLiveMode
            if isActive && monitoringStartTime == nil {
                monitoringStartTime = Date()
                hasLoggedTimeout = false
            } else if !isActive {
                monitoringStartTime = nil
                hasLoggedTimeout = false
            }
        }
        .onChange(of: connectivityManager.lastUpdateTime) { _, _ in
            // Reset timeout flag when we receive new heart rate data
            if hasRecentHeartRateData {
                hasLoggedTimeout = false
            }
        }
        .onAppear {
            // Set start time if HR is already active when the view appears
            if (connectivityManager.isLiveMode || heartRateService.isActive) && monitoringStartTime == nil {
                monitoringStartTime = Date()
                hasLoggedTimeout = false
            }
        }
        )
    }
    
    // MARK: - Status Heart Icon
    
    private var statusHeartIcon: some View {
        // Use a dedicated view to maintain animation state across hasRecentHeartRateData changes
        // When pulsing, use original heart color; when static (error), use gray template
        PulsingHeartIcon(
            shouldPulse: shouldPulse,
            useOriginalColor: shouldPulse,  // Original color when pulsing, template when static
            templateColor: statusColor
        )
    }
    
    // MARK: - Heart Rate Data State
    
    /// Check if we're waiting too long for heart rate data (more than 15 seconds)
    private var isWaitingTooLong: Bool {
        guard let startTime = monitoringStartTime,
              connectivityManager.isLiveMode else { return false }
        
        let elapsed = currentTime.timeIntervalSince(startTime)
        return elapsed > 15 && !hasRecentHeartRateData
    }
    
    /// Check if we have recent heart rate data (within 1 minute)
    private var hasRecentHeartRateData: Bool {
        // Must have actual BPM data (not just recent timestamp)
        guard router.currentBPM > 0 else { return false }
        
        // Prefer unified router (Watch or AirPods). Fallback to phone connectivity timestamp.
        if let last = router.lastUpdate {
            return currentTime.timeIntervalSince(last) < 60
        }
        if let lastWatch = connectivityManager.lastUpdateTime {
            return currentTime.timeIntervalSince(lastWatch) < 60
        }
        return false
    }
    
    /// Active sensor currently providing data, if any.
    private var activeSensor: HeartRateRouter.Source? {
        guard hasRecentHeartRateData else { return nil }
        switch router.currentSource {
        case .none:
            return nil
        default:
            return router.currentSource
        }
    }

    /// Human readable label for the active sensor, if any.
    private var activeSensorName: String? {
        guard let sensor = activeSensor else { return nil }
        switch sensor {
        case .watch:
            return "Apple Watch"
        case .airpods:
            return "AirPods"
        case .fitbit:
            return "Fitbit"
        case .none:
            return nil
        }
    }

    /// Check if we're actively waiting for initial heart rate data
    private var isWaitingForData: Bool {
        guard let startTime = monitoringStartTime,
              connectivityManager.isLiveMode else { return false }
        
        let elapsed = currentTime.timeIntervalSince(startTime)
        return elapsed > 2 && !hasRecentHeartRateData // Give 2 seconds before showing "waiting" message
    }
    
    // MARK: - Visual States (2 colors: red, gray)
    // Red = Ready/Active (pulsing) - everything is set up or receiving data
    // Gray = Error (static) - no devices paired, user needs to take action
    
    private var statusColor: Color {
        // Only gray when truly no devices are available — Watch not paired, no AirPods, no Fitbit app
        if connectivityManager.heartRateStatus == .notPaired
            && !hasRecentHeartRateData
            && !FitbitDetector.isFitbitAppInstalled {
            return .gray
        }
        
        // Everything else is red (ready or active)
        return .red
    }
    
    /// Should the heart icon pulse? Yes for ready/active states, no for errors.
    private var shouldPulse: Bool {
        // Pulse when active (receiving data) or ready (waiting for audio)
        // Don't pulse for gray (error) states
        statusColor != .gray && (hasRecentHeartRateData || heartRateService.isActive || connectivityManager.isLiveMode)
    }
    
    // MARK: - State Key (for logging deduplication)
    
    /// Compute a state key that only changes when the displayed state changes.
    /// Used to prevent logging the same state repeatedly.
    private func computeStateKey() -> String {
        if hasRecentHeartRateData {
            return "ACTIVE-\(Int(round(router.currentBPM)))"
        }
        if connectivityManager.heartRateStatus == .notPaired {
            return "NO_DEVICES"
        }
        if connectivityManager.isLiveMode || heartRateService.isActive {
            if elapsedSeconds < promptDelaySeconds {
                return "CONNECTING"
            }
            if let device = waitingDeviceName {
                return "WAITING_FOR_\(device.uppercased().replacingOccurrences(of: " ", with: "_"))"
            }
            return "FAILED_TO_CONNECT"
        }
        return "IDLE"
    }
    
    // MARK: - Two-Line Text Content
    
    /// Determine which device we're waiting for (for messaging).
    ///
    /// Priority (most → least reliable real-time signal):
    /// 1. AirPods: physically connected right now
    /// 2. Watch reachable: Watch app is running in the foreground
    /// 3. Watch paired: prompt user to open the Watch app
    /// 4. Fitbit: bonded device or app installed (Fitbit-only users — no Watch)
    ///
    /// History (lastHRSource) is intentionally NOT used here. It created a stuck state:
    /// once a device provided HR, the prompt never changed even when the user switched
    /// devices. Since there is no iOS API to detect which device is physically on the
    /// user's wrist, the cleanest approach is to always prompt Watch users to open the
    /// Watch app (step 3), and let the first-to-win router handle data correctly
    /// regardless of which prompt is showing. Fitbit-only users (no Watch) are not
    /// affected because watchPaired is false for them.
    private var waitingDeviceName: String? {
        let watchPaired  = connectivityManager.isWatchConnected || WatchPairingManager.shared.isWatchPaired

        // 1. AirPods physically connected right now
        if AirPodsHRProvider.areAirPodsProConnected() { return "AirPods" }

        // 2. Watch app actively running in the foreground — data is imminent
        if heartRateService.isWatchReachable { return "Apple Watch" }

        // 3. Both Watch (paired) and Fitbit (BLE-connected) are present but neither is
        //    actively sending data yet. Show a combined message so the user knows both
        //    options are available and what to do for each.
        if watchPaired && heartRateService.isFitbitBLEConnected { return "Both" }

        // 4. Watch paired, no Fitbit — prompt user to open the Watch app.
        if watchPaired { return "Apple Watch" }

        // 4. Fitbit — user has no Watch
        if SharedUserStorage.retrieve(forKey: .fitbitDeviceUUID, as: String.self) != nil { return "Fitbit" }
        if FitbitDetector.isFitbitAppInstalled { return "Fitbit" }

        return nil
    }

    /// Seconds to wait before showing device-specific guidance.
    /// Fitbit users with a previously bonded device see the action prompt sooner —
    /// they know their device and just need the reminder.
    private var promptDelaySeconds: TimeInterval {
        let device = waitingDeviceName
        // AirPods: show "Play audio to begin" immediately — it's accurate and actionable
        // the moment they're detected, and HR data often arrives within seconds.
        if device == "AirPods" { return 0.0 }
        guard device == "Fitbit" || device == "Both" else { return 5.0 }
        let hasBonded = SharedUserStorage.retrieve(forKey: .fitbitDeviceUUID, as: String.self) != nil
        return hasBonded ? 2.0 : 5.0
    }
    
    /// Title line - what's happening
    private var titleText: String {
        // Active: show device source
        if hasRecentHeartRateData {
            return "Heart Rate from \(activeSensorName ?? "Device")"
        }
        
        // Error: no devices available — only when Watch not paired AND no Fitbit app
        if connectivityManager.heartRateStatus == .notPaired && !FitbitDetector.isFitbitAppInstalled {
            return "No devices found"
        }
        
        // Session active - phased titles
        if connectivityManager.isLiveMode || heartRateService.isActive {
            if elapsedSeconds < promptDelaySeconds {
                return "Device Connecting"
            }
            if let device = waitingDeviceName {
                if device == "Both" { return "Multiple HR Devices Detected" }
                return "Heart Rate from \(device)"
            }
            return "Failed to Connect"
        }
        
        // Idle
        return "Heart Rate"
    }
    
    /// Elapsed seconds since monitoring started (for phased messages)
    private var elapsedSeconds: TimeInterval {
        guard let startTime = monitoringStartTime else { return 0 }
        return currentTime.timeIntervalSince(startTime)
    }
    
    /// Subtitle line - phased messages based on timing
    private var subtitleText: String {
        // Active: show BPM (handled separately in body with HStack)
        if hasRecentHeartRateData {
            return "\(Int(round(router.currentBPM))) bpm"
        }
        
        // Error: no devices available — only when Watch not paired AND no Fitbit app
        if connectivityManager.heartRateStatus == .notPaired && !FitbitDetector.isFitbitAppInstalled {
            return "Pair AirPods Pro 2 or Apple Watch"
        }
        
        // Session active - show phased messages
        if connectivityManager.isLiveMode || heartRateService.isActive {
            if elapsedSeconds < promptDelaySeconds {
                return "Please wait..."
            }
            if let device = waitingDeviceName {
                switch device {
                case "Apple Watch":
                    return "Open Dojo Watch app"
                case "Fitbit":
                    let deviceName = SharedUserStorage.retrieve(forKey: .fitbitDeviceName, as: String.self) ?? "Fitbit"
                    return "Swipe down on \(deviceName) → tap HR on Equipment"
                case "Both":
                    let fitbitName = SharedUserStorage.retrieve(forKey: .fitbitDeviceName, as: String.self) ?? "Fitbit"
                    return "Open Watch app, or swipe down on \(fitbitName)"
                default:
                    return "Play audio to begin"  // AirPods
                }
            }
            return "Check device connection"
        }
        
        // Idle: CTA to start
        return "Start a practice to begin"
    }
}

// MARK: - Pulsing Heart Icon

/// Dedicated view for the pulsing heart animation.
/// Maintains its own animation state so it persists across parent view updates.
private struct PulsingHeartIcon: View {
    let shouldPulse: Bool
    let useOriginalColor: Bool
    let templateColor: Color
    
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        heartImage
            .scaleEffect(scale)
            .onAppear {
                if shouldPulse {
                    startPulsing()
                }
            }
            .onChange(of: shouldPulse) { _, newValue in
                if newValue {
                    startPulsing()
                } else {
                    stopPulsing()
                }
            }
    }
    
    @ViewBuilder
    private var heartImage: some View {
        if useOriginalColor {
            // Active state: use original heart color
            Image("iconHeart")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        } else {
            // Waiting/error states: recolor heart
            Image("iconHeart")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(templateColor)
        }
    }
    
    private func startPulsing() {
        // Use withAnimation to start a continuous repeating animation
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            scale = 1.15
        }
    }
    
    private func stopPulsing() {
        // Smoothly return to normal scale
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1.0
        }
    }
}

// MARK: - Preview

struct LiveHeartRateCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Active state - Watch
                PreviewPlayerContainer {
                    PreviewHeartRateCard(
                        useOriginalColor: true,
                        title: "Heart Rate from Apple Watch",
                        bpmNumber: 72,
                        isAnimated: true
                    )
                }
                
                // Active state - AirPods
                PreviewPlayerContainer {
                    PreviewHeartRateCard(
                        useOriginalColor: true,
                        title: "Heart Rate from AirPods",
                        bpmNumber: 65,
                        isAnimated: true
                    )
                }
                
                // Connecting state (0-5s)
                PreviewPlayerContainer {
                    PreviewHeartRateCard(
                        useOriginalColor: false,
                        statusColor: .red,
                        title: "Device Connecting",
                        actionMessage: "Please wait...",
                        isAnimated: true
                    )
                }
                
                // Waiting for AirPods (5s+, AirPods connected but needs audio)
                PreviewPlayerContainer {
                    PreviewHeartRateCard(
                        useOriginalColor: false,
                        statusColor: .red,
                        title: "Heart Rate from AirPods",
                        actionMessage: "Play audio to begin",
                        isAnimated: true
                    )
                }
                
                // Waiting for Watch (5s+, Watch paired)
                PreviewPlayerContainer {
                    PreviewHeartRateCard(
                        useOriginalColor: false,
                        statusColor: .red,
                        title: "Heart Rate from Apple Watch",
                        actionMessage: "Open Dojo Watch app",
                        isAnimated: true
                    )
                }
                
                // Failed to connect (no devices detected)
                PreviewPlayerContainer {
                    PreviewHeartRateCard(
                        useOriginalColor: false,
                        statusColor: .gray,
                        title: "Failed to Connect",
                        actionMessage: "Check device connection",
                        isAnimated: false
                    )
                }
                
                // Error: no devices paired
                PreviewPlayerContainer {
                    PreviewHeartRateCard(
                        useOriginalColor: false,
                        statusColor: .gray,
                        title: "No devices found",
                        actionMessage: "Pair AirPods Pro 2 or Apple Watch",
                        isAnimated: false
                    )
                }
            }
            .padding(16)
        }
        .background(Color.backgroundDarkPurple)
        .previewDisplayName("Heart Rate States")
    }
}

// MARK: - Preview Player Container (mimics PlayerView container)

private struct PreviewPlayerContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            // Simulated progress bar area
            HStack(spacing: 12) {
                Text("00:00")
                    .font(Font.custom("Nunito", size: 14).weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 2)
                
                Text("10:00")
                    .font(Font.custom("Nunito", size: 14).weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            // Simulated play controls
            HStack(spacing: 40) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 46))
                    .foregroundColor(.white)
                
                Image(systemName: "goforward.15")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Section divider
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(height: 1)
            
            // Heart rate card content
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.00),
                    Gradient.Stop(color: Color(red: 0.08, green: 0.08, blue: 0.14), location: 1.00),
                ],
                startPoint: UnitPoint(x: 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 1)
            )
            .opacity(0.95)
        )
        .cornerRadius(18)
    }
}

// MARK: - Preview Helper

private struct PreviewHeartRateCard: View {
    let useOriginalColor: Bool
    var statusColor: Color = .white
    let title: String
    var bpmNumber: Int? = nil
    var actionMessage: String? = nil
    let isAnimated: Bool
    
    @State private var animating = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Heart icon
            if useOriginalColor {
                Image("iconHeart")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .scaleEffect(animating ? 1.15 : 1.0)
            } else {
                Image("iconHeart")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(statusColor)
                    .scaleEffect(animating ? 1.15 : 1.0)
            }
            
            // Two-line text
            VStack(alignment: .leading, spacing: 2) {
                // Title row
                Text(title)
                    .font(Font.custom("Nunito", size: 12).weight(.semibold))
                    .foregroundColor(.fontsGray)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                // Subtitle row
                if let bpm = bpmNumber {
                    // Active: BPM number + "bpm" text
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(bpm)")
                            .font(Font.custom("Nunito", size: 24).weight(.semibold))
                            .foregroundColor(.fontsGray)
                        
                        Text("bpm")
                            .font(Font.custom("Nunito", size: 16).italic())
                            .foregroundColor(.fontsGray)
                    }
                } else if let message = actionMessage {
                    // Waiting/Error: action message
                    Text(message)
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(.fontsGray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if isAnimated {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
        }
    }
}