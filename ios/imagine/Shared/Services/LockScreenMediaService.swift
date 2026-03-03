//
//  LockScreenMediaService.swift
//  Dojo
//
//  Centralized service for iOS lock screen media controls integration.
//  Manages MPNowPlayingInfoCenter and MPRemoteCommandCenter for all session types.
//

import Foundation
import MediaPlayer
import UIKit

/// Singleton service that handles all lock screen media integration.
/// Both guided and timer sessions register with this service to display
/// on the lock screen and respond to remote commands.
class LockScreenMediaService {
    
    // MARK: - Singleton
    
    static let shared = LockScreenMediaService()
    
    // MARK: - Properties
    
    /// The currently active media session (weak to avoid retain cycles)
    private weak var activeSession: MediaSessionProtocol?
    
    /// Cached artwork to avoid reloading
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkURL: URL?
    
    // MARK: - Initialization
    
    private init() {
        setupRemoteCommandCenter()
    }
    
    // MARK: - Session Management
    
    /// Registers a session as the active media session for lock screen display.
    /// This will update the Now Playing info and enable remote commands.
    /// - Parameter session: The session to register
    func registerSession(_ session: MediaSessionProtocol) {
        print("🧠 AI_DEBUG [LOCKSCREEN] Registering session: \(session.mediaTitle)")
        activeSession = session
        
        // Load artwork - prefer remote URL, fall back to local asset
        if let artworkURL = session.mediaArtworkURL {
            loadArtwork(from: artworkURL)
        } else if let localName = session.mediaLocalArtworkName {
            loadLocalArtwork(named: localName)
        } else {
            cachedArtwork = nil
            cachedArtworkURL = nil
        }
        
        updateNowPlayingInfo()
    }
    
    /// Unregisters the current session, clearing the lock screen.
    func unregisterSession() {
        print("🧠 AI_DEBUG [LOCKSCREEN] Unregistering session")
        activeSession = nil
        clearNowPlayingInfo()
    }
    
    // MARK: - Now Playing Updates
    
    /// Updates all Now Playing info from the active session.
    /// Call this when session metadata changes (e.g., cue changes in timer session).
    func updateNowPlayingInfo() {
        guard let session = activeSession else {
            clearNowPlayingInfo()
            return
        }
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: session.mediaTitle,
            MPMediaItemPropertyPlaybackDuration: session.mediaDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: session.mediaElapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: session.mediaIsPlaying ? 1.0 : 0.0
        ]
        
        if let subtitle = session.mediaSubtitle {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        
        if let artwork = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    /// Updates only the elapsed time - more efficient for frequent updates.
    /// - Parameter time: The new elapsed time in seconds
    func updateElapsedTime(_ time: TimeInterval) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            updateNowPlayingInfo()
            return
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    /// Updates only the playback state (playing/paused).
    /// - Parameter isPlaying: Whether playback is active
    func updatePlaybackState(isPlaying: Bool) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            updateNowPlayingInfo()
            return
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        // Also update elapsed time to ensure scrubber position is accurate
        if let session = activeSession {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = session.mediaElapsedTime
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    /// Loads artwork from a URL asynchronously.
    /// - Parameter url: The URL to load artwork from
    func loadArtwork(from url: URL?) {
        guard let url = url else {
            cachedArtwork = nil
            cachedArtworkURL = nil
            return
        }
        
        // Skip if already cached
        if url == cachedArtworkURL, cachedArtwork != nil {
            return
        }
        
        cachedArtworkURL = url
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self,
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                return
            }
            
            // Crop to square for optimal lock screen display (1:1 aspect ratio)
            let squareImage = self.cropToSquare(image)
            
            let artwork = MPMediaItemArtwork(boundsSize: squareImage.size) { _ in squareImage }
            
            DispatchQueue.main.async {
                self.cachedArtwork = artwork
                self.updateNowPlayingInfo()
            }
        }
    }
    
    /// Loads artwork from a local bundle asset.
    /// - Parameter name: The name of the image asset in the bundle
    func loadLocalArtwork(named name: String) {
        // Clear URL cache since we're using a local asset
        cachedArtworkURL = nil
        
        guard let image = UIImage(named: name) else {
            print("🧠 AI_DEBUG [LOCKSCREEN] Failed to load local artwork: \(name)")
            cachedArtwork = nil
            return
        }
        
        // Crop to square for optimal lock screen display (1:1 aspect ratio)
        let squareImage = cropToSquare(image)
        
        // Create artwork with the cropped square image
        cachedArtwork = MPMediaItemArtwork(boundsSize: squareImage.size) { _ in squareImage }
        print("🧠 AI_DEBUG [LOCKSCREEN] Loaded local artwork: \(name) (cropped to \(Int(squareImage.size.width))x\(Int(squareImage.size.height)))")
    }
    
    // MARK: - Image Processing
    
