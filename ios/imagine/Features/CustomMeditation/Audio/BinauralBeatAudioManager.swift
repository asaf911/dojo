//
//  BinauralBeatAudioManager.swift
//  Dojo
//
//  Created by Assistant on 2025-10-01
//

import AVFoundation
import Foundation

class BinauralBeatAudioManager: NSObject {
    private var currentPlayer: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?
    private var crossfadeTimer: Timer?
    private var crossfadeDuration: TimeInterval = 10.0
    private var audioData: Data?
    private var soundDuration: TimeInterval = 0.0
    private var isPlaying: Bool = false

    private(set) var volume: Float = 0.5

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
    
    func play(beat: BinauralBeat, withFadeInDuration fadeInDuration: TimeInterval = 8.0) {
        if beat.id == "None" || beat.name == "None" || beat.url.isEmpty {
            print("[BB][DEBUG] No binaural beat selected.")
            return
        }
        guard let remoteURL = URL(string: beat.url) else {
            print("[BB][DEBUG] Invalid URL for binaural beat: \(beat.url)")
            return
        }
        print("[BB][DEBUG] Attempting to play binaural beat: \(beat.name) url=\(beat.url)")
        FileManagerHelper.shared.ensureLocalFile(for: remoteURL, setDownloading: { downloading in
            print("AI_[BB] ensureLocalFile downloading=\(downloading) for \(remoteURL)")
        }, completion: { [weak self] localURL in
            guard let self = self, let localURL = localURL else {
                print("[BB][DEBUG] Failed to download binaural beat file.")
                return
            }
            print("AI_[BB] local file ready path=\(localURL.path)")
            do {
                self.audioData = try Data(contentsOf: localURL)
                guard let data = self.audioData else { return }
                self.currentPlayer = try AVAudioPlayer(data: data)
                self.currentPlayer?.delegate = self
                // Start from 0 and fade to user-controlled target volume via setVolume below
                self.currentPlayer?.volume = 0.0
                self.currentPlayer?.prepareToPlay()
                self.soundDuration = self.currentPlayer?.duration ?? 0.0
                print("AI_[BB] loaded duration=\(self.soundDuration)s fade_in=\(fadeInDuration)s")
                self.currentPlayer?.play()
                // Fade in the first player to the configured volume
                self.currentPlayer?.setVolume(self.volume, fadeDuration: fadeInDuration)
                self.isPlaying = true
                self.scheduleCrossfade()
                print("AI_[BB] started with crossfade loop")
            } catch {
                print("[BB][DEBUG] Error playing binaural beat: \(error.localizedDescription)")
            }
        })
    }
    
