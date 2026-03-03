//
//  MeditationAudioManager.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-11
//

import AVFoundation
import Foundation

class MeditationAudioManager: NSObject {
    // Two players used to crossfade between loops.
    private var currentPlayer: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?
    
    // Timer to schedule crossfade.
    private var crossfadeTimer: Timer?
    
    // Duration (in seconds) for the crossfade transition.
    private var crossfadeDuration: TimeInterval = 10.0
    
    // In-memory audio data loaded from the downloaded file.
    private var audioData: Data?
    
    // Duration of the loaded audio file.
    private var soundDuration: TimeInterval = 0.0
    
    // Indicates if looping is active.
    private var isPlaying: Bool = false

    // Target output volume for ambience channel (0.0 - 1.0)
    private(set) var volume: Float = 0.5

    /// Updates the ambience volume. If audio is currently playing, this will fade to the new level.
    /// - Parameters:
    ///   - value: Target volume in 0...1
    ///   - animated: Whether to fade to the new volume
    ///   - fadeDuration: Fade duration if animated is true
    func setVolume(_ value: Float, animated: Bool = true, fadeDuration: TimeInterval = 0.3) {
        let clamped = max(0.0, min(1.0, value))
        volume = clamped
        if animated {
            currentPlayer?.setVolume(volume, fadeDuration: fadeDuration)
            nextPlayer?.setVolume(volume, fadeDuration: fadeDuration)
        } else {
            currentPlayer?.volume = volume
            nextPlayer?.volume = volume
        }
    }

    /// Plays a background sound with crossfade looping.
    /// - Parameters:
    ///   - sound: The BackgroundSound model containing the name and URL.
    ///   - fadeInDuration: The fade-in duration for the initial playback.
    func play(sound: BackgroundSound, withFadeInDuration fadeInDuration: TimeInterval = 10.0) {
        // If the selected sound is none, do nothing.
        if sound.id == "None" || sound.name == "None" || sound.url.isEmpty {
            print("[DEBUG] No background sound selected.")
            return
        }
        print("[DEBUG] Attempting to play background sound: \(sound.name) with initial fade-in duration \(fadeInDuration)s and crossfade duration \(crossfadeDuration)s")
        
        guard ConnectivityHelper.isConnectedToInternet() else {
            print("[DEBUG] No internet connection. Cannot download background sound.")
            return
        }
        
        guard let remoteURL = URL(string: sound.url) else {
            print("[DEBUG] Invalid URL for background sound: \(sound.url)")
            return
        }
        
        FileManagerHelper.shared.ensureLocalFile(for: remoteURL, setDownloading: { downloading in
            print("[DEBUG] Background sound ensureLocalFile downloading: \(downloading)")
        }, completion: { [weak self] localURL in
            guard let self = self else { return }
            guard let localURL = localURL else {
                print("[DEBUG] Failed to download background sound file.")
                return
            }
            do {
                // Load the file data into memory.
                self.audioData = try Data(contentsOf: localURL)
                guard let data = self.audioData else {
                    print("[DEBUG] Audio data is nil after download.")
                    return
                }
                // Create the current player from the in-memory data.
                self.currentPlayer = try AVAudioPlayer(data: data)
                self.currentPlayer?.delegate = self
                self.currentPlayer?.volume = 0.0
                self.currentPlayer?.prepareToPlay()
                self.soundDuration = self.currentPlayer?.duration ?? 0.0
                print("[DEBUG] Loaded audio file. Duration: \(self.soundDuration) seconds.")
                self.currentPlayer?.play()
                // Fade in the first player to the configured volume
                self.currentPlayer?.setVolume(self.volume, fadeDuration: fadeInDuration)
                self.isPlaying = true
                self.scheduleCrossfade()
                print("[DEBUG] Background sound started with crossfade loop.")
            } catch {
                print("[DEBUG] Error playing background sound: \(error.localizedDescription)")
            }
        })
    }
    
