//
//  MediaSessionProtocol.swift
//  Dojo
//
//  Protocol defining the interface for media sessions that can be displayed
//  on the iOS lock screen via MPNowPlayingInfoCenter.
//

import Foundation

/// Protocol that any playable session must conform to for lock screen integration.
/// Both guided (MP3) sessions and timer (custom meditation) sessions implement this.
protocol MediaSessionProtocol: AnyObject {
    /// Title displayed on lock screen (e.g., meditation name or current cue)
    var mediaTitle: String { get }
    
    /// Subtitle displayed on lock screen (e.g., duration or description)
    var mediaSubtitle: String? { get }
    
    /// Total duration of the session in seconds
    var mediaDuration: TimeInterval { get }
    
    /// Current elapsed time in seconds
    var mediaElapsedTime: TimeInterval { get }
    
    /// Whether the session is currently playing
    var mediaIsPlaying: Bool { get }
    
    /// Optional artwork URL for the lock screen (remote images)
    var mediaArtworkURL: URL? { get }
    
    /// Optional local asset name for the lock screen (bundle images)
    var mediaLocalArtworkName: String? { get }
    
    // MARK: - Playback Controls
    
    /// Start or resume playback
    func mediaPlay()
    
    /// Pause playback
    func mediaPause()
    
    /// Skip forward by the specified number of seconds
    func mediaSkipForward(seconds: Int)
    
    /// Skip backward by the specified number of seconds
    func mediaSkipBackward(seconds: Int)
}

