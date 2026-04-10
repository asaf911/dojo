//
//  CuePlaybackManager.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-24
//

import Foundation
import AVFoundation

class CuePlaybackManager {
    static let shared = CuePlaybackManager()
    
    // MARK: - AVAudioEngine Playback
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sfxPlayerNode = AVAudioPlayerNode()
    private var currentAudioFile: AVAudioFile?
    private var currentSfxAudioFile: AVAudioFile?
    private var currentBoostGain: Float = 1.0
    private var playbackFinished = true
    
    private var volume: Float = 1.0
    
    // MARK: - Volume Boost
    
    /// Legacy per-module boost for IDs that still use the old monolithic naming (e.g. `IM_FRAC` as a single asset).
    /// **Excluded:** atomic fractional clips `IM_C###` / `NF_C###` — same mastering pipeline as body scan (`BS_*`);
    /// those must not get this boost or Dan (no `/asaf/` URL boost) sounds ~+18dB louder than body scan.
    private static let moduleVolumeBoostDB: [String: Float] = [
        "IM": 18.0,
        "NF": 18.0
    ]
    
    /// Boost for fractional voice paths where assets are not pre-amplified to legacy levels (`/asaf/` in cue URL).
    private static let asafVoiceBoostDB: Float = 18.0
    
    /// Converts a dB value to a linear gain multiplier.
    private static func linearGain(forDB db: Float) -> Float {
        pow(10.0, db / 20.0)
    }
    
    /// Legacy table boost only when not an atomic fractional IM/NF clip (those align with BS_* loudness).
    private static func boostGainForLegacyModule(for moduleId: String) -> Float {
        if FractionalCueID.isAtomicMantraOrNostrilClip(moduleId) { return 1.0 }
        for (prefix, db) in moduleVolumeBoostDB {
            if moduleId.hasPrefix(prefix) {
                return linearGain(forDB: db)
            }
        }
        return 1.0
    }
    
    /// Asaf voice boost for new content (URL contains /asaf/).
    private static func asafVoiceBoostGain(for cue: Cue) -> Float {
        guard cue.url.localizedCaseInsensitiveContains("/asaf/") else { return 1.0 }
        return linearGain(forDB: asafVoiceBoostDB)
    }
    
    /// Combined boost: legacy modules first, then Asaf voice for new content.
    private static func boostGain(for cue: Cue) -> Float {
        let legacy = boostGainForLegacyModule(for: cue.id)
        if legacy > 1.0 { return legacy }
        return asafVoiceBoostGain(for: cue)
    }
    
    /// Applies the current user volume multiplied by the per-module boost to the engine mixer.
    private func updateEngineVolume() {
        engine.mainMixerNode.outputVolume = volume * currentBoostGain
    }
    
    // MARK: - State Tracking for Skip/Seek
    
    /// Generation counter to ignore stale completion handlers from previous buffers.
    /// When we stop a cue and start a new one, playerNode.stop() triggers the OLD buffer's
    /// completion handler. That handler schedules DispatchQueue.main.async { playbackFinished = true },
    /// which can run AFTER we've started the new cue - incorrectly setting playbackFinished = true.
    /// By incrementing this before each schedule, we ignore stale completions.
    private var playbackGeneration: Int = 0
    
    /// ID of the currently playing cue
    private(set) var currentCueId: String?
    
    /// When the current cue started playing (session elapsed time in seconds)
    private(set) var cueStartSessionTime: TimeInterval = 0
    
    /// Whether a cue is currently playing (voice and/or parallel SFX).
    var isPlaying: Bool {
        !playbackFinished && (playerNode.isPlaying || sfxPlayerNode.isPlaying)
    }
    
    /// Duration of the currently loaded primary cue audio (voice track).
    var cueDuration: TimeInterval {
        guard let audioFile = currentAudioFile else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }
    
    /// Effective window for skip/seek: max of voice and parallel SFX when present.
    private func effectiveLoadedDuration() -> TimeInterval {
        let v = cueDuration
        if let sfx = currentSfxAudioFile {
            let s = Double(sfx.length) / sfx.processingFormat.sampleRate
            return max(v, s)
        }
        return v
    }
    
