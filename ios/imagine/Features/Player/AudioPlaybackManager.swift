//
//  AudioPlaybackManager.swift
//

import AVFoundation

protocol AudioPlaybackDelegate: AnyObject {
    func playbackDidFinishSuccessfully()
    func playbackProgressDidUpdate(currentTime: TimeInterval, duration: TimeInterval)
    func playbackDidFail(with error: Error)
}

class AudioPlaybackManager: NSObject, AVAudioPlayerDelegate {
    var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    
    weak var delegate: AudioPlaybackDelegate?
    
    var isPlaying: Bool {
        return audioPlayer?.isPlaying ?? false
    }
    
    var currentTime: TimeInterval {
        return audioPlayer?.currentTime ?? 0
    }
    
    var duration: TimeInterval {
        return audioPlayer?.duration ?? 0
    }
    
    func startPlaying(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            // Auto-start playback
            play()
        } catch {
            delegate?.playbackDidFail(with: error)
        }
    }
    
    /// Prepares the audio player without starting playback.
    func prepareToPlay(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
        } catch {
            delegate?.playbackDidFail(with: error)
        }
    }
    
    func play() {
        audioPlayer?.play()
        startProgressTimer()
    }
    
    func pause() {
        audioPlayer?.pause()
        stopProgressTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        stopProgressTimer()
    }
    
    func skipForward(seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let newTime = player.currentTime + seconds
        if newTime >= player.duration {
            player.currentTime = player.duration
            player.stop()
            stopProgressTimer()
            updateProgress()
            delegate?.playbackDidFinishSuccessfully()
        } else {
            player.currentTime = newTime
            updateProgress()
        }
    }
    
    func skipBackward(seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = max(player.currentTime - seconds, 0)
        updateProgress()
    }
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(timeInterval: 0.5,
                                             target: self,
                                             selector: #selector(updateProgress),
                                             userInfo: nil,
                                             repeats: true)
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    @objc private func updateProgress() {
        guard let player = audioPlayer else { return }
        delegate?.playbackProgressDidUpdate(currentTime: player.currentTime, duration: player.duration)
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopProgressTimer()
        updateProgress()
        if flag {
            delegate?.playbackDidFinishSuccessfully()
        } else {
            let error = NSError(domain: "AudioPlaybackManager",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Audio playback finished unsuccessfully"])
            delegate?.playbackDidFail(with: error)
        }
    }
}
