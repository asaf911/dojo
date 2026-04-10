//
//  MeditationSessionTimer.swift
//  Dojo
//
//  Countdown timer for custom (timer) meditations: tick, milestones, silent keep-alive,
//  and session completion hooks. Used by TimerMeditationSession and app lifecycle.
//

import SwiftUI
import Combine
import AVFoundation

class MeditationSessionTimer: ObservableObject {
    // Static shared instance for global access
    static var shared: MeditationSessionTimer?
    
    @Published var totalSeconds: Int
    @Published var remainingSeconds: Int
    @Published var isRunning: Bool = false
    @Published var hasReached75Percent: Bool = false

    var onSessionComplete: (() -> Void)?

    private var sessionStartDate: Date?
    private let practiceID = "meditationSession" // Meditation session identifier.
    private var completionLogs: [(threshold: Double, logged: Bool, eventName: String)] = []
    private var contentDetails: String = ""
    private var timerCancellable: AnyCancellable?
    // Track whether the session actually completed to gate post-practice AI message
    private var didCompleteSession: Bool = false

    // Silent audio to keep timer alive.
    private let silentAudioPlayer = SilentAudioPlayer()
    
    // Background sound analytics properties.
    var backgroundSoundUsed: Bool = false
    var backgroundSoundName: String = ""
    
    // Binaural beat analytics properties.
    var binauralBeatUsed: Bool = false
    var binauralBeatName: String = ""
    var binauralBeatId: String = ""
    
    // Cue settings for this session.
    private let cueSettings: [CueSetting]
    
    // Session metadata (from AI or user)
    var sessionTitle: String?
    var sessionDescription: String?

    init(totalSeconds: Int, cueSettings: [CueSetting] = [], title: String? = nil, description: String? = nil) {
        self.totalSeconds = totalSeconds
        self.remainingSeconds = totalSeconds
        self.cueSettings = cueSettings
        self.sessionTitle = title
        self.sessionDescription = description
    }

    public var currentProgress: Double {
        totalDuration - Double(remainingSeconds)
    }
    public var totalDuration: Double {
        Double(totalSeconds)
    }
    
    // MARK: - Skip/Seek Support
    
    /// Sets the remaining seconds directly, clamped to valid range.
    /// Used by TimerMeditationSession for skip forward/backward.
    func setRemainingSeconds(_ seconds: Int) {
        remainingSeconds = max(0, min(totalSeconds, seconds))
    }
    
    /// Checks completion rates after a seek operation.
    /// This ensures progress events (25%, 50%, 75%) are logged if we skipped past them.
    func checkCompletionRatesAfterSeek() {
        checkCompletionRates()
        
        // Also update hasReached75Percent if we seeked past it
        let completionRate = currentProgress / totalDuration
        if completionRate >= 0.75 && !hasReached75Percent {
            hasReached75Percent = true
        }
    }

    // MARK: - Start / Pause / End

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Audio session is activated by AppAudioLifecycleController.meditationDidStart()
        // before this method is called.

        if sessionStartDate == nil {
            sessionStartDate = Date()
            contentDetails = "Meditation Session (\(totalSeconds / 60) minutes)"
            // Log session_start via AnalyticsRouter
            AnalyticsRouter.shared.logSessionStart()
            
            // Log ai_onboarding_meditation_played when AI meditation from onboarding actually starts
            if let context = SessionContextManager.shared.currentContext,
               context.contentOrigin == .aiRecommended && SenseiOnboardingState.shared.isComplete {
                AnalyticsManager.shared.logEvent("ai_onboarding_meditation_played", parameters: [
                    "steps_completed": SenseiOnboardingState.shared.stepsCompletedBeforeExit,
                    "skipped_early": SenseiOnboardingState.shared.didSkipEarly
                ])
            }
            
            setupCompletionLogs()
            
            // Note: Heart rate is managed by PlayerView via HeartRateService
        }

        // Start silent audio.
        silentAudioPlayer.playSilently()

        timerCancellable = Timer
            .publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    /// Re-starts the silent keep-alive audio player after the app returns
    /// to foreground. Called by AppAudioLifecycleController when a timer
    /// session is active. Audio session activation is handled by the controller.
    func reactivateSilentAudio() {
        guard isRunning else { return }
        silentAudioPlayer.playSilently()
        print("[TimerSession] Silent audio reactivated")
    }

    func pause() {
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        
        // Note: We don't stop heart rate monitoring on pause, 
        // only when the session actually ends
    }

    func endSession() {
        pause()
        
        // 🛑 Notify end; orchestrator will manage HR stop
        PhoneConnectivityManager.shared.notifyPracticeEnded()
        
        // Lock HR results before metrics update to ensure final values are available
        if SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false) {
            PracticeBPMTracker.shared.stopTracking()
        }
        
        // Capture heart rate results before any cleanup
        let heartRateResults = HeartRateResults.from(PracticeBPMTracker.shared)

        if let startDate = sessionStartDate {
            let endDate = Date()
            StatsManager.shared.updateMetricsOnSessionCompletion(
                practiceID: practiceID,
                startDate: startDate,
                endDate: endDate
            )
        }

