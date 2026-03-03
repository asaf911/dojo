//
//  AppAudioLifecycleController.swift
//  Dojo
//
//  Single source of truth for app-wide audio lifecycle management.
//
//  Rules enforced:
//  1. Background music ALWAYS stops when the app enters background or is terminated.
//  2. Meditation audio continues in background but stops on app termination.
//  3. When a meditation session ends, ALL meditation audio is fully stopped
//     and the AVAudioSession is deactivated.
//
//  No other file should observe didEnterBackground / willEnterForeground /
//  willTerminate for audio purposes. Audio players register here and only
//  know how to play/pause/stop themselves.
//

import AVFoundation
import UIKit

final class AppAudioLifecycleController {

    // MARK: - Singleton

    static let shared = AppAudioLifecycleController()

    // MARK: - Session State

    /// Whether a meditation session (guided or timer) is currently in progress.
    /// This is the single source of truth -- replaces the UserDefaults backup
    /// flag and the multi-check `isMeditationSessionActive()` that previously
    /// lived inside GeneralBackgroundMusicController.
    private(set) var isMeditationSessionActive: Bool = false

    // MARK: - Registered Audio Players

    /// General background music (ambient loop that plays throughout the app).
    private weak var backgroundMusic: GeneralBackgroundMusicController?

    /// Guided meditation player (pre-recorded MP3 sessions).
    private weak var guidedPlayer: AudioPlayerManager?

    /// Timer session audio layers -- present only during an active timer session.
    private var timerAudioLayers: TimerAudioLayers?

    /// Timer manager reference for silent-audio reactivation on foreground.
    private weak var timerManager: MeditationSessionTimer?

    /// Lightweight container for the three audio layers used by timer meditations.
    struct TimerAudioLayers {
        weak var backgroundSound: MeditationAudioManager?
        weak var binauralBeat: BinauralBeatAudioManager?
        // CuePlaybackManager is a singleton; accessed directly via .shared.
    }

    // MARK: - Init

    private init() {
        observeLifecycle()
        print("[AudioLifecycle] Initialized")
    }

    // MARK: - Registration

    /// Register the background music controller. Called once at app startup.
    func registerBackgroundMusic(_ controller: GeneralBackgroundMusicController) {
        backgroundMusic = controller
        print("[AudioLifecycle] Registered background music controller")
    }

    /// Register the guided meditation player. Called once at app startup.
    func registerGuidedPlayer(_ player: AudioPlayerManager) {
        guidedPlayer = player
        print("[AudioLifecycle] Registered guided player")
    }

    /// Register timer session audio layers. Called when a timer session is created.
    func registerTimerSession(
        backgroundSound: MeditationAudioManager,
        binauralBeat: BinauralBeatAudioManager,
        timerManager: MeditationSessionTimer
    ) {
        timerAudioLayers = TimerAudioLayers(
            backgroundSound: backgroundSound,
            binauralBeat: binauralBeat
        )
        self.timerManager = timerManager
        print("[AudioLifecycle] Registered timer session audio layers")
    }

    /// Unregister timer session audio layers. Called when a timer session is destroyed.
    func unregisterTimerSession() {
        timerAudioLayers = nil
        timerManager = nil
        print("[AudioLifecycle] Unregistered timer session audio layers")
    }

    // MARK: - Session Lifecycle

    /// Call when any meditation session (guided or timer) begins.
    ///
    /// - Marks the session as active
    /// - Mutes background music
    /// - Activates the `.playback` audio session so meditation audio survives
    ///   background / lock-screen
    func meditationDidStart() {
        isMeditationSessionActive = true

        // Rule 1: Gently fade out background music (0.5s) and set isMuted = true
        // so the mute/unmute icon updates. Music stays muted after meditation ends
        // until the user manually unmutes.
        backgroundMusic?.muteForMeditation()

        // Activate .playback so meditation audio plays through silent switch
        // and continues in background.
        activatePlaybackSession()

        print("[AudioLifecycle] Meditation session started — background music fading out, .playback activated")
    }

