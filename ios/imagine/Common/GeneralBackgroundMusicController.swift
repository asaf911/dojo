//
//  GeneralBackgroundMusicController.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-03-XX
//
//  Responsible for playing the ambient background music loop throughout the app.
//  Exposes a mute/unmute toggle for the UI and fade in/out helpers.
//
//  IMPORTANT: This controller does NOT observe app lifecycle events.
//  All background / foreground / terminate handling is owned by
//  AppAudioLifecycleController, which calls `immediateStop()` and
//  `resumeIfWasPlaying()` at the appropriate times.
//

import Foundation
import AVFoundation
import SwiftUI
import UIKit

class GeneralBackgroundMusicController: ObservableObject {

    // MARK: - Singleton

    static let shared = GeneralBackgroundMusicController()

    // MARK: - Private State

    private var audioPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?

    /// Tracks whether music was actively playing before the app entered background.
    /// Used by `resumeIfWasPlaying()` to decide whether to resume on foreground.
    private var wasPlayingBeforeBackground = false

    // MARK: - Persisted Mute State

    /// Single UserDefaults key for the muted state.
    /// This is the only persistent key -- no second "preference" key.
    /// On first-ever launch the key is absent, defaulting to `false` (music plays).
    private let muteStateKey = "backgroundMusicMuted"

    // MARK: - Published State