    /// Schedules the crossfade timer to trigger when the current loop nears its end.
    private func scheduleCrossfade() {
        // Invalidate any existing timer.
        crossfadeTimer?.invalidate()
        guard let currentPlayer = currentPlayer else {
            print("🧠 AI_DEBUG [AMBIENCE] scheduleCrossfade: no currentPlayer")
            return
        }
        
        // Calculate the time remaining until we need to start the crossfade.
        let remainingTime = (soundDuration - crossfadeDuration) - currentPlayer.currentTime
        print("🧠 AI_DEBUG [AMBIENCE] scheduleCrossfade: position=\(String(format: "%.1f", currentPlayer.currentTime))s, crossfade in \(String(format: "%.1f", remainingTime))s")
        // Always schedule on the main thread.
        DispatchQueue.main.async {
            if remainingTime > 0 {
                self.crossfadeTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
                    self?.performCrossfade()
                }
            } else {
                print("🧠 AI_DEBUG [AMBIENCE] Remaining time <= 0; performing immediate crossfade")
                self.performCrossfade()
            }
        }
    }
    
    /// Performs the crossfade by starting a second player at volume 0 and fading it in while fading out the current player.
    private func performCrossfade() {
        guard let data = audioData, let currentPlayer = currentPlayer else {
            print("🧠 AI_DEBUG [AMBIENCE] performCrossfade: missing data or player")
            return
        }
        print("🧠 AI_DEBUG [AMBIENCE] performCrossfade: starting \(crossfadeDuration)s crossfade, current position=\(String(format: "%.1f", currentPlayer.currentTime))s")
        do {
            // Create the next player from the in-memory audio data.
            nextPlayer = try AVAudioPlayer(data: data)
            nextPlayer?.delegate = self
            nextPlayer?.volume = 0.0
            nextPlayer?.prepareToPlay()
            nextPlayer?.play()
            // Begin simultaneous fade: next player's target volume is configured volume
            nextPlayer?.setVolume(volume, fadeDuration: crossfadeDuration)
            currentPlayer.setVolume(0.0, fadeDuration: crossfadeDuration)
            
            // After the fade duration, swap the players and schedule the next crossfade.
            DispatchQueue.main.asyncAfter(deadline: .now() + crossfadeDuration) { [weak self] in
                guard let self = self else { return }
                self.currentPlayer?.stop()
                self.currentPlayer = self.nextPlayer
                self.nextPlayer = nil
                print("🧠 AI_DEBUG [AMBIENCE] Crossfade complete, new loop started")
                if self.isPlaying {
                    self.scheduleCrossfade()
                }
            }
        } catch {
            print("🧠 AI_DEBUG [AMBIENCE] Error during crossfade: \(error.localizedDescription)")
        }
    }
    
    /// Stops the background sound playback with a fade-out.
    /// - Parameter fadeOutDuration: Duration for the fade-out effect.
    func stop(withFadeOutDuration fadeOutDuration: TimeInterval = 3.0) {
        print("🧠 AI_DEBUG [AMBIENCE] stop() called with fadeOut=\(fadeOutDuration)s")
        isPlaying = false
        crossfadeTimer?.invalidate()
        if let currentPlayer = currentPlayer {
            currentPlayer.setVolume(0.0, fadeDuration: fadeOutDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutDuration) {
                currentPlayer.stop()
                self.currentPlayer = nil
                print("🧠 AI_DEBUG [AMBIENCE] Fade-out complete, player stopped")
            }
        }
        if let nextPlayer = nextPlayer {
            nextPlayer.setVolume(0.0, fadeDuration: fadeOutDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutDuration) {
                nextPlayer.stop()
                self.nextPlayer = nil
            }
        }
    }
    
    /// Pauses the background sound playback.
    func pause() {
        print("[DEBUG] Pausing background sound.")
        isPlaying = false
        crossfadeTimer?.invalidate()
        currentPlayer?.pause()
        nextPlayer?.pause()
    }
    
    /// Resumes the background sound playback and re-schedules the crossfade.
    func resume() {
        print("[DEBUG] Resuming background sound.")
        isPlaying = true
        currentPlayer?.play()
        nextPlayer?.play()
        scheduleCrossfade()
    }
    
    // MARK: - Seeking
    
    /// Seeks forward or backward by the specified number of seconds.
    /// Handles looping: if seeking past the end, wraps to the beginning; if seeking before the start, wraps to the end.
    /// - Parameter seconds: Positive to seek forward, negative to seek backward.
    func seek(by seconds: TimeInterval) {
        // Entry point logging - always prints
        print("🧠 AI_DEBUG [AMBIENCE] seek(by: \(seconds)) called - hasPlayer=\(currentPlayer != nil), duration=\(soundDuration), isPlaying=\(isPlaying), hasData=\(audioData != nil)")
        
        // Cancel any in-progress crossfade timer
        crossfadeTimer?.invalidate()
        
        // Stop any mid-crossfade next player
        if let next = nextPlayer {
            next.stop()
            nextPlayer = nil
            print("🧠 AI_DEBUG [AMBIENCE] Cancelled mid-crossfade next player")
        }
        
        // Try to recover if player was nil'd but we have audio data
        if currentPlayer == nil, let data = audioData {
            print("🧠 AI_DEBUG [AMBIENCE] Recovering - recreating player from cached data")
            do {
                currentPlayer = try AVAudioPlayer(data: data)
                currentPlayer?.delegate = self
                currentPlayer?.prepareToPlay()
                soundDuration = currentPlayer?.duration ?? 0.0
            } catch {
                print("🧠 AI_DEBUG [AMBIENCE] Failed to recreate player: \(error.localizedDescription)")
                return
            }
        }
        
        guard let player = currentPlayer, soundDuration > 0 else {
            print("🧠 AI_DEBUG [AMBIENCE] Cannot seek - no player or duration")
            return
        }
        
        let oldPosition = player.currentTime
        var newPosition = oldPosition + seconds
        
        // Handle wrapping for loops
        while newPosition < 0 {
            newPosition += soundDuration
        }
        while newPosition >= soundDuration {
            newPosition -= soundDuration
        }
        
        // Seek to new position
        player.currentTime = newPosition
        
        // CRITICAL: Restore volume immediately (cancels any fade-in/out in progress)
        player.volume = volume
        
        // Ensure player is actually playing
        if !player.isPlaying {
            player.play()
            print("🧠 AI_DEBUG [AMBIENCE] Restarted playback after seek")
        }
        
        // Mark as playing
        isPlaying = true
        
        print("🧠 AI_DEBUG [AMBIENCE] Seeked: \(String(format: "%.1f", oldPosition))s -> \(String(format: "%.1f", newPosition))s (duration=\(String(format: "%.1f", soundDuration))s, vol=\(volume))")
        
        // Reschedule crossfade based on new position
        scheduleCrossfade()
    }
    
    /// Seeks to a specific session elapsed time with optional fade-in (for restarting from beginning).
    /// - Parameters:
    ///   - sessionElapsed: The session elapsed time in seconds
    ///   - withFadeIn: If true and sessionElapsed is 0, apply a fade-in effect
    ///   - fadeInDuration: Duration of fade-in if applicable
    func seekToSessionTime(_ sessionElapsed: TimeInterval, withFadeIn: Bool = false, fadeInDuration: TimeInterval = 3.0) {
        print("🧠 AI_DEBUG [AMBIENCE] seekToSessionTime(\(sessionElapsed), fadeIn=\(withFadeIn), wasPlaying=\(isPlaying))")
        
        // Remember if we were playing before seek - respect paused state
        let wasPlaying = isPlaying
        
        // Cancel any in-progress crossfade
        crossfadeTimer?.invalidate()
        if let next = nextPlayer {
            next.stop()
            nextPlayer = nil
        }
        
        // Log current state before any changes
        print("🧠 AI_DEBUG [AMBIENCE] PRE-SEEK: hasPlayer=\(currentPlayer != nil), playerIsPlaying=\(currentPlayer?.isPlaying ?? false), currentVol=\(currentPlayer?.volume ?? -1), targetVol=\(volume)")
        
        // Recover player if needed
        if currentPlayer == nil, let data = audioData {
            do {
                currentPlayer = try AVAudioPlayer(data: data)
                currentPlayer?.delegate = self
                currentPlayer?.prepareToPlay()
                soundDuration = currentPlayer?.duration ?? 0.0
                print("🧠 AI_DEBUG [AMBIENCE] Recovered player from cached data, duration=\(soundDuration)")
            } catch {
                print("🧠 AI_DEBUG [AMBIENCE] Failed to recreate player: \(error)")
                return
            }
        }
        
        guard let player = currentPlayer, soundDuration > 0 else {
            print("🧠 AI_DEBUG [AMBIENCE] Cannot seekToSessionTime - no player or no duration")
            return
        }
        
        // Calculate position in audio file (wrap for loops)
        var audioPosition = sessionElapsed.truncatingRemainder(dividingBy: soundDuration)
        if audioPosition < 0 { audioPosition += soundDuration }
        
        // If paused, just update position without starting playback
        if !wasPlaying {
            player.currentTime = audioPosition
            player.volume = volume
            print("🧠 AI_DEBUG [AMBIENCE] PAUSED SEEK: updated position to \(String(format: "%.1f", audioPosition))s, staying paused")
            return
        }
        
        // Handle fade-in for "restart from beginning" experience (only when playing)
        if withFadeIn && sessionElapsed == 0 {
            // Stop the player first, then restart fresh for clean fade-in
            player.stop()
            player.currentTime = 0
            player.volume = 0.0
            player.prepareToPlay()
            let playSuccess = player.play()
            player.setVolume(volume, fadeDuration: fadeInDuration)
            print("🧠 AI_DEBUG [AMBIENCE] FADE-IN: playSuccess=\(playSuccess), isPlaying=\(player.isPlaying), vol=\(player.volume)->target=\(volume) over \(fadeInDuration)s")
        } else {
            player.currentTime = audioPosition
            player.volume = volume
            if !player.isPlaying {
                let playSuccess = player.play()
                print("🧠 AI_DEBUG [AMBIENCE] Started playback: success=\(playSuccess)")
            }
        }
        
        isPlaying = true
        scheduleCrossfade()
        
        print("🧠 AI_DEBUG [AMBIENCE] POST-SEEK: isPlaying=\(player.isPlaying), vol=\(player.volume), audioPos=\(String(format: "%.1f", audioPosition))s")
    }
    
    /// Returns the current playback position and total duration.
    func getPlaybackInfo() -> (currentTime: TimeInterval, duration: TimeInterval)? {
        guard let player = currentPlayer, soundDuration > 0 else { return nil }
        return (currentTime: player.currentTime, duration: soundDuration)
    }
}

// MARK: - AVAudioPlayerDelegate

extension MeditationAudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // This should not normally happen if crossfade is scheduled.
        // If it does, log the event and restart playback.
        print("[DEBUG] audioPlayerDidFinishPlaying triggered. successfully = \(flag). Restarting playback if needed.")
        if isPlaying {
            // Restart the player from beginning.
            player.currentTime = 0
            player.play()
            scheduleCrossfade()
            print("[DEBUG] audioPlayerDidFinishPlaying: Restarted playback.")
        }
    }
}
