//
//  MeditationSession.swift
//  Dojo
//
//  Protocol defining the common interface for all meditation session types.
//

import Foundation
import Combine

/// Enum defining the type of meditation session
enum SessionType {
    case guided  // MP3 playback (pre-recorded)
    case timer   // Countdown with audio layers (custom meditation)
    
    var supportsSkip: Bool {
        // Both guided and timer sessions now support skip forward/backward
        true
    }
    
    var analyticsPrefix: String {
        switch self {
        case .guided: return "practice"
        case .timer: return "timer"
        }
    }
}

/// Protocol that all meditation session types must implement
protocol MeditationSession: ObservableObject {
    /// The type of session (guided or timer)
    var sessionType: SessionType { get }
    
    /// Whether the session is currently playing
    var isPlaying: Bool { get }
    
    /// Progress from 0.0 to 1.0
    var progress: Double { get }
    
    /// Current time display string (e.g., "05:30")
    /// For guided: elapsed time
    /// For timer: remaining time
    var currentTimeDisplay: String { get }
    
    /// Total time display string (e.g., "10:00")
    /// For guided: total duration
    /// For timer: can be empty or total
    var totalTimeDisplay: String { get }
    
    /// Total duration in seconds
    var totalDuration: TimeInterval { get }
    
    /// Whether the session supports seeking (skip forward/backward)
    var canSeek: Bool { get }
    
    /// Whether the session has finished
    var hasFinished: Bool { get }
    
    /// Whether the session has reached 75% completion (for rating prompt)
    var hasReached75Percent: Bool { get }
    
    /// Callback when session completes
    var onSessionComplete: (() -> Void)? { get set }
    
    /// Start or resume playback
    func start()
    
    /// Pause playback
    func pause()
    
    /// Stop and cleanup the session
    func stop()
    
    /// Seek by a number of seconds (positive = forward, negative = backward)
    /// No-op for timer sessions
    func seek(seconds: TimeInterval)
}

/// Extension with default implementations
extension MeditationSession {
    var canSeek: Bool {
        sessionType.supportsSkip
    }
}

