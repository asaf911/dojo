//
//  GuidedMeditationSession.swift
//  Dojo
//
//  Session implementation for pre-recorded (MP3) guided meditations.
//  Wraps the existing AudioPlayerManager.
//

import Foundation
import Combine

/// Guided meditation session that wraps AudioPlayerManager for MP3 playback
class GuidedMeditationSession: ObservableObject, PlayableSession {
    
    // MARK: - MeditationSession Protocol Properties
    
    let sessionType: SessionType = .guided
    
    var isPlaying: Bool {
        audioPlayerManager.isPlaying
    }
    
    var progress: Double {
        guard audioPlayerManager.totalDuration > 0 else { return 0 }
        return audioPlayerManager.currentTime / audioPlayerManager.totalDuration
    }
    
    var currentTimeDisplay: String {
        AppFunctions.formatTime(audioPlayerManager.currentTime)
    }
    
    var totalTimeDisplay: String {
        AppFunctions.formatTime(audioPlayerManager.totalDuration)
    }
    
    var totalDuration: TimeInterval {
        audioPlayerManager.totalDuration
    }
    
    var hasFinished: Bool {
        audioPlayerManager.didJustFinishSession
    }
    
    var hasReached75Percent: Bool {
        audioPlayerManager.hasReached75Percent
    }
    
    var onSessionComplete: (() -> Void)? {
        get { audioPlayerManager.onSessionComplete }
        set { audioPlayerManager.onSessionComplete = newValue }
    }
    
    // MARK: - Guided Session Specific Properties
    
    /// The underlying audio player manager
    let audioPlayerManager: AudioPlayerManager
    
    /// The audio file being played
    var audioFile: AudioFile? {
        audioPlayerManager.selectedFile
    }
    
    /// Content details for analytics
    var contentDetails: String {
        audioPlayerManager.contentDetails
    }
    
    /// Image URL for the practice
    var imageURL: String? {
        audioPlayerManager.selectedFile?.imageFile
    }
    
    /// Whether audio is currently downloading
    var isDownloading: Bool {
        audioPlayerManager.isDownloading
    }
    
    /// Current time in seconds
    var currentTime: TimeInterval {
        audioPlayerManager.currentTime
    }
    
    /// Remaining time in seconds
    var remainingTime: TimeInterval {
        audioPlayerManager.remainingTime
    }
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(audioPlayerManager: AudioPlayerManager) {
        self.audioPlayerManager = audioPlayerManager
        
        // Forward published changes from AudioPlayerManager
        audioPlayerManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - MeditationSession Protocol Methods
    
    func start() {
        audioPlayerManager.play()
    }
    
    func pause() {
        audioPlayerManager.pause()
    }
    
    func stop() {
        audioPlayerManager.stopAudio()
    }
    
    func seek(seconds: TimeInterval) {
        if seconds > 0 {
            audioPlayerManager.skipForward()
        } else if seconds < 0 {
            audioPlayerManager.skipBackward()
        }
    }
    
    // MARK: - Additional Methods
    
    /// Preload an audio file for playback
    func preload(file: AudioFile, durationIndex: Int, completion: @escaping () -> Void) {
        audioPlayerManager.preloadAudioFile(file: file, durationIndex: durationIndex, completion: completion)
    }
    
    /// End the session and cleanup
    func endSession(completion: (() -> Void)? = nil) {
        audioPlayerManager.endSession(completion: completion)
    }
    
    /// Skip forward by 15 seconds
    func skipForward() {
        audioPlayerManager.skipForward()
    }
    
    /// Skip backward by 15 seconds
    func skipBackward() {
        audioPlayerManager.skipBackward()
    }
}