    /// Call when any meditation session (guided or timer) ends.
    ///
    /// - Stops ALL meditation audio layers
    /// - Deactivates the audio session
    /// - Clears lock-screen Now Playing info
    /// - Marks the session as inactive
    func meditationDidEnd() {
        guard isMeditationSessionActive else {
            print("[AudioLifecycle] meditationDidEnd called but no session active — ignoring")
            return
        }

        isMeditationSessionActive = false

        // Rule 3: Stop all meditation audio
        guidedPlayer?.stopAudio()

        timerAudioLayers?.backgroundSound?.stop(withFadeOutDuration: 0)
        timerAudioLayers?.binauralBeat?.stop(withFadeOutDuration: 0)
        CuePlaybackManager.shared.stop()

        // Stop the silent keep-alive player
        timerManager?.endSession()

        // Deactivate the audio session so iOS no longer treats the app as an
        // audio source. This prevents phantom playback and control-center ghosts.
        deactivateAudioSession()

        // Clear lock screen
        LockScreenMediaService.shared.unregisterSession()

        print("[AudioLifecycle] Meditation session ended — all audio stopped, session deactivated")
    }

    // MARK: - Lifecycle Observers

    private func observeLifecycle() {
        let nc = NotificationCenter.default

        nc.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    // MARK: - Background / Foreground / Terminate

    /// Rule 1: Background music always stops on background.
    /// Rule 2: Meditation audio keeps playing in background.
    @objc private func appDidEnterBackground() {
        // Rule 1: Always stop background music immediately
        backgroundMusic?.immediateStop()

        if isMeditationSessionActive {
            // Rule 2: Meditation audio continues — leave .playback session active
            print("[AudioLifecycle] App entered background — background music stopped, meditation continues")
        } else {
            // No meditation playing — deactivate the audio session entirely so iOS
            // does not keep the app alive as an audio source.
            deactivateAudioSession()
            print("[AudioLifecycle] App entered background — background music stopped, audio session deactivated")
        }
    }

    /// Resume background music if no meditation is active and user preference allows it.
    /// Re-activate silent audio for timer sessions that were running in background.
    @objc private func appWillEnterForeground() {
        if isMeditationSessionActive {
            // Meditation was running in background — re-claim the audio session
            // and reactivate the silent keep-alive player for timer sessions.
            activatePlaybackSession()
            timerManager?.reactivateSilentAudio()
            print("[AudioLifecycle] App entering foreground — meditation active, reactivated audio session")
        } else {
            // No meditation — resume background music only if it was playing before background
            backgroundMusic?.resumeIfWasPlaying()
            print("[AudioLifecycle] App entering foreground — resuming background music if was playing")
        }
    }

    /// Terminate handler: stop ALL audio and deactivate the session.
    @objc private func appWillTerminate() {
        print("[AudioLifecycle] App will terminate — stopping all audio")

        // Rule 1: Stop background music
        backgroundMusic?.immediateStop()

        // Rule 2: Stop ALL meditation audio
        guidedPlayer?.stopAudio()
        timerAudioLayers?.backgroundSound?.stop(withFadeOutDuration: 0)
        timerAudioLayers?.binauralBeat?.stop(withFadeOutDuration: 0)
        CuePlaybackManager.shared.stop()

        // Deactivate audio session
        deactivateAudioSession()

        // Clear lock screen
        LockScreenMediaService.shared.unregisterSession()

        isMeditationSessionActive = false
    }

    // MARK: - Audio Session Helpers

    /// Activates the shared audio session with `.playback` category.
    /// Called when a meditation starts and when the app returns to foreground
    /// during an active meditation.
    private func activatePlaybackSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[AudioLifecycle] Audio session activated (.playback)")
        } catch {
            print("[AudioLifecycle] Failed to activate audio session: \(error)")
        }
    }

    /// Deactivates the shared audio session so iOS no longer considers
    /// the app an audio source. Prevents phantom playback and
    /// control-center ghosts.
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            print("[AudioLifecycle] Audio session deactivated")
        } catch {
            print("[AudioLifecycle] Failed to deactivate audio session: \(error)")
        }
    }
}