    /// Current playback position within the cue
    var currentPosition: TimeInterval {
        guard currentCueId != nil,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return 0 }
        return max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
    }
    
    // MARK: - Preloading System
    
    /// Preloaded cue data: local file URL and exact duration.
    /// Cache key combines cue.id and cue.url so different voices (different URLs) get separate entries.
    private var preloadedCues: [String: (localURL: URL, duration: TimeInterval)] = [:]
    
    /// Cache key that includes URL so same cue ID with different voice (URL) gets a separate cache entry.
    private func preloadCacheKey(for cue: Cue) -> String {
        "\(cue.id)|\(cue.url)"
    }

    private func preloadCacheKey(parallelSfx: ParallelSfxCue) -> String {
        "\(parallelSfx.id)|\(parallelSfx.url)"
    }
    
    // MARK: - Init
    
    private init() {
        engine.attach(playerNode)
        engine.attach(sfxPlayerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        engine.connect(sfxPlayerNode, to: engine.mainMixerNode, format: nil)
    }
    
    // MARK: - Volume
    
    /// Updates the instructions/cues volume (0.0 - 1.0)
    func setVolume(_ value: Float) {
        volume = max(0.0, min(1.0, value))
        updateEngineVolume()
        logger.eventMessage("🧠 AI_DEBUG volumes instructions_update=\(volume)")
    }
    
    // MARK: - Preloading Methods
    
    /// Preloads a single cue file and calculates its exact duration.
    /// - Parameters:
    ///   - cue: The Cue to preload.
    ///   - completion: Called with the duration if successful, nil otherwise.
    func preloadCue(_ cue: Cue, completion: @escaping (TimeInterval?) -> Void) {
        // Skip "None" cues
        if cue.id == "None" || cue.name == "None" || cue.url.isEmpty {
            completion(nil)
            return
        }
        
        // Check if already preloaded (key includes URL so different voices get separate entries)
        let cacheKey = preloadCacheKey(for: cue)
        if let cached = preloadedCues[cacheKey] {
            print("🧠 AI_DEBUG [CUE] Already preloaded \(cue.id): duration=\(String(format: "%.1f", cached.duration))s")
            completion(cached.duration)
            return
        }
        
        guard let remoteURL = URL(string: cue.url) else {
            print("🧠 AI_DEBUG [CUE] Invalid URL for cue preload: \(cue.url)")
            completion(nil)
            return
        }
        
        print("🧠 AI_DEBUG [CUE] Preloading cue \(cue.id) (\(cue.name))...")
        
        FileManagerHelper.shared.ensureLocalFile(for: remoteURL, setDownloading: { _ in }, completion: { [weak self] localURL in
            guard let self = self, let localURL = localURL else {
                print("[Server][Cue] Failed to download cue \(cue.id) (\(cue.name)) url=\(cue.url)")
                print("🧠 AI_DEBUG [CUE] Failed to download cue \(cue.id)")
                completion(nil)
                return
            }
            
            // Read exact duration from AVAudioFile
            do {
                let audioFile = try AVAudioFile(forReading: localURL)
                let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
                self.preloadedCues[self.preloadCacheKey(for: cue)] = (localURL: localURL, duration: duration)
                print("🧠 AI_DEBUG [CUE] Preloaded \(cue.id): duration=\(String(format: "%.1f", duration))s")
                if let ps = cue.parallelSfx, !ps.url.isEmpty {
                    self.preloadParallelSfxOnly(ps) { sfxDuration in
                        let combined: TimeInterval? = {
                            guard let s = sfxDuration else { return duration }
                            return max(duration, s)
                        }()
                        completion(combined)
                    }
                } else {
                    completion(duration)
                }
            } catch {
                print("🧠 AI_DEBUG [CUE] Error preloading cue \(cue.id): \(error.localizedDescription)")
                completion(nil)
            }
        })
    }

    private func preloadParallelSfxOnly(_ ps: ParallelSfxCue, completion: @escaping (TimeInterval?) -> Void) {
        let key = preloadCacheKey(parallelSfx: ps)
        if let cached = preloadedCues[key] {
            completion(cached.duration)
            return
        }
        guard let remoteURL = URL(string: ps.url) else {
            completion(nil)
            return
        }
        FileManagerHelper.shared.ensureLocalFile(for: remoteURL, setDownloading: { _ in }, completion: { [weak self] localURL in
            guard let self = self, let localURL = localURL else {
                completion(nil)
                return
            }
            do {
                let audioFile = try AVAudioFile(forReading: localURL)
                let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
                self.preloadedCues[key] = (localURL: localURL, duration: duration)
                print("🧠 AI_DEBUG [CUE] Preloaded parallel SFX \(ps.id): duration=\(String(format: "%.1f", duration))s")
                completion(duration)
            } catch {
                completion(nil)
            }
        })
    }
    
    /// Preloads multiple cues in parallel.
    /// - Parameters:
    ///   - cues: Array of Cues to preload.
    ///   - completion: Called when all cues have been processed.
    func preloadCues(_ cues: [Cue], completion: @escaping () -> Void) {
        // Filter out "None" cues and duplicates (by id+url so same cue with different voice is separate)
        let validCues = cues.filter { $0.id != "None" && $0.name != "None" && !$0.url.isEmpty }
        var expanded: [Cue] = []
        for cue in validCues {
            expanded.append(cue)
            if let ps = cue.parallelSfx, !ps.url.isEmpty {
                expanded.append(Cue(id: ps.id, name: ps.name, url: ps.url))
            }
        }
        let uniqueCues = Array(Set(expanded.map { preloadCacheKey(for: $0) })).compactMap { key in expanded.first { preloadCacheKey(for: $0) == key } }
        
        guard !uniqueCues.isEmpty else {
            completion()
            return
        }
        
        let group = DispatchGroup()
        
        for cue in uniqueCues {
            group.enter()
            preloadCue(cue) { _ in
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            print("[DEBUG] Finished preloading \(uniqueCues.count) cues")
            completion()
        }
    }
    
    /// Gets the preloaded duration for a cue if available.
    /// Uses cue.id and cue.url so different voices are looked up correctly.
    /// With `parallelSfx`, returns the max of voice and SFX durations for timeline windows.
    func getPreloadedDuration(for cue: Cue) -> TimeInterval? {
        let v = preloadedCues[preloadCacheKey(for: cue)]?.duration
        guard let ps = cue.parallelSfx, !ps.url.isEmpty else { return v }
        let s = preloadedCues[preloadCacheKey(parallelSfx: ps)]?.duration
        switch (v, s) {
        case (let a?, let b?): return max(a, b)
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (nil, nil): return nil
        }
    }
    
    // MARK: - Playback Methods
    
    /// Plays the given cue sound once (or loads it paused for later resume).
    /// - Parameters:
    ///   - cue: The Cue model containing name and URL.
    ///   - sessionElapsedTime: The elapsed time in the session when this cue is triggered.
    ///   - startPaused: If true, load the cue but don't start playing (ready for resume).
    func play(cue: Cue, sessionElapsedTime: TimeInterval = 0, startPaused: Bool = false) {
        // If cue is "None", do nothing.
        if cue.id == "None" || cue.name == "None" || cue.url.isEmpty {
            print("[DEBUG] No cue selected.")
            return
        }
        
        // Check if we have preloaded data (key includes URL so different voices get correct file)
        let cacheKey = preloadCacheKey(for: cue)
        if let preloaded = preloadedCues[cacheKey] {
            playFromLocalURL(preloaded.localURL, cue: cue, sessionElapsedTime: sessionElapsedTime, startPaused: startPaused)
            return
        }
        
        // Fallback to download if not preloaded
        guard ConnectivityHelper.isConnectedToInternet() else {
            print("[DEBUG] No internet connection. Cannot play cue.")
            return
        }
        
        guard let remoteURL = URL(string: cue.url) else {
            print("[DEBUG] Invalid URL for cue: \(cue.url)")
            return
        }
        
        // Ensure local cache using FileManagerHelper.
        FileManagerHelper.shared.ensureLocalFile(for: remoteURL, setDownloading: { downloading in
            print("[DEBUG] Cue ensureLocalFile downloading: \(downloading)")
        }, completion: { [weak self] localURL in
            guard let self = self, let localURL = localURL else {
                print("[Server][Cue] Failed to download cue \(cue.id) (\(cue.name)) url=\(cue.url)")
                print("[DEBUG] Failed to download cue file.")
                return
            }
            self.playFromLocalURL(localURL, cue: cue, sessionElapsedTime: sessionElapsedTime, startPaused: startPaused)
            
            // Cache for future use (key includes URL so different voices get separate entries)
            if let audioFile = self.currentAudioFile {
                let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
                self.preloadedCues[self.preloadCacheKey(for: cue)] = (localURL: localURL, duration: duration)
            }
        })
    }
    
    /// Internal method to play from a local URL using AVAudioEngine.
    private func playFromLocalURL(_ localURL: URL, cue: Cue, sessionElapsedTime: TimeInterval, startPaused: Bool = false) {
        do {
            playerNode.stop()
            sfxPlayerNode.stop()
            currentSfxAudioFile = nil

            let audioFile = try AVAudioFile(forReading: localURL)
            currentAudioFile = audioFile

            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: audioFile.processingFormat)

            currentBoostGain = Self.boostGain(for: cue)
            updateEngineVolume()

            if currentBoostGain > 1.0 {
                let tableDB = Self.moduleVolumeBoostDB.first { cue.id.hasPrefix($0.key) }?.value
                let legacyDB: Float? = {
                    guard let db = tableDB, !FractionalCueID.isAtomicMantraOrNostrilClip(cue.id) else { return nil }
                    return db
                }()
                let source = legacyDB.map { "legacy +\(Int($0))dB" } ?? "Asaf voice +\(Int(Self.asafVoiceBoostDB))dB"
                print("🧠 AI_DEBUG [CUE] Volume boost for \(cue.id): \(source) (x\(String(format: "%.2f", currentBoostGain)))")
            }

            if !engine.isRunning {
                try engine.start()
            }

            currentCueId = cue.id
            cueStartSessionTime = sessionElapsedTime
            playbackFinished = false
            playbackGeneration += 1
            let generation = playbackGeneration

            let voiceDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

            if let ps = cue.parallelSfx, !ps.url.isEmpty {
                let sfxKey = preloadCacheKey(parallelSfx: ps)
                if let preloaded = preloadedCues[sfxKey] {
                    try scheduleVoiceAndParallelAndStart(
                        audioFile: audioFile,
                        cue: cue,
                        sessionElapsedTime: sessionElapsedTime,
                        startPaused: startPaused,
                        voiceDuration: voiceDuration,
                        generation: generation,
                        sfxLocalURL: preloaded.localURL
                    )
                } else if let sfxRemote = URL(string: ps.url) {
                    FileManagerHelper.shared.ensureLocalFile(for: sfxRemote, setDownloading: { _ in }, completion: { [weak self] sfxLocal in
                        guard let self = self else { return }
                        guard self.playbackGeneration == generation else { return }
                        guard let sfxLocal = sfxLocal else {
                            print("🧠 AI_DEBUG [CUE] Parallel SFX missing for \(cue.id); playing voice only")
                            try? self.scheduleVoiceOnlyAndStart(
                                audioFile: audioFile,
                                cue: cue,
                                sessionElapsedTime: sessionElapsedTime,
                                startPaused: startPaused,
                                voiceDuration: voiceDuration,
                                generation: generation
                            )
                            return
                        }
                        if let sfxFile = try? AVAudioFile(forReading: sfxLocal) {
                            let d = Double(sfxFile.length) / sfxFile.processingFormat.sampleRate
                            self.preloadedCues[sfxKey] = (localURL: sfxLocal, duration: d)
                        }
                        do {
                            try self.scheduleVoiceAndParallelAndStart(
                                audioFile: audioFile,
                                cue: cue,
                                sessionElapsedTime: sessionElapsedTime,
                                startPaused: startPaused,
                                voiceDuration: voiceDuration,
                                generation: generation,
                                sfxLocalURL: sfxLocal
                            )
                        } catch {
                            try? self.scheduleVoiceOnlyAndStart(
                                audioFile: audioFile,
                                cue: cue,
                                sessionElapsedTime: sessionElapsedTime,
                                startPaused: startPaused,
                                voiceDuration: voiceDuration,
                                generation: generation
                            )
                        }
                    })
                } else {
                    try scheduleVoiceOnlyAndStart(
                        audioFile: audioFile,
                        cue: cue,
                        sessionElapsedTime: sessionElapsedTime,
                        startPaused: startPaused,
                        voiceDuration: voiceDuration,
                        generation: generation
                    )
                }
            } else {
                try scheduleVoiceOnlyAndStart(
                    audioFile: audioFile,
                    cue: cue,
                    sessionElapsedTime: sessionElapsedTime,
                    startPaused: startPaused,
                    voiceDuration: voiceDuration,
                    generation: generation
                )
            }
        } catch {
            print("🧠 AI_DEBUG [CUE] Error playing cue: \(error.localizedDescription)")
            clearCueState()
        }
    }

    private func scheduleVoiceOnlyAndStart(
        audioFile: AVAudioFile,
        cue: Cue,
        sessionElapsedTime: TimeInterval,
        startPaused: Bool,
        voiceDuration: TimeInterval,
        generation: Int
    ) throws {
        let group = DispatchGroup()
        group.enter()
        playerNode.scheduleFile(audioFile, at: nil) { DispatchQueue.main.async { group.leave() } }
        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.playbackGeneration == generation else { return }
            self.playbackFinished = true
        }
        if startPaused {
            print("🧠 AI_DEBUG [CUE] Loaded \(cue.id) (\(cue.name)) PAUSED at session time \(String(format: "%.1f", sessionElapsedTime))s, duration=\(String(format: "%.1f", voiceDuration))s")
        } else {
            playerNode.play()
            print("🧠 AI_DEBUG [CUE] Playing \(cue.id) (\(cue.name)) at session time \(String(format: "%.1f", sessionElapsedTime))s, duration=\(String(format: "%.1f", voiceDuration))s")
        }
    }

    private func scheduleVoiceAndParallelAndStart(
        audioFile: AVAudioFile,
        cue: Cue,
        sessionElapsedTime: TimeInterval,
        startPaused: Bool,
        voiceDuration: TimeInterval,
        generation: Int,
        sfxLocalURL: URL
    ) throws {
        let group = DispatchGroup()
        group.enter()
        playerNode.scheduleFile(audioFile, at: nil) { DispatchQueue.main.async { group.leave() } }

        group.enter()
        let sfxFile = try AVAudioFile(forReading: sfxLocalURL)
        currentSfxAudioFile = sfxFile
        engine.disconnectNodeOutput(sfxPlayerNode)
        engine.connect(sfxPlayerNode, to: engine.mainMixerNode, format: sfxFile.processingFormat)
        sfxPlayerNode.scheduleFile(sfxFile, at: nil) { DispatchQueue.main.async { group.leave() } }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.playbackGeneration == generation else { return }
            self.playbackFinished = true
        }

        if startPaused {
            print("🧠 AI_DEBUG [CUE] Loaded \(cue.id) (\(cue.name))+SFX PAUSED at session time \(String(format: "%.1f", sessionElapsedTime))s")
        } else {
            playerNode.play()
            sfxPlayerNode.play()
            print("🧠 AI_DEBUG [CUE] Playing \(cue.id) (\(cue.name))+parallel SFX at session time \(String(format: "%.1f", sessionElapsedTime))s, voice=\(String(format: "%.1f", voiceDuration))s")
        }
    }
    
    // MARK: - Seeking Methods
    
    /// Seeks within the currently playing cue to a specific position.
    /// - Parameter time: The position within the cue to seek to (in seconds).
    func seek(to time: TimeInterval) {
        guard let audioFile = currentAudioFile else {
            print("🧠 AI_DEBUG [CUE] Cannot seek - no cue loaded")
            return
        }

        let effDuration = effectiveLoadedDuration()
        let clampedSeek = max(0, min(time, effDuration))

        let wasPlaying = isPlaying
        playerNode.stop()
        sfxPlayerNode.stop()
        playbackFinished = false
        playbackGeneration += 1
        let generation = playbackGeneration

        let group = DispatchGroup()

        // Per-track seek seconds: `effDuration` is max(voice, parallel SFX). Using that same value for
        // both `scheduleSegment` calls can push the shorter track past its end → frameCount 0 →
        // AVAudioPlayerNode assertion ("numberFrames > 0"). Clamp each file independently.
        let vRate = audioFile.processingFormat.sampleRate
        let vTotal = audioFile.length
        let voiceDurationSec = Double(vTotal) / vRate
        let voiceSeekSec = min(clampedSeek, voiceDurationSec)
        let vTarget = AVAudioFramePosition(voiceSeekSec * vRate)
        let vClamped = max(0, min(vTarget, vTotal))
        let vRemaining = AVAudioFrameCount(vTotal - vClamped)

        func completeTrackInGroup() {
            group.enter()
            DispatchQueue.main.async { group.leave() }
        }

        if vRemaining > 0 {
            group.enter()
            playerNode.scheduleSegment(audioFile, startingFrame: vClamped, frameCount: vRemaining, at: nil) { [weak self] in
                DispatchQueue.main.async { group.leave() }
            }
        } else {
            completeTrackInGroup()
        }

        var sfxRemaining: AVAudioFrameCount = 0
        if let sfxFile = currentSfxAudioFile {
            let sRate = sfxFile.processingFormat.sampleRate
            let sTotal = sfxFile.length
            let sfxDurationSec = Double(sTotal) / sRate
            let sfxSeekSec = min(clampedSeek, sfxDurationSec)
            let sTarget = AVAudioFramePosition(sfxSeekSec * sRate)
            let sClamped = max(0, min(sTarget, sTotal))
            let sRemaining = AVAudioFrameCount(sTotal - sClamped)
            sfxRemaining = sRemaining
            if sRemaining > 0 {
                group.enter()
                sfxPlayerNode.scheduleSegment(sfxFile, startingFrame: sClamped, frameCount: sRemaining, at: nil) { [weak self] in
                    DispatchQueue.main.async { group.leave() }
                }
            } else {
                completeTrackInGroup()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.playbackGeneration == generation else { return }
            self.playbackFinished = true
        }

        if wasPlaying {
            if vRemaining > 0 {
                playerNode.play()
            }
            if sfxRemaining > 0 {
                sfxPlayerNode.play()
            }
        }

        print("🧠 AI_DEBUG [CUE] Seeked combined cue to \(String(format: "%.2f", clampedSeek))s / \(String(format: "%.2f", effDuration))s (voiceSeek=\(String(format: "%.2f", voiceSeekSec))s)")
    }
    
    /// Stops the current cue and clears tracking state.
    func stop() {
        let wasPlaying = currentCueId
        playbackGeneration += 1
        playerNode.stop()
        sfxPlayerNode.stop()
        currentAudioFile = nil
        currentSfxAudioFile = nil
        playbackFinished = true
        clearCueState()
        print("🧠 AI_DEBUG [CUE] Stopped cue \(wasPlaying ?? "none")")
    }
    
    /// Gets info about the currently playing cue.
    /// - Returns: Tuple with cue ID, start time, and duration, or nil if no cue is playing.
    func getCurrentCueInfo() -> (id: String, startTime: TimeInterval, duration: TimeInterval)? {
        guard let cueId = currentCueId, currentAudioFile != nil else {
            return nil
        }
        return (id: cueId, startTime: cueStartSessionTime, duration: effectiveLoadedDuration())
    }
    
    /// Clears the cue state tracking.
    private func clearCueState() {
        currentCueId = nil
        cueStartSessionTime = 0
    }
    
    // MARK: - Existing Methods
    
    /// Fades out the currently playing cue sound over the specified duration.
    /// - Parameter fadeDuration: The duration over which to fade out the cue.
    func fadeOutCurrentCue(withDuration fadeDuration: TimeInterval = 1.0) {
        guard currentCueId != nil, !playbackFinished else { return }
        let fadeSteps = Int(fadeDuration / 0.1)
        let startVolume = engine.mainMixerNode.outputVolume
        let stepVolume = startVolume / Float(fadeSteps)
        var currentStep = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if currentStep >= fadeSteps {
                self.playerNode.stop()
                self.sfxPlayerNode.stop()
                self.currentSfxAudioFile = nil
                self.playbackFinished = true
                self.clearCueState()
                self.updateEngineVolume() // Restore proper volume for next cue
                timer.invalidate()
                print("[DEBUG] Cue faded out and stopped.")
            } else {
                self.engine.mainMixerNode.outputVolume = max(startVolume - stepVolume * Float(currentStep + 1), 0)
                currentStep += 1
            }
        }
        timer.fire() // Start fading immediately.
    }
    
    /// Pauses the currently playing cue sound.
    func pause() {
        let shouldPause = currentCueId != nil && !playbackFinished
        print("🧠 AI_DEBUG [CUE] pause() called - cueId=\(currentCueId ?? "none"), playbackFinished=\(playbackFinished), playerNode.isPlaying=\(playerNode.isPlaying) -> \(shouldPause ? "PAUSING" : "skipped (no active cue)")")
        if shouldPause {
            playerNode.pause()
            sfxPlayerNode.pause()
            print("🧠 AI_DEBUG [CUE] Paused \(currentCueId ?? "unknown") at \(String(format: "%.1f", currentPosition))s")
        }
    }
    
    /// Resumes the cue sound from where it was paused.
    func resume() {
        print("🧠 AI_DEBUG [CUE] resume() called - cueId=\(currentCueId ?? "none"), position=\(String(format: "%.1f", currentPosition))s")
        if currentAudioFile != nil && !playbackFinished {
            if !engine.isRunning {
                try? engine.start()
            }
            playerNode.play()
            if currentSfxAudioFile != nil {
                sfxPlayerNode.play()
            }
            print("🧠 AI_DEBUG [CUE] Resumed \(currentCueId ?? "unknown") from \(String(format: "%.1f", currentPosition))s")
        } else {
            print("🧠 AI_DEBUG [CUE] Cannot resume - no audio file loaded")
        }
    }
}