    /// Whether background music is currently muted.
    /// This is the single source of truth for both playback decisions and the
    /// mute/unmute icon. Setting it persists to UserDefaults and triggers
    /// `updatePlaybackState()`.
    @Published var isMuted: Bool = false {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: muteStateKey)
            updatePlaybackState()
        }
    }

    // MARK: - Init

    private init() {
        // Read the persisted mute state. Default to false (music plays)
        // for first-ever launch. Every subsequent launch reads whatever
        // the last state was -- including meditation auto-mute.
        let persisted = UserDefaults.standard.object(forKey: muteStateKey) as? Bool
        isMuted = persisted ?? false

        print("[BackgroundMusic] init — isMuted=\(isMuted)")

        if !isMuted {
            playMusic()
        }
    }

    // MARK: - Controller Interface (called by AppAudioLifecycleController)

    /// Immediately stops playback with zero fade. Synchronous and safe to call
    /// from `didEnterBackground` or `willTerminate` where iOS may suspend the
    /// process before asynchronous work completes.
    func immediateStop() {
        fadeTimer?.invalidate()
        fadeTimer = nil

        if let player = audioPlayer, player.isPlaying {
            wasPlayingBeforeBackground = true
            player.volume = 0
            player.pause()
        }

        print("[BackgroundMusic] immediateStop — playback paused, wasPlaying=\(wasPlayingBeforeBackground)")
    }

    /// Gentle fade-out used when a meditation session starts.
    /// Sets `isMuted = true` after the fade completes so the mute/unmute
    /// icon reflects the silenced state.
    /// Safe to call from the foreground only (uses Timer-based fade).
    func muteForMeditation() {
        fadeTimer?.invalidate()
        fadeTimer = nil

        guard let player = audioPlayer, player.isPlaying else {
            // Already silent -- just sync the flag
            DispatchQueue.main.async { self.isMuted = true }
            print("[BackgroundMusic] muteForMeditation — already silent, synced isMuted")
            return
        }

        let fadeDuration: Double = 0.5
        let fadeSteps = 10
        let stepDuration = fadeDuration / Double(fadeSteps)
        let initialVolume = player.volume
        let stepVolume = initialVolume / Float(fadeSteps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if currentStep < fadeSteps {
                player.volume = max(player.volume - stepVolume, 0)
                currentStep += 1
            } else {
                timer.invalidate()
                self.fadeTimer = nil
                player.pause()
                DispatchQueue.main.async { self.isMuted = true }
                print("[BackgroundMusic] muteForMeditation — fade complete, isMuted=true")
            }
        }
    }

    /// Resumes music on foreground only if BOTH conditions are met:
    /// 1. Music is not currently muted (by user toggle or meditation auto-mute)
    /// 2. Music was actually playing before the app went to background
    ///
    /// This ensures music stays muted after a meditation ends -- the user
    /// must manually tap unmute to bring it back.
    func resumeIfWasPlaying() {
        defer { wasPlayingBeforeBackground = false }

        guard !isMuted, wasPlayingBeforeBackground else {
            print("[BackgroundMusic] resumeIfWasPlaying — skipping (muted=\(isMuted), wasBG=\(wasPlayingBeforeBackground))")
            return
        }

        playMusic()
        print("[BackgroundMusic] resumeIfWasPlaying — resumed playback")
    }

    // MARK: - Playback

    /// Starts playing the background music with a fade-in effect.
    /// Uses `.playback` so audio is audible regardless of the hardware silent switch.
    func playMusic() {
        if isMuted {
            print("[BackgroundMusic] playMusic() skipped — isMuted=true")
            return
        }

        // Activate a .playback session so the music is audible even when the
        // iPhone silent switch is on. The session may have been deactivated after
        // a meditation ended, so we always explicitly re-activate here.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            print("[BackgroundMusic] audio session set to .playback + active")
        } catch {
            print("[BackgroundMusic] Failed to configure audio session: \(error)")
        }

        // Resume existing player with fade-in
        if let player = audioPlayer, !player.isPlaying {
            player.volume = 0.0
            let started = player.play()
            print("[BackgroundMusic] resuming existing player — play()=\(started)")
            fadeInMusic(duration: 2.0)
            return
        }

        if let player = audioPlayer, player.isPlaying {
            print("[BackgroundMusic] playMusic() — player already playing, volume=\(player.volume)")
            return
        }

        // Initialize a new player
        print("[BackgroundMusic] initializing new audio player")
        initializeAudioPlayer { [weak self] in
            self?.fadeInMusic(duration: 2.0)
        }
    }

    // MARK: - Pause / Mute / Toggle

    /// Pauses the background music with a 1-second fade-out.
    func pauseMusic() {
        fadeOutMusic(duration: 1.0, isFinalPause: true)
    }

    /// Temporary pause without affecting the user preference (for automatic pauses).
    func temporaryPause() {
        temporaryFadeOut(duration: 1.0)
    }

    /// Toggles mute state. This is the **manual** toggle triggered by user interaction.
    /// Persistence is handled by the `isMuted` didSet writing to `muteStateKey`.
    func toggleMute() {
        let newMuted = !isMuted
        print("[BackgroundMusic] toggleMute — \(isMuted) -> \(newMuted)")
        isMuted = newMuted
    }

    /// Fades out music when entering a practice session (1-second fade).
    func fadeOutForPractice() {
        fadeOutMusic(duration: 1.0, isFinalPause: true)
    }

    // MARK: - Fade Helpers

    /// Gradually fades out and optionally sets `isMuted = true` when complete.
    func fadeOutMusic(duration: Double = 1.0, isFinalPause: Bool = false) {
        guard let player = audioPlayer, player.isPlaying else { return }

        fadeTimer?.invalidate()

        let fadeSteps = 20
        let stepDuration = duration / Double(fadeSteps)
        let initialVolume = player.volume
        let stepVolume = initialVolume / Float(fadeSteps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            if currentStep < fadeSteps {
                player.volume = max(player.volume - stepVolume, 0)
                currentStep += 1
            } else {
                timer.invalidate()
                self.fadeTimer = nil
                player.pause()

                if isFinalPause {
                    DispatchQueue.main.async { self.isMuted = true }
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// Syncs playback state with the current `isMuted` value.
    private func updatePlaybackState() {
        print("[BackgroundMusic] updatePlaybackState — isMuted=\(isMuted), playerExists=\(audioPlayer != nil), isPlaying=\(audioPlayer?.isPlaying ?? false)")
        if isMuted {
            pauseMusic()
        } else {
            playMusic()
        }
    }

    /// Gradually fades in the background music over `duration` seconds.
    private func fadeInMusic(duration: Double = 2.0) {
        guard let player = audioPlayer, player.isPlaying else { return }

        fadeTimer?.invalidate()

        let fadeSteps = 20
        let stepDuration = duration / Double(fadeSteps)
        let targetVolume: Float = 1.0
        let stepVolume = targetVolume / Float(fadeSteps)
        var currentStep = 0

        player.volume = 0.0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            if currentStep < fadeSteps {
                player.volume = min(player.volume + stepVolume, targetVolume)
                currentStep += 1
            } else {
                timer.invalidate()
                self.fadeTimer = nil
            }
        }
    }

    /// Temporary fade-out that does NOT change `isMuted`.
    private func temporaryFadeOut(duration: Double = 1.0) {
        guard let player = audioPlayer, player.isPlaying else { return }

        fadeTimer?.invalidate()

        let fadeSteps = 20
        let stepDuration = duration / Double(fadeSteps)
        let initialVolume = player.volume
        let stepVolume = initialVolume / Float(fadeSteps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            if currentStep < fadeSteps {
                player.volume = max(player.volume - stepVolume, 0)
                currentStep += 1
            } else {
                timer.invalidate()
                self.fadeTimer = nil
                player.pause()
            }
        }
    }

    /// Initializes the AVAudioPlayer with the bundled background music file.
    private func initializeAudioPlayer(completion: @escaping () -> Void) {
        guard let url = Bundle.main.url(forResource: "ES_Interstice of Sound - DEX 1200", withExtension: "mp3") else {
            print("[BackgroundMusic] ERROR — music file not found in bundle")
            return
        }

        do {
            audioPlayer = nil
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.0
            audioPlayer?.prepareToPlay()
            let started = audioPlayer?.play() ?? false
            print("[BackgroundMusic] player initialized — play()=\(started), duration=\(audioPlayer?.duration ?? 0)")
            completion()
        } catch {
            print("[BackgroundMusic] ERROR loading audio file: \(error)")
        }
    }

    // MARK: - Cleanup

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