    private func scheduleCrossfade() {
        crossfadeTimer?.invalidate()
        guard let currentPlayer = currentPlayer else {
            print("🧠 AI_DEBUG [BINAURAL] scheduleCrossfade: no currentPlayer")
            return
        }
        let remainingTime = (soundDuration - crossfadeDuration) - currentPlayer.currentTime
        print("🧠 AI_DEBUG [BINAURAL] scheduleCrossfade: position=\(String(format: "%.1f", currentPlayer.currentTime))s, crossfade in \(String(format: "%.1f", remainingTime))s")
        DispatchQueue.main.async {
            if remainingTime > 0 {
                self.crossfadeTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
                    self?.performCrossfade()
                }
            } else {
                print("🧠 AI_DEBUG [BINAURAL] Remaining time <= 0; performing immediate crossfade")
                self.performCrossfade()
            }
        }
    }
    
    private func performCrossfade() {
        guard let data = audioData, let currentPlayer = currentPlayer else {
            print("🧠 AI_DEBUG [BINAURAL] performCrossfade: missing data or player")
            return
        }
        print("🧠 AI_DEBUG [BINAURAL] performCrossfade: starting \(crossfadeDuration)s crossfade, current position=\(String(format: "%.1f", currentPlayer.currentTime))s")
        do {
            nextPlayer = try AVAudioPlayer(data: data)
            nextPlayer?.delegate = self
            // Start next player at 0 to crossfade up to the current target volume
            nextPlayer?.volume = 0.0
            nextPlayer?.prepareToPlay()
            nextPlayer?.play()
            nextPlayer?.setVolume(volume, fadeDuration: crossfadeDuration)
            currentPlayer.setVolume(0.0, fadeDuration: crossfadeDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + crossfadeDuration) { [weak self] in
                guard let self = self else { return }
                self.currentPlayer?.stop()
                self.currentPlayer = self.nextPlayer
                self.nextPlayer = nil
                print("🧠 AI_DEBUG [BINAURAL] Crossfade complete, new loop started")
                if self.isPlaying { self.scheduleCrossfade() }
            }
        } catch {
            print("🧠 AI_DEBUG [BINAURAL] Error during crossfade: \(error.localizedDescription)")
        }
    }
    
    func stop(withFadeOutDuration fadeOutDuration: TimeInterval = 3.0) {
        print("🧠 AI_DEBUG [BINAURAL] stop() called with fadeOut=\(fadeOutDuration)s")
        isPlaying = false
        crossfadeTimer?.invalidate()
        if let currentPlayer = currentPlayer {
            currentPlayer.setVolume(0.0, fadeDuration: fadeOutDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutDuration) {
                currentPlayer.stop()
                self.currentPlayer = nil
                print("🧠 AI_DEBUG [BINAURAL] Fade-out complete, player stopped")
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
    
    func pause() {
        isPlaying = false
        crossfadeTimer?.invalidate()
        currentPlayer?.pause()
        nextPlayer?.pause()
    }
    
    func resume() {
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
        print("🧠 AI_DEBUG [BINAURAL] seek(by: \(seconds)) called - hasPlayer=\(currentPlayer != nil), duration=\(soundDuration), isPlaying=\(isPlaying), hasData=\(audioData != nil)")
        
        // Cancel any in-progress crossfade timer
        crossfadeTimer?.invalidate()
        
        // Stop any mid-crossfade next player
        if let next = nextPlayer {
            next.stop()
            nextPlayer = nil
            print("🧠 AI_DEBUG [BINAURAL] Cancelled mid-crossfade next player")
        }
        
        // Try to recover if player was nil'd but we have audio data
        if currentPlayer == nil, let data = audioData {
            print("🧠 AI_DEBUG [BINAURAL] Recovering - recreating player from cached data")
            do {
                currentPlayer = try AVAudioPlayer(data: data)
                currentPlayer?.delegate = self
                currentPlayer?.prepareToPlay()
                soundDuration = currentPlayer?.duration ?? 0.0
            } catch {
                print("🧠 AI_DEBUG [BINAURAL] Failed to recreate player: \(error.localizedDescription)")
                return
            }
        }
        
        guard let player = currentPlayer, soundDuration > 0 else {
            print("🧠 AI_DEBUG [BINAURAL] Cannot seek - no player or duration")
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
            print("🧠 AI_DEBUG [BINAURAL] Restarted playback after seek")
        }
        
        // Mark as playing
        isPlaying = true
        
        print("🧠 AI_DEBUG [BINAURAL] Seeked: \(String(format: "%.1f", oldPosition))s -> \(String(format: "%.1f", newPosition))s (duration=\(String(format: "%.1f", soundDuration))s, vol=\(volume))")
        
        // Reschedule crossfade based on new position
        scheduleCrossfade()
    }
    
    /// Seeks to a specific session elapsed time with optional fade-in (for restarting from beginning).
    /// - Parameters:
    ///   - sessionElapsed: The session elapsed time in seconds
    ///   - withFadeIn: If true and sessionElapsed is 0, apply a fade-in effect
    ///   - fadeInDuration: Duration of fade-in if applicable
    func seekToSessionTime(_ sessionElapsed: TimeInterval, withFadeIn: Bool = false, fadeInDuration: TimeInterval = 3.0) {
        print("🧠 AI_DEBUG [BINAURAL] seekToSessionTime(\(sessionElapsed), fadeIn=\(withFadeIn), wasPlaying=\(isPlaying))")
        
        // Remember if we were playing before seek - respect paused state
        let wasPlaying = isPlaying
        
        // Cancel any in-progress crossfade
        crossfadeTimer?.invalidate()
        if let next = nextPlayer {
            next.stop()
            nextPlayer = nil
        }
        
        // Log current state before any changes
        print("🧠 AI_DEBUG [BINAURAL] PRE-SEEK: hasPlayer=\(currentPlayer != nil), playerIsPlaying=\(currentPlayer?.isPlaying ?? false), currentVol=\(currentPlayer?.volume ?? -1), targetVol=\(volume)")
        
        // Recover player if needed
        if currentPlayer == nil, let data = audioData {
            do {
                currentPlayer = try AVAudioPlayer(data: data)
                currentPlayer?.delegate = self
                currentPlayer?.prepareToPlay()
                soundDuration = currentPlayer?.duration ?? 0.0
                print("🧠 AI_DEBUG [BINAURAL] Recovered player from cached data, duration=\(soundDuration)")
            } catch {
                print("🧠 AI_DEBUG [BINAURAL] Failed to recreate player: \(error)")
                return
            }
        }
        
        guard let player = currentPlayer, soundDuration > 0 else {
            print("🧠 AI_DEBUG [BINAURAL] Cannot seekToSessionTime - no player or no duration")
            return
        }
        
        // Calculate position in audio file (wrap for loops)
        var audioPosition = sessionElapsed.truncatingRemainder(dividingBy: soundDuration)
        if audioPosition < 0 { audioPosition += soundDuration }
        
        // If paused, just update position without starting playback
        if !wasPlaying {
            player.currentTime = audioPosition
            player.volume = volume
            print("🧠 AI_DEBUG [BINAURAL] PAUSED SEEK: updated position to \(String(format: "%.1f", audioPosition))s, staying paused")
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
            print("🧠 AI_DEBUG [BINAURAL] FADE-IN: playSuccess=\(playSuccess), isPlaying=\(player.isPlaying), vol=\(player.volume)->target=\(volume) over \(fadeInDuration)s")
        } else {
            player.currentTime = audioPosition
            player.volume = volume
            if !player.isPlaying {
                let playSuccess = player.play()
                print("🧠 AI_DEBUG [BINAURAL] Started playback: success=\(playSuccess)")
            }
        }
        
        isPlaying = true
        scheduleCrossfade()
        
        print("🧠 AI_DEBUG [BINAURAL] POST-SEEK: isPlaying=\(player.isPlaying), vol=\(player.volume), audioPos=\(String(format: "%.1f", audioPosition))s")
    }
    
    /// Returns the current playback position and total duration.
    func getPlaybackInfo() -> (currentTime: TimeInterval, duration: TimeInterval)? {
        guard let player = currentPlayer, soundDuration > 0 else { return nil }
        return (currentTime: player.currentTime, duration: soundDuration)
    }
}

extension BinauralBeatAudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if isPlaying {
            player.currentTime = 0
            player.play()
            scheduleCrossfade()
        }
    }
}


