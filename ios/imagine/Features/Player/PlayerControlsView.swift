//
//  PlayerControlsView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-17
//
//  Unified player controls supporting both guided and timer sessions.
//

import SwiftUI

struct PlayerControlsView: View {
    // MARK: - Session Properties
    
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    var selectedFile: AudioFile?
    var sessionType: SessionType
    
    /// Observed wrapper for timer session - allows view to re-render when session state changes
    @ObservedObject var timerSessionWrapper: TimerMeditationSessionWrapper
    
    /// Convenience accessor for the actual session
    var timerSession: TimerMeditationSession? {
        timerSessionWrapper.session
    }
    
    // MARK: - Environment
    
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    // MARK: - Computed Properties
    
    /// Whether skip buttons should be shown (now enabled for all session types)
    private var showSkipButtons: Bool {
        true
    }
    
    /// Whether the controls are disabled
    private var controlsDisabled: Bool {
        sessionType == .guided && audioPlayerManager.isDownloading
    }
    
    /// Whether the session is currently playing
    private var isPlaying: Bool {
        switch sessionType {
        case .guided:
            return audioPlayerManager.isPlaying
        case .timer:
            return timerSession?.isPlaying ?? false
        }
    }
    
    /// Current time display (elapsed time for both session types)
    private var currentTimeText: String {
        switch sessionType {
        case .guided:
            return AppFunctions.formatTime(audioPlayerManager.currentTime)
        case .timer:
            return timerSession?.playerElapsedTimeDisplay ?? "00:00"
        }
    }
    
    /// Total time display
    private var totalTimeText: String {
        switch sessionType {
        case .guided:
            return AppFunctions.formatTime(audioPlayerManager.totalDuration)
        case .timer:
            return timerSession?.playerTotalTimeDisplay ?? "00:00"
        }
    }
    
    /// Progress value (elapsed time in seconds)
    private var progressValue: Double {
        switch sessionType {
        case .guided:
            return audioPlayerManager.currentTime
        case .timer:
            return (timerSession?.totalDuration ?? 0) * (timerSession?.progress ?? 0)
        }
    }
    
    /// Progress total
    private var progressTotal: Double {
        switch sessionType {
        case .guided:
            return audioPlayerManager.totalDuration
        case .timer:
            return timerSession?.totalDuration ?? 0
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            // Progress bar with elapsed time on left and total duration on right
            progressBarView
            
            // Control buttons
            controlButtonsView
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
    
    // MARK: - Progress Bar View
    
    private var progressBarView: some View {
        HStack(spacing: 12) {
            Text(currentTimeText)
                .font(
                    Font.custom("Nunito", size: 14)
                        .weight(.medium)
                )
                .kerning(0.07)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.9))
            
            // Custom gradient progress bar (full session); optional tick at practice start (00:00)
            GradientProgressBar(
                value: progressValue,
                total: progressTotal,
                practiceStartFraction: sessionType == .timer ? timerSession?.practiceStartBarFraction : nil
            )
            .frame(height: 2)
            
            Text(totalTimeText)
                .font(
                    Font.custom("Nunito", size: 14)
                        .weight(.medium)
                )
                .kerning(0.07)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 29)
    }
    
    // MARK: - Control Buttons View
    