    /// Crops an image to a square from the center.
    /// Lock screen artwork displays best at 1:1 aspect ratio.
    /// - Parameter image: The source image to crop
    /// - Returns: A center-cropped square image
    private func cropToSquare(_ image: UIImage) -> UIImage {
        let originalSize = image.size
        let shortestSide = min(originalSize.width, originalSize.height)
        
        // If already square, return as-is
        if originalSize.width == originalSize.height {
            return image
        }
        
        // Calculate the crop rect (centered)
        let cropRect = CGRect(
            x: (originalSize.width - shortestSide) / 2,
            y: (originalSize.height - shortestSide) / 2,
            width: shortestSide,
            height: shortestSide
        )
        
        // Perform the crop
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return image // Return original if cropping fails
        }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // MARK: - Private Methods
    
    private func setupRemoteCommandCenter() {
        let cmd = MPRemoteCommandCenter.shared()
        
        // MARK: Play/Pause Commands
        
        // Play command - explicitly enable
        cmd.playCommand.isEnabled = true
        cmd.playCommand.addTarget { [weak self] _ in
            print("🧠 AI_DEBUG [LOCKSCREEN] Play command received")
            guard let session = self?.activeSession else {
                print("🧠 AI_DEBUG [LOCKSCREEN] No active session for play")
                return .commandFailed
            }
            session.mediaPlay()
            self?.updatePlaybackState(isPlaying: true)
            return .success
        }
        
        // Pause command - only pauses, never resumes.
        // AirPods send pauseCommand on reconnect; if we toggled here,
        // a paused meditation would resume without user intent.
        cmd.pauseCommand.isEnabled = true
        cmd.pauseCommand.addTarget { [weak self] _ in
            print("[LockScreen] Pause command received")
            guard let session = self?.activeSession else {
                print("[LockScreen] No active session for pause")
                return .commandFailed
            }
            if session.mediaIsPlaying {
                session.mediaPause()
                self?.updatePlaybackState(isPlaying: false)
                print("[LockScreen] Paused")
            } else {
                print("[LockScreen] Already paused — ignoring pause command")
            }
            return .success
        }
        
        // Toggle play/pause - used by AirPods single click and headphone button
        cmd.togglePlayPauseCommand.isEnabled = true
        cmd.togglePlayPauseCommand.addTarget { [weak self] _ in
            print("🧠 AI_DEBUG [LOCKSCREEN] Toggle play/pause command received")
            guard let session = self?.activeSession else {
                print("🧠 AI_DEBUG [LOCKSCREEN] No active session for toggle")
                return .commandFailed
            }
            if session.mediaIsPlaying {
                session.mediaPause()
                self?.updatePlaybackState(isPlaying: false)
            } else {
                session.mediaPlay()
                self?.updatePlaybackState(isPlaying: true)
            }
            return .success
        }
        
        // MARK: Skip Commands (Lock Screen UI)
        
        // Skip forward command (15 seconds) - shown on lock screen
        cmd.skipForwardCommand.isEnabled = true
        cmd.skipForwardCommand.preferredIntervals = [15]
        cmd.skipForwardCommand.addTarget { [weak self] _ in
            print("🧠 AI_DEBUG [LOCKSCREEN] Skip forward command received")
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSkipForward(seconds: 15)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        
        // Skip backward command (15 seconds) - shown on lock screen
        cmd.skipBackwardCommand.isEnabled = true
        cmd.skipBackwardCommand.preferredIntervals = [15]
        cmd.skipBackwardCommand.addTarget { [weak self] _ in
            print("🧠 AI_DEBUG [LOCKSCREEN] Skip backward command received")
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSkipBackward(seconds: 15)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        
        // MARK: Track Commands (AirPods double/triple click)
        
        // Next track - AirPods double click (map to skip forward)
        cmd.nextTrackCommand.isEnabled = true
        cmd.nextTrackCommand.addTarget { [weak self] _ in
            print("🧠 AI_DEBUG [LOCKSCREEN] Next track command received (AirPods double click)")
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSkipForward(seconds: 15)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        
        // Previous track - AirPods triple click (map to skip backward)
        cmd.previousTrackCommand.isEnabled = true
        cmd.previousTrackCommand.addTarget { [weak self] _ in
            print("🧠 AI_DEBUG [LOCKSCREEN] Previous track command received (AirPods triple click)")
            guard let session = self?.activeSession else { return .commandFailed }
            session.mediaSkipBackward(seconds: 15)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        
        // Disable commands we don't support
        cmd.seekForwardCommand.isEnabled = false
        cmd.seekBackwardCommand.isEnabled = false
        cmd.changePlaybackRateCommand.isEnabled = false
        cmd.changeRepeatModeCommand.isEnabled = false
        cmd.changeShuffleModeCommand.isEnabled = false
        
        print("🧠 AI_DEBUG [LOCKSCREEN] Remote command center configured (all controls enabled)")
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        cachedArtwork = nil
        cachedArtworkURL = nil
        print("🧠 AI_DEBUG [LOCKSCREEN] Now Playing info cleared")
    }
}