        // Queue post-practice message via unified manager ONLY when session fully completed
        if didCompleteSession {
            let durationMinutes = max(1, totalSeconds / 60)
            let title = sessionTitle
            let description = sessionDescription
            
            // Use Task to await the async handler - ensures report is persisted
            Task { @MainActor in
                logger.aiChat("📋 [POST_PRACTICE] COMPLETION_AWAIT_START type=custom")
                await UnifiedPostSessionManager.shared.handleCompletedSession(
                    type: .custom(title: title, description: description),
                    durationMinutes: durationMinutes,
                    heartRateResults: heartRateResults
                )
                logger.aiChat("📋 [POST_PRACTICE] COMPLETION_AWAIT_DONE type=custom")
            }
        }
        silentAudioPlayer.stopSilently()
        sessionStartDate = nil
        remainingSeconds = totalSeconds
        hasReached75Percent = false
        completionLogs.removeAll()
        // Clear session context after session ends
        AnalyticsRouter.shared.endSession()
        // Reset flag for next session lifecycle
        didCompleteSession = false
    }

    // MARK: - Audio Session
    //
    // Audio session activation/deactivation is managed centrally by
    // AppAudioLifecycleController. This file only manages the silent
    // keep-alive player and timer tick logic.

    // MARK: - Timer Tick

    private func tick() {
        guard remainingSeconds > 0 else {
            completeSession()
            return
        }
        remainingSeconds -= 1
        checkCompletionRates()

        let completionRate = currentProgress / totalDuration
        if completionRate >= 0.75, !hasReached75Percent {
            hasReached75Percent = true
        }

        if remainingSeconds <= 0 {
            completeSession()
        }
    }

    private func completeSession() {
        pause()
        remainingSeconds = 0
        
        // Log session_complete via AnalyticsRouter
        AnalyticsRouter.shared.logSessionComplete()
        
        onSessionComplete?()
        // Mark as truly completed before final cleanup to allow post-practice message queuing
        didCompleteSession = true
        
        // Add to session history using the new comprehensive manager
        // Determine source based on SessionContextManager
        let source: MeditationSessionSource = {
            guard let context = SessionContextManager.shared.currentContext else {
                return .timer
            }
            
            switch context.entryPoint {
            case .aiChat:
                return .aiChat
            case .createScreen:
                return .timer
            case .deepLink:
                return .deeplink
            default:
                return .timer
            }
        }()
        
        // Use AI-specific recording if this is an AI-generated meditation with a title
        if source == .aiChat, let title = sessionTitle {
            SessionHistoryManager.shared.recordAIMeditationCompletion(
                title: title,
                description: sessionDescription,
                totalSeconds: totalSeconds,
                backgroundSoundId: backgroundSoundUsed ? backgroundSoundName : nil,
                backgroundSoundName: backgroundSoundUsed ? backgroundSoundName : nil,
                binauralBeatId: binauralBeatUsed ? binauralBeatId : nil,
                binauralBeatName: binauralBeatUsed ? binauralBeatName : nil,
                cueIds: cueSettings.map { $0.cue.id },
                cueNames: cueSettings.map { $0.cue.name }
            )
        } else {
            SessionHistoryManager.shared.recordCustomMeditationCompletion(
                title: sessionTitle ?? "Custom Meditation",
                totalSeconds: totalSeconds,
                backgroundSoundId: backgroundSoundUsed ? backgroundSoundName : nil,
                backgroundSoundName: backgroundSoundUsed ? backgroundSoundName : nil,
                binauralBeatId: binauralBeatUsed ? binauralBeatId : nil,
                binauralBeatName: binauralBeatUsed ? binauralBeatName : nil,
                cueIds: cueSettings.map { $0.cue.id },
                cueNames: cueSettings.map { $0.cue.name },
                source: source
            )
        }
        
        endSession()
    }

    // MARK: - Completion Logs

    private func setupCompletionLogs() {
        completionLogs = [
            (0.25, false, "meditation_session_25_percent_complete"),
            (0.50, false, "meditation_session_50_percent_complete"),
            (0.75, false, "meditation_session_75_percent_complete"),
            (0.95, false, "meditation_session_95_percent_complete")
        ]
    }

    private func checkCompletionRates() {
        let fracComplete = currentProgress / totalDuration
        for i in completionLogs.indices where !completionLogs[i].logged && fracComplete >= completionLogs[i].threshold {
            completionLogs[i].logged = true
            // Log progress via AnalyticsRouter
            let milestone = Int(completionLogs[i].threshold * 100)
            AnalyticsRouter.shared.logSessionProgress(milestone: milestone)
        }
    }

    // HR start/stop is managed by HRSessionOrchestrator from Player/MeditationPlayer views
}

// MARK: - SilentAudioPlayer

/// Plays a silent MP3 on loop to keep the app alive in background
/// while a timer meditation is running. iOS suspends apps that have no
/// active audio; this silent track prevents that.
class SilentAudioPlayer {
    private var audioPlayer: AVAudioPlayer?

    func playSilently() {
        guard let url = Bundle.main.url(forResource: "silentLoop", withExtension: "mp3") else {
            print("[SilentAudio] ERROR — silentLoop.mp3 not found in bundle")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
            print("[SilentAudio] Started playing")
        } catch {
            print("[SilentAudio] Failed to start: \(error.localizedDescription)")
        }
    }

    func stopSilently() {
        audioPlayer?.stop()
        audioPlayer = nil
        print("[SilentAudio] Stopped")
    }
}