    private var controlButtonsView: some View {
        HStack(spacing: 0) {
            // Skip backward button - guided sessions only
            if showSkipButtons {
                skipBackwardButton
            } else {
                // Empty spacer to maintain layout balance
                Spacer()
                    .frame(maxWidth: .infinity)
            }
            
            // Play/pause button centered
            playPauseButton
            
            // Skip forward button - guided sessions only
            if showSkipButtons {
                skipForwardButton
            } else {
                // Empty spacer to maintain layout balance
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Skip Backward Button
    
    private var skipBackwardButton: some View {
        HStack {
            Button(action: {
                HapticManager.shared.impact(.light)
                checkSubscriptionAndExecute {
                    performSkipBackward()
                }
            }) {
                Image(systemName: "gobackward.15")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28)
                    .foregroundColor(.white)
            }
            .buttonStyle(RoundButtonStyle(isEnabled: !controlsDisabled))
            .disabled(controlsDisabled)
            .padding(.leading, 44)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Play/Pause Button
    
    private var playPauseButton: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            togglePlayPause()
        }) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 46)
                .foregroundColor(.white)
        }
        .buttonStyle(RoundButtonStyle(isEnabled: !controlsDisabled))
        .disabled(controlsDisabled)
        .frame(width: 69)
    }
    
    // MARK: - Skip Forward Button
    
    private var skipForwardButton: some View {
        HStack {
            Spacer()
            Button(action: {
                HapticManager.shared.impact(.light)
                checkSubscriptionAndExecute {
                    performSkipForward()
                }
            }) {
                Image(systemName: "goforward.15")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28)
                    .foregroundColor(.white)
            }
            .buttonStyle(RoundButtonStyle(isEnabled: !controlsDisabled))
            .disabled(controlsDisabled)
            .padding(.trailing, 44)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Private Methods
    
    private func checkSubscriptionAndExecute(action: () -> Void) {
        if sessionType == .guided, subscriptionManager.shouldGatePlay {
            subscriptionManager.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=PlayerControlsView")
            #endif
            navigationCoordinator.subscriptionSource = .explore
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        action()
    }

    private func togglePlayPause() {
        switch sessionType {
        case .guided:
            checkSubscriptionAndExecute {
                if audioPlayerManager.isPlaying {
                    audioPlayerManager.pause()
                } else {
                    audioPlayerManager.play()
                }
            }
            
        case .timer:
            guard let timer = timerSession else { return }
            if timer.isPlaying {
                timer.pause()
            } else {
                if timer.timerManager.remainingSeconds == timer.timerManager.totalSeconds {
                    // First start
                    timer.start()
                } else {
                    // Resume
                    timer.resume()
                }
            }
        }
    }
    
    private func performSkipBackward() {
        switch sessionType {
        case .guided:
            audioPlayerManager.skipBackward()
        case .timer:
            timerSession?.skipBackward(seconds: 15)
        }
    }
    
    private func performSkipForward() {
        switch sessionType {
        case .guided:
            audioPlayerManager.skipForward()
        case .timer:
            timerSession?.skipForward(seconds: 15)
        }
    }
}

// MARK: - Custom Gradient Progress Bar

struct GradientProgressBar: View {
    let value: Double
    let total: Double
    /// 0...1 along the bar where the meditation (practice) clock starts at 00:00; drawn as a small dot on the track.
    var practiceStartFraction: CGFloat? = nil
    
    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(value / total, 1.0)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack(alignment: .leading) {
                // Background track (dark color)
                Rectangle()
                    .fill(Color(red: 0.28, green: 0.28, blue: 0.37))
                    .frame(height: 2)
                    .cornerRadius(1)
                
                // Filled portion (bright color) - everything behind the gradient
                if progress > 0 {
                    Rectangle()
                        .fill(Color(red: 0.88, green: 0.88, blue: 0.88))
                        .frame(width: max(0, w * progress - 19), height: 2)
                        .cornerRadius(1)
                }
                
                // Moving gradient section (20px wide)
                if progress > 0 {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: min(20, w * progress), height: 2)
                        .background(
                            LinearGradient(
                                stops: [
                                    Gradient.Stop(color: Color(red: 0.88, green: 0.88, blue: 0.88), location: 0.0),
                                    Gradient.Stop(color: Color(red: 0.28, green: 0.28, blue: 0.37), location: 1.0),
                                ],
                                startPoint: UnitPoint(x: 0, y: 0.5),
                                endPoint: UnitPoint(x: 1, y: 0.5)
                            )
                        )
                        .cornerRadius(1)
                        .offset(x: max(0, w * progress - 20))
                }

                // Practice start (00:00) — 2pt dot centered on the track
                if let frac = practiceStartFraction, frac > 0, frac < 1 {
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 2, height: 2)
                        .offset(x: w * frac - 1)
                        .zIndex(2)
                }
            }
        }
    }
}
