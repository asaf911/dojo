//
//  TimerMeditationSession.swift
//  Dojo
//
//  Session implementation for timer-based custom meditations.
//  Wraps MeditationSessionTimer and manages audio layers (ambience, binaural, cues).
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

/// Configuration for a timer meditation session
struct TimerSessionConfig {
    /// Practice duration in minutes (user-selected); used for display and analytics.
    let minutes: Int
    /// When set, total countdown/play length includes intro prelude (e.g. `INT_FRAC`) before practice.
    let playbackDurationSeconds: Int?
    let backgroundSound: BackgroundSound
    let binauralBeat: BinauralBeat
    let cueSettings: [CueSetting]
    let isDeepLinked: Bool
    
    /// Optional title for the meditation (from AI or user)
    let title: String?
    /// Optional description for the meditation (from AI)
    let description: String?
    
    init(
        minutes: Int,
        playbackDurationSeconds: Int? = nil,
        backgroundSound: BackgroundSound = BackgroundSound(id: "None", name: "None", url: ""),
        binauralBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil),
        cueSettings: [CueSetting] = [],
        isDeepLinked: Bool = false,
        title: String? = nil,
        description: String? = nil
    ) {
        self.minutes = minutes
        self.playbackDurationSeconds = playbackDurationSeconds
        self.backgroundSound = backgroundSound
        self.binauralBeat = binauralBeat
        self.cueSettings = cueSettings
        self.isDeepLinked = isDeepLinked
        self.title = title
        self.description = description
    }
}

extension TimerSessionConfig {
    /// Background, binaural (when selected), every cue voice URL, and every `parallelSfx` URL — deduplicated.
    /// Used for offline checks and pre-start downloads so Perfect Breath (and similar) cache `PBS_IN` / `PBS_OUT`.
    func allTimerAssetRemoteURLStrings() -> [String] {
        var urls: [String] = []
        if !backgroundSound.url.isEmpty, backgroundSound.id != "None" {
            urls.append(backgroundSound.url)
        }
        if !binauralBeat.url.isEmpty, binauralBeat.id != "None" {
            urls.append(binauralBeat.url)
        }
        for setting in cueSettings {
            let c = setting.cue
            if !c.url.isEmpty {
                urls.append(c.url)
            }
            if let ps = c.parallelSfx, !ps.url.isEmpty {
                urls.append(ps.url)
            }
        }
        return Array(Set(urls))
    }

    /// Seconds of intro prelude before the practice clock reads `00:00`.
    /// When `playbackDurationSeconds` is set, derives from total − practice. Otherwise matches server intro curve
    /// for `INT_FRAC@start` or for **expanded** intro clips (`INT_GRT_*`, `INT_ARR_*`, …) after `expandFractionalCues`.
    var introPrefixSeconds: Int {
        if let playback = playbackDurationSeconds {
            let practice = minutes * 60
            return max(0, playback - practice)
        }
        let practiceSec = minutes * 60
        if cueSettings.contains(where: { $0.cue.id == "INT_FRAC" && $0.triggerType == .start }) {
            return IntroPrefixTimeline.introPrefixSeconds(practiceDurationSec: practiceSec)
        }
        if cueSettings.contains(where: { $0.cue.id.hasPrefix("INT_") }) {
            return IntroPrefixTimeline.introPrefixSeconds(practiceDurationSec: practiceSec)
        }
        return 0
    }

    /// Latest absolute session second at which any cue **starts** (expanded server cues use `.second` wall-clock times).
    func maxAbsoluteScheduledCueSecond() -> Int {
        let intro = introPrefixSeconds
        var m = 0
        for cs in cueSettings {
            switch cs.triggerType {
            case .second:
                m = max(m, cs.minute ?? 0)
            case .minute:
                m = max(m, intro + (cs.minute ?? 0) * 60)
            case .start:
                m = max(m, 0)
            case .end:
                m = max(m, intro + minutes * 60)
            }
        }
        return m
    }

    /// Seconds after the last scheduled cue start to allow the final fractional clip to finish (composer may pack starts near the end).
    private static let scheduledCueTailSecondsAfterLastStart = 30

    /// Wall-clock countdown length: honors `playbackDurationSeconds` when set; otherwise practice + inferred intro (see `introPrefixSeconds`).
    /// Never shorter than the expanded cue schedule plus a short tail so the last clip can finish.
    func resolvedTimerTotalSeconds() -> Int {
        let practiceSec = minutes * 60
        let base: Int
        if let playback = playbackDurationSeconds {
            base = playback
        } else {
            base = practiceSec + introPrefixSeconds
        }
        let maxStart = maxAbsoluteScheduledCueSecond()
        let scheduleFloor = maxStart + Self.scheduledCueTailSecondsAfterLastStart
        return max(base, scheduleFloor)
    }

    /// Cues for the Create / Timer editor: practice-minute rows and fractional modules, not expanded clips or wall-clock seconds.
    /// Call this when opening the editor from the player (playback config uses `.second` and atomic clip IDs after server expansion / intro shift).
    func cueSettingsForTimerEditor() -> [CueSetting] {
        cueSettings
            .normalizedPlaybackCuesForTimerEditor(introPrefixSeconds: introPrefixSeconds, practiceMinutes: minutes)
            .collapsedFractionalCues(meditationMinutes: minutes)
            .convertingNonFractionalSecondTriggersForTimerEditor(practiceMinutes: minutes)
    }
}

/// Timer meditation session that wraps MeditationSessionTimer and audio layers
class TimerMeditationSession: ObservableObject, PlayableSession {
    
    // MARK: - MeditationSession Protocol Properties
    
    let sessionType: SessionType = .timer
    
    var isPlaying: Bool {
        timerManager.isRunning
    }
    
    var progress: Double {
        guard timerManager.totalDuration > 0 else { return 0 }
        return timerManager.currentProgress / timerManager.totalDuration
    }
    
    /// For timer: shows remaining time (countdown)
    var currentTimeDisplay: String {
        formatTime(timerManager.remainingSeconds)
    }
    
    /// Elapsed time display (for progress bar - time counting up)
    var elapsedTimeDisplay: String {
        let elapsed = timerManager.totalSeconds - timerManager.remainingSeconds
        return formatTime(elapsed)
    }

    /// Player UI: during intro shows remaining intro as `-MM:SS` (e.g. `-00:18`); after that, practice elapsed from `00:00`.
    var playerElapsedTimeDisplay: String {
        let elapsed = timerManager.totalSeconds - timerManager.remainingSeconds
        let intro = config.introPrefixSeconds
        if intro <= 0 {
            return formatTime(elapsed)
        }
        if elapsed < intro {
            let remainingIntro = intro - elapsed
            return "-\(formatTime(remainingIntro))"
        }
        return formatTime(elapsed - intro)
    }

    /// Player UI: total shown as practice length when intro exists so left/right match the meditation timeline.
    var playerTotalTimeDisplay: String {
        if config.introPrefixSeconds > 0 {
            return formatTime(config.minutes * 60)
        }
        return totalTimeDisplay
    }

    /// Fraction along the full session bar where practice starts (`00:00`), for a marker line.
    var practiceStartBarFraction: CGFloat? {
        let intro = config.introPrefixSeconds
        let total = timerManager.totalSeconds
        guard intro > 0, total > 0, intro < total else { return nil }
        return CGFloat(intro) / CGFloat(total)
    }
    
    /// For timer: shows total duration
    var totalTimeDisplay: String {
        formatTime(timerManager.totalSeconds)
    }
    
    var totalDuration: TimeInterval {
        timerManager.totalDuration
    }
    
    var hasFinished: Bool {
        timerManager.remainingSeconds <= 0
    }
    
    var hasReached75Percent: Bool {
        timerManager.hasReached75Percent
    }
    
    var onSessionComplete: (() -> Void)? {
        get { _onSessionComplete }
        set {
            _onSessionComplete = newValue
            timerManager.onSessionComplete = { [weak self] in
                self?.handleSessionComplete()
            }
        }
    }
    private var _onSessionComplete: (() -> Void)?
    
    // MARK: - Timer Session Specific Properties
    
    /// The underlying timer manager
    let timerManager: MeditationSessionTimer
    
    /// Configuration
    let config: TimerSessionConfig
    
    /// Volume store for persisting user preferences
    @ObservedObject private var volumeStore = CustomMeditationVolumeStore.shared
    
    /// Audio layer managers
    private var backgroundSoundManager = MeditationAudioManager()
    private var binauralBeatManager = BinauralBeatAudioManager()
    
    /// Volume levels
    @Published var instructionsVolume: Float = 0.5
    @Published var ambienceVolume: Float = 0.5
    @Published var binauralVolume: Float = 0.25
    
    /// Track which cues have been played
    private var playedCues = Set<UUID>()
    
    /// Flag to track if fade out has started
    private var fadeOutStarted = false
    
    /// Flag to track if the session has been started (audio layers initialized)
    private var hasStarted = false
    
    /// Flag to track if the session is completing (prevents further interactions)
    private var isCompleting = false
    
    /// Tracks if session was playing before an audio interruption (phone call, Siri, etc.)
    private var wasPlayingBeforeInterruption = false
    
    /// Whether this session was initialized via deep link
    var isDeepLinked: Bool {
        config.isDeepLinked
    }
    
    /// Remaining seconds for display
    var remainingSeconds: Int {
        timerManager.remainingSeconds
    }
    
    /// Total seconds for display
    var totalSeconds: Int {
        timerManager.totalSeconds
    }
    
    /// Whether background sound is enabled
    var hasBackgroundSound: Bool {
        config.backgroundSound.name != "None" && !config.backgroundSound.url.isEmpty
    }
    
    /// Whether binaural beats are enabled
    var hasBinauralBeat: Bool {
        config.binauralBeat.name != "None" && !config.binauralBeat.url.isEmpty
    }
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()

#if DEBUG
    private func traceTimerSession(_ message: String) { print(message) }
#else
    private func traceTimerSession(_ message: String) {}
#endif
    
    // MARK: - Initialization
    
    init(config: TimerSessionConfig) {
        self.config = config
        let totalSec = config.resolvedTimerTotalSeconds()
        self.timerManager = MeditationSessionTimer(
            totalSeconds: totalSec,
            cueSettings: config.cueSettings,
            title: config.title,
            description: config.description
        )
        timerManager.historyPracticeDurationMinutes = config.minutes
        timerManager.historyPlaybackDurationSeconds = config.playbackDurationSeconds
        
        setupBindings()
        initializeVolumes()
        configureTimerAnalytics()
        setupInterruptionHandling()
        
        // Log session preload event (session configured but not yet started)
        AnalyticsRouter.shared.logSessionPreload()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
    }
    
    private func setupBindings() {
        // Forward published changes from timer manager
        timerManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Monitor remaining seconds for cue triggers and fade out
        timerManager.$remainingSeconds
            .sink { [weak self] remaining in
                self?.handleTimeUpdate(remaining: remaining)
            }
            .store(in: &cancellables)
    }
    
    private func initializeVolumes() {
        instructionsVolume = volumeStore.instructions
        ambienceVolume = volumeStore.ambience
        binauralVolume = volumeStore.binaural
        
        // Apply volume transformation (bias + 50% more impact) to actual audio levels
        let actualInstructions = transformVolume(instructionsVolume, bias: Self.instructionsBias)
        let actualAmbience = transformVolume(ambienceVolume, bias: Self.ambienceBias)
        let actualBinaural = transformVolume(binauralVolume, bias: Self.binauralBias)
        
        CuePlaybackManager.shared.setVolume(actualInstructions)
        backgroundSoundManager.setVolume(actualAmbience, animated: false)
        binauralBeatManager.setVolume(actualBinaural, animated: false)
    }
    
    private func configureTimerAnalytics() {
        // Set background sound properties for analytics
        if hasBackgroundSound {
            timerManager.backgroundSoundUsed = true
            timerManager.backgroundSoundName = config.backgroundSound.name
        } else {
            timerManager.backgroundSoundUsed = false
            timerManager.backgroundSoundName = ""
        }
        
        // Set binaural beat properties for analytics
        if hasBinauralBeat {
            timerManager.binauralBeatUsed = true
            timerManager.binauralBeatName = config.binauralBeat.name
            timerManager.binauralBeatId = config.binauralBeat.id
        } else {
            timerManager.binauralBeatUsed = false
            timerManager.binauralBeatName = ""
            timerManager.binauralBeatId = ""
        }
    }
    
    // MARK: - Audio Interruption Handling
    
    /// Sets up observer for audio session interruptions (phone calls, Siri, etc.)
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        traceTimerSession("🧠 AI_DEBUG [SESSION] Audio interruption handling configured")
    }
    
    /// Handles audio session interruptions (phone calls, Siri, alarms, etc.)
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Interruption began (e.g., incoming call)
            traceTimerSession("🧠 AI_DEBUG [SESSION] Audio interruption BEGAN - wasPlaying=\(isPlaying)")
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                // Use full pause() - AVAudioEngine/AVAudioPlayerNode (cues) are NOT auto-paused by iOS
                pause()
            }
            
        case .ended:
            // Interruption ended
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                traceTimerSession("🧠 AI_DEBUG [SESSION] Audio interruption ENDED - no options")
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            traceTimerSession("🧠 AI_DEBUG [SESSION] Audio interruption ENDED - shouldResume=\(options.contains(.shouldResume)), wasPlaying=\(wasPlayingBeforeInterruption)")
            
            if options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                // Audio session reactivation is handled by AppAudioLifecycleController
                // on foreground. Just resume the audio layers here.
                resumeAfterInterruption()
            }
            
        @unknown default:
            break
        }
    }
    
    /// Resumes all audio layers after an interruption ends
    private func resumeAfterInterruption() {
        traceTimerSession("🧠 AI_DEBUG [SESSION] Resuming after interruption...")
        
        timerManager.start()
        resumeAllAudio()
        
        // Update lock screen
        LockScreenMediaService.shared.updatePlaybackState(isPlaying: true)
        
        traceTimerSession("🧠 AI_DEBUG [SESSION] All audio layers resumed after interruption")
    }
    
    /// Pauses all audio layers (background, binaural, cues). Single place for coordination.
    private func pauseAllAudio() {
        if hasBackgroundSound { backgroundSoundManager.pause() }
        if hasBinauralBeat { binauralBeatManager.pause() }
        CuePlaybackManager.shared.pause()
    }
    
    /// Resumes all audio layers (background, binaural, cues). Single place for coordination.
    private func resumeAllAudio() {
        if hasBackgroundSound { backgroundSoundManager.resume() }
        if hasBinauralBeat { binauralBeatManager.resume() }
        CuePlaybackManager.shared.resume()
    }
    
    // MARK: - MeditationSession Protocol Methods
    
    func start() {
        print("[TimerSession] start() — timerRunning=\(timerManager.isRunning), hasStarted=\(hasStarted)")
        
        hasStarted = true
        
        // Register audio layers and start the session via the central controller.
        // This stops background music, activates .playback, and marks the session active.
        AppAudioLifecycleController.shared.registerTimerSession(
            backgroundSound: backgroundSoundManager,
            binauralBeat: binauralBeatManager,
            timerManager: timerManager
        )
        AppAudioLifecycleController.shared.meditationDidStart()
        
        // Preload all cue + parallel SFX into memory before starting the clock so prep cues never race
        // (parallel breath SFX must be cached or voice+SFX scheduling can be skipped when generation changes).
        let allCues = config.cueSettings.map { $0.cue }
        CuePlaybackManager.shared.preloadCues(allCues) { [weak self] in
            guard let self = self else { return }
            self.timerManager.start()
            if self.hasBackgroundSound {
                self.backgroundSoundManager.play(sound: self.config.backgroundSound, withFadeInDuration: 3.0)
            }
            if self.hasBinauralBeat {
                self.binauralBeatManager.play(beat: self.config.binauralBeat, withFadeInDuration: 3.0)
            }
            self.playStartCues()
        }
        
        // Register with lock screen service (metadata only until playback begins after preload)
        LockScreenMediaService.shared.registerSession(self)
        
        // Note: HR lifecycle is managed by PlayerView (unified for all session types)
    }
    
    func pause() {
        // Guard against interactions during session completion
        guard !isCompleting else {
            traceTimerSession("🧠 AI_DEBUG [SESSION] Ignoring pause - session is completing")
            return
        }
        
        timerManager.pause()
        pauseAllAudio()
        
        // Update lock screen
        LockScreenMediaService.shared.updatePlaybackState(isPlaying: false)
    }
    
    func resume() {
        // Guard against interactions during session completion
        guard !isCompleting else {
            traceTimerSession("🧠 AI_DEBUG [SESSION] Ignoring resume - session is completing")
            return
        }
        
        traceTimerSession("🧠 AI_DEBUG [SESSION] resume() called - timerRunning=\(timerManager.isRunning), hasStarted=\(hasStarted), cueActive=\(CuePlaybackManager.shared.currentCueId ?? "none")")
        
        // If session was never started (e.g., user skipped before pressing play),
        // initialize audio layers from the current position instead of resuming
        if !hasStarted {
            traceTimerSession("🧠 AI_DEBUG [SESSION] resume() - session not started yet, initializing audio layers")
            startFromCurrentPosition()
            return
        }
        
        timerManager.start()
        resumeAllAudio()
        
        // Update lock screen
        LockScreenMediaService.shared.updatePlaybackState(isPlaying: true)
        
        traceTimerSession("🧠 AI_DEBUG [SESSION] resume() complete")
    }
    
    /// Starts the session from the current position (used when user skipped before first play)
    private func startFromCurrentPosition() {
        let elapsed = totalSeconds - remainingSeconds
        print("[TimerSession] startFromCurrentPosition() — elapsed=\(elapsed)s")
        
        hasStarted = true
        
        // Ensure the session is marked active via the controller (may already be active
        // if start() was called previously; meditationDidStart() is idempotent for state).
        if !AppAudioLifecycleController.shared.isMeditationSessionActive {
            AppAudioLifecycleController.shared.registerTimerSession(
                backgroundSound: backgroundSoundManager,
                binauralBeat: binauralBeatManager,
                timerManager: timerManager
            )
            AppAudioLifecycleController.shared.meditationDidStart()
        }
        
        let allCues = config.cueSettings.map { $0.cue }
        CuePlaybackManager.shared.preloadCues(allCues) { [weak self] in
            guard let self = self else { return }
            let elapsedNow = TimeInterval(self.totalSeconds - self.remainingSeconds)
            self.timerManager.start()
            if self.hasBackgroundSound {
                self.backgroundSoundManager.play(sound: self.config.backgroundSound, withFadeInDuration: 0.5)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    let t = TimeInterval(self.totalSeconds - self.remainingSeconds)
                    self.backgroundSoundManager.seekToSessionTime(t, withFadeIn: false)
                }
            }
            if self.hasBinauralBeat {
                self.binauralBeatManager.play(beat: self.config.binauralBeat, withFadeInDuration: 0.5)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    let t = TimeInterval(self.totalSeconds - self.remainingSeconds)
                    self.binauralBeatManager.seekToSessionTime(t, withFadeIn: false)
                }
            }
            self.checkAndPlayCueAtPosition(newElapsed: elapsedNow, startPaused: false)
            traceTimerSession("🧠 AI_DEBUG [SESSION] startFromCurrentPosition() complete (after cue preload)")
        }
        
        LockScreenMediaService.shared.registerSession(self)
    }
    
    func stop() {
        stopAllAudio(fadeOutDuration: 1.0)
        timerManager.endSession()
        
        // Let the central controller handle session cleanup: stops all meditation audio,
        // deactivates the audio session, and clears the lock screen.
        AppAudioLifecycleController.shared.meditationDidEnd()
        
        print("[TimerSession] stop() — session ended via controller")
    }
    
    func seek(seconds: TimeInterval) {
        // Use skipForward/skipBackward instead for timer sessions
    }
    
    // MARK: - Skip Forward/Backward
    
    /// Skips forward by the specified number of seconds.
    /// - Parameter seconds: Number of seconds to skip forward (default 15).
    func skipForward(seconds: Int = 15) {
        // Guard against interactions during session completion
        guard !isCompleting else {
            traceTimerSession("🧠 AI_DEBUG [SKIP] Ignoring skipForward - session is completing")
            return
        }
        
        let oldElapsed = totalSeconds - remainingSeconds
        let newRemaining = max(0, remainingSeconds - seconds)
        let newElapsed = totalSeconds - newRemaining
        let wasPaused = !isPlaying
        
        traceTimerSession("🧠 AI_DEBUG [SKIP] Forward: \(oldElapsed)s -> \(newElapsed)s (remaining: \(newRemaining)s, paused=\(wasPaused))")
        traceTimerSession("🧠 AI_DEBUG [SKIP] Cues configured: \(config.cueSettings.map { "\($0.cue.id)@\($0.triggerType.rawValue)\($0.minute.map { ":\($0)m" } ?? "")" }.joined(separator: ", "))")
        traceTimerSession("🧠 AI_DEBUG [SKIP] Already played cues: \(playedCues.map { $0.uuidString.prefix(8) }.joined(separator: ", "))")
        traceTimerSession("🧠 AI_DEBUG [SKIP] Audio layers: ambience=\(hasBackgroundSound), binaural=\(hasBinauralBeat)")
        
        // CRITICAL: If skipping to or past the end, immediately trigger session completion
        if newRemaining <= 0 {
            traceTimerSession("🧠 AI_DEBUG [SKIP] Skipped to end - triggering immediate session completion")
            timerManager.setRemainingSeconds(0)
            handleSessionComplete()
            return
        }
        
        // Handle fade-out BEFORE updating timer to avoid race condition with handleTimeUpdate
        // (handleTimeUpdate also monitors remaining seconds and would start a 10s fade)
        if !wasPaused && newRemaining <= 10 && !fadeOutStarted && (hasBackgroundSound || hasBinauralBeat) {
            fadeOutStarted = true
            let fadeOutDuration = TimeInterval(max(1, newRemaining))
            traceTimerSession("🧠 AI_DEBUG [SKIP] Starting fade-out (\(fadeOutDuration)s)")
            if hasBackgroundSound {
                backgroundSoundManager.stop(withFadeOutDuration: fadeOutDuration)
            }
            if hasBinauralBeat {
                binauralBeatManager.stop(withFadeOutDuration: fadeOutDuration)
            }
        }
        
        // Seek background audio layers forward (respects paused state internally)
        seekAudioLayers(to: TimeInterval(newElapsed))
        
        // Handle currently playing cue (or paused cue)
        handleCueSeek(oldElapsed: TimeInterval(oldElapsed), newElapsed: TimeInterval(newElapsed), isForward: true, isPaused: wasPaused)
        
        // Mark minute-based cues in the skipped window as played (don't trigger audio)
        for setting in config.cueSettings where setting.triggerType == .minute {
            if let min = setting.minute {
                let triggerTime = min * 60
                if triggerTime > oldElapsed && triggerTime <= newElapsed {
                    playedCues.insert(setting.id)
                    traceTimerSession("🧠 AI_DEBUG [SKIP] Marked cue \(setting.cue.id) as played (skipped past trigger at \(triggerTime)s)")
                }
            }
        }

        // Mark second-based cues in the skipped window as played (fractional modules)
        for setting in config.cueSettings where setting.triggerType == .second {
            if let sec = setting.minute {
                if sec > oldElapsed && sec <= newElapsed {
                    playedCues.insert(setting.id)
                    traceTimerSession("🧠 AI_DEBUG [Fractional][Player] ⏭️ skipForward: marked \(setting.cue.id) as played (trigger=\(sec)s, window=\(oldElapsed)-\(newElapsed))")
                }
            }
        }
        
        // Handle start cues: mark as played if skipped past their window
        for setting in config.cueSettings where setting.triggerType == .start {
            if let cueDuration = CuePlaybackManager.shared.getPreloadedDuration(for: setting.cue) {
                // Start cue window is 0 to cueDuration
                // If we skipped from within the window to past it, mark as played
                if TimeInterval(oldElapsed) < cueDuration && TimeInterval(newElapsed) >= cueDuration {
                    playedCues.insert(setting.id)
                    traceTimerSession("🧠 AI_DEBUG [SKIP] Marked start cue \(setting.cue.id) as played (skipped past end at \(String(format: "%.1f", cueDuration))s)")
                }
            }
        }
        
        // Check if we landed inside a cue's time window
        // If playing: start the cue immediately
        // If paused: load the cue but keep it paused (ready for resume)
        checkAndPlayCueAtPosition(newElapsed: TimeInterval(newElapsed), startPaused: wasPaused)
        
        // Update timer
        timerManager.setRemainingSeconds(newRemaining)
        
        // Check progress thresholds (will log any we crossed)
        timerManager.checkCompletionRatesAfterSeek()
    }
    
    /// Skips backward by the specified number of seconds.
    /// - Parameter seconds: Number of seconds to skip backward (default 15).
    func skipBackward(seconds: Int = 15) {
        // Guard against interactions during session completion
        guard !isCompleting else {
            traceTimerSession("🧠 AI_DEBUG [SKIP] Ignoring skipBackward - session is completing")
            return
        }
        
        let oldElapsed = totalSeconds - remainingSeconds
        let newRemaining = min(totalSeconds, remainingSeconds + seconds)
        let newElapsed = totalSeconds - newRemaining
        let wasPaused = !isPlaying
        
        traceTimerSession("🧠 AI_DEBUG [SKIP] Backward: \(oldElapsed)s -> \(newElapsed)s (remaining: \(newRemaining)s, paused=\(wasPaused))")
        traceTimerSession("🧠 AI_DEBUG [SKIP] Cues configured: \(config.cueSettings.map { "\($0.cue.id)@\($0.triggerType.rawValue)\($0.minute.map { ":\($0)m" } ?? "")" }.joined(separator: ", "))")
        traceTimerSession("🧠 AI_DEBUG [SKIP] Already played cues: \(playedCues.map { $0.uuidString.prefix(8) }.joined(separator: ", "))")
        traceTimerSession("🧠 AI_DEBUG [SKIP] Audio layers: ambience=\(hasBackgroundSound), binaural=\(hasBinauralBeat)")
        
        // Seek background audio layers to new position (respects paused state internally)
        seekAudioLayers(to: TimeInterval(newElapsed))
        
        // Handle currently playing cue (or paused cue)
        handleCueSeek(oldElapsed: TimeInterval(oldElapsed), newElapsed: TimeInterval(newElapsed), isForward: false, isPaused: wasPaused)
        
        // Allow minute-based cues that are now "in the future" to fire again
        var removedFromPlayed: [String] = []
        for setting in config.cueSettings where setting.triggerType == .minute {
            if let min = setting.minute {
                let triggerTime = min * 60
                if triggerTime > newElapsed && playedCues.contains(setting.id) {
                    playedCues.remove(setting.id)
                    removedFromPlayed.append("\(setting.cue.id)@\(min)m")
                }
            }
        }
        if !removedFromPlayed.isEmpty {
            traceTimerSession("🧠 AI_DEBUG [SKIP] Reset minute cues for replay: \(removedFromPlayed.joined(separator: ", "))")
        }

        // Allow second-based cues that are now "in the future" to fire again (fractional modules)
        var removedSecondCues: [String] = []
        for setting in config.cueSettings where setting.triggerType == .second {
            if let sec = setting.minute {
                if sec > newElapsed && playedCues.contains(setting.id) {
                    playedCues.remove(setting.id)
                    removedSecondCues.append("\(setting.cue.id)@\(sec)s")
                }
            }
        }
        if !removedSecondCues.isEmpty {
            traceTimerSession("🧠 AI_DEBUG [Fractional][Player] ⏮️ skipBackward: reset cues for replay: \(removedSecondCues.joined(separator: ", "))")
        }
        
        // For start cues: reset if we skipped back into or before their window
        for setting in config.cueSettings where setting.triggerType == .start {
            if let cueDuration = CuePlaybackManager.shared.getPreloadedDuration(for: setting.cue) {
                // If we were past the start cue window and now we're inside or before it
                if TimeInterval(oldElapsed) >= cueDuration && TimeInterval(newElapsed) < cueDuration && playedCues.contains(setting.id) {
                    playedCues.remove(setting.id)
                    traceTimerSession("🧠 AI_DEBUG [SKIP] Reset start cue \(setting.cue.id) for replay (back inside window 0-\(String(format: "%.1f", cueDuration))s)")
                }
            }
        }
        
        // Check if we landed inside a cue's time window
        // If playing: start the cue immediately
        // If paused: load the cue but keep it paused (ready for resume)
        checkAndPlayCueAtPosition(newElapsed: TimeInterval(newElapsed), startPaused: wasPaused)
        
        // Reset fade-out if we jumped back out of final 10 seconds
        if newRemaining > 10 && fadeOutStarted {
            fadeOutStarted = false
            traceTimerSession("🧠 AI_DEBUG [SKIP] Reset fade-out flag")
        }
        
        // Update timer
        timerManager.setRemainingSeconds(newRemaining)
    }
    
    /// Checks if we should be playing a cue at the new elapsed time and starts it if needed.
    /// - Parameters:
    ///   - newElapsed: The new session elapsed time.
    ///   - startPaused: If true, load the cue but keep it paused (for seeking while paused).
    private func checkAndPlayCueAtPosition(newElapsed: TimeInterval, startPaused: Bool = false) {
        let cueManager = CuePlaybackManager.shared
        
        // Don't start a new cue if one is already active (playing or paused)
        if cueManager.isPlaying || cueManager.currentCueId != nil {
            traceTimerSession("🧠 AI_DEBUG [SKIP] Cue already active, not starting new one")
            return
        }
        
        traceTimerSession("🧠 AI_DEBUG [SKIP] checkAndPlayCueAtPosition: newElapsed=\(String(format: "%.1f", newElapsed))s, startPaused=\(startPaused)")
        
        // Check start cues first (they trigger at elapsed=0, window is 0 to duration)
        for setting in config.cueSettings where setting.triggerType == .start {
            guard let cueDuration = cueManager.getPreloadedDuration(for: setting.cue) else {
                traceTimerSession("🧠 AI_DEBUG [SKIP] No preloaded duration for start cue \(setting.cue.id)")
                continue
            }
            
            // Start cue window is 0 to cueDuration
            if newElapsed >= 0 && newElapsed < cueDuration {
                let positionInCue = newElapsed
                traceTimerSession("🧠 AI_DEBUG [SKIP] Landed inside START cue \(setting.cue.id) window (0s-\(String(format: "%.1f", cueDuration))s), \(startPaused ? "loading paused" : "playing") from \(String(format: "%.1f", positionInCue))s")
                
                // Play the cue (or load it paused)
                cueManager.play(cue: setting.cue, sessionElapsedTime: 0, startPaused: startPaused)
                
                // Give the player a moment to load, then seek
                if positionInCue > 0.5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        cueManager.seek(to: positionInCue)
                    }
                }
                
                // Mark as played so it doesn't trigger again
                playedCues.insert(setting.id)
                return // Only play one cue at a time
            }
        }
        
        // Check each minute-based cue to see if we're inside its time window
        for setting in config.cueSettings where setting.triggerType == .minute {
            guard let min = setting.minute else { continue }
            
            let triggerTime = TimeInterval(min * 60)
            
            // Get the cue's duration from preloaded data
            guard let cueDuration = cueManager.getPreloadedDuration(for: setting.cue) else {
                traceTimerSession("🧠 AI_DEBUG [SKIP] No preloaded duration for cue \(setting.cue.id)")
                continue
            }
            
            let cueEndTime = triggerTime + cueDuration
            
            // Check if newElapsed is within the cue's time window
            if newElapsed >= triggerTime && newElapsed < cueEndTime {
                let positionInCue = newElapsed - triggerTime
                traceTimerSession("🧠 AI_DEBUG [SKIP] Landed inside MINUTE cue \(setting.cue.id) window (\(String(format: "%.1f", triggerTime))s-\(String(format: "%.1f", cueEndTime))s), \(startPaused ? "loading paused" : "playing") from \(String(format: "%.1f", positionInCue))s")
                
                // Play the cue (or load it paused)
                cueManager.play(cue: setting.cue, sessionElapsedTime: triggerTime, startPaused: startPaused)
                
                // Give the player a moment to load, then seek
                if positionInCue > 0.5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        cueManager.seek(to: positionInCue)
                    }
                }
                
                // Mark as played so it doesn't trigger again from handleTimeUpdate
                playedCues.insert(setting.id)
                return // Only play one cue at a time
            }
        }

        // Check each second-based cue to see if we're inside its time window (fractional modules)
        for setting in config.cueSettings where setting.triggerType == .second {
            guard let sec = setting.minute else { continue }

            let triggerTime = TimeInterval(sec)

            guard let cueDuration = cueManager.getPreloadedDuration(for: setting.cue) else {
                traceTimerSession("🧠 AI_DEBUG [Fractional][Player] seek: no preloaded duration for \(setting.cue.id)")
                continue
            }

            let cueEndTime = triggerTime + cueDuration

            if newElapsed >= triggerTime && newElapsed < cueEndTime {
                let positionInCue = newElapsed - triggerTime
                traceTimerSession("🧠 AI_DEBUG [Fractional][Player] 🎯 seek: landed inside \(setting.cue.id) window (\(String(format: "%.1f", triggerTime))s-\(String(format: "%.1f", cueEndTime))s), \(startPaused ? "paused" : "playing") from \(String(format: "%.1f", positionInCue))s")

                cueManager.play(cue: setting.cue, sessionElapsedTime: triggerTime, startPaused: startPaused)

                if positionInCue > 0.5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        cueManager.seek(to: positionInCue)
                    }
                }

                playedCues.insert(setting.id)
                return
            }
        }
        
        traceTimerSession("🧠 AI_DEBUG [SKIP] No cue window contains elapsed=\(String(format: "%.1f", newElapsed))s")
    }
    
    /// Handles seeking within a currently playing (or paused) cue, or stopping it if we've seeked outside its window.
    private func handleCueSeek(oldElapsed: TimeInterval, newElapsed: TimeInterval, isForward: Bool, isPaused: Bool) {
        let cueManager = CuePlaybackManager.shared
        
        // Check if there's a cue loaded (could be playing or paused)
        let cueIsActive = cueManager.isPlaying || cueManager.currentCueId != nil
        let cueInfo = cueManager.getCurrentCueInfo()
        
        traceTimerSession("🧠 AI_DEBUG [SKIP] handleCueSeek: cueActive=\(cueIsActive), isPaused=\(isPaused), cueInfo=\(cueInfo.map { "\($0.id) start=\($0.startTime) dur=\($0.duration)" } ?? "nil")")
        
        guard cueIsActive, let cueInfo = cueInfo else {
            traceTimerSession("🧠 AI_DEBUG [SKIP] No cue currently active")
            return
        }
        
        let cueStartTime = cueInfo.startTime
        let cueDuration = cueInfo.duration
        let cueEndTime = cueStartTime + cueDuration
        
        // Calculate where we'd be in the cue at the new elapsed time
        let newPositionInCue = newElapsed - cueStartTime
        
        traceTimerSession("🧠 AI_DEBUG [SKIP] Cue \(cueInfo.id): window=\(cueStartTime)s-\(cueEndTime)s, newPositionInCue=\(String(format: "%.1f", newPositionInCue))s")
        
        if newPositionInCue < 0 {
            // We've seeked to before the cue started - stop it
            cueManager.stop()
            // Find and remove from played so it can trigger again
            if let setting = config.cueSettings.first(where: { $0.cue.id == cueInfo.id }) {
                playedCues.remove(setting.id)
            }
            traceTimerSession("🧠 AI_DEBUG [SKIP] Cue \(cueInfo.id): seeked before start, stopped and reset for replay")
        } else if newPositionInCue >= cueDuration {
            // We've seeked past the cue's end - stop it, keep it marked as played
            cueManager.stop()
            traceTimerSession("🧠 AI_DEBUG [SKIP] Cue \(cueInfo.id): seeked past end, stopped")
        } else {
            // We're still within the cue's duration - seek to the correct position
            // This works whether playing or paused - just updates the position
            cueManager.seek(to: newPositionInCue)
            traceTimerSession("🧠 AI_DEBUG [SKIP] Cue \(cueInfo.id): seeking to \(String(format: "%.2f", newPositionInCue))s (paused=\(isPaused))")
            
            // IMPORTANT: If we seeked a START cue back to position 0, also reset its playedCues status
            // This ensures it will play again if start() is called instead of resume()
            if cueStartTime == 0 && newPositionInCue == 0 {
                if let setting = config.cueSettings.first(where: { $0.cue.id == cueInfo.id && $0.triggerType == .start }) {
                    if playedCues.contains(setting.id) {
                        playedCues.remove(setting.id)
                        traceTimerSession("🧠 AI_DEBUG [SKIP] Reset start cue \(cueInfo.id) playedCues status (seeked to beginning)")
                    }
                }
            }
        }
    }
    
    // MARK: - Audio Layer Seeking
    
    /// Seeks audio layers (background music, binaural beats) to match the session elapsed time.
    /// If seeking to the beginning (elapsed = 0), applies a fade-in for a "fresh start" experience.
    /// - Parameter sessionElapsed: The target session elapsed time in seconds.
    private func seekAudioLayers(to sessionElapsed: TimeInterval) {
        let isSeekingToBeginning = sessionElapsed == 0
        // Use 8 seconds for fade-in (same as initial session start for binaural, 10s for ambience)
        let fadeInDuration: TimeInterval = 8.0
        
        traceTimerSession("🧠 AI_DEBUG [SKIP] seekAudioLayers(to: \(sessionElapsed)s, isBeginning=\(isSeekingToBeginning))")
        
        if hasBackgroundSound {
            traceTimerSession("🧠 AI_DEBUG [SKIP] Calling backgroundSoundManager.seekToSessionTime(\(sessionElapsed), fadeIn=\(isSeekingToBeginning))")
            backgroundSoundManager.seekToSessionTime(sessionElapsed, withFadeIn: isSeekingToBeginning, fadeInDuration: fadeInDuration)
        }
        
        if hasBinauralBeat {
            traceTimerSession("🧠 AI_DEBUG [SKIP] Calling binauralBeatManager.seekToSessionTime(\(sessionElapsed), fadeIn=\(isSeekingToBeginning))")
            binauralBeatManager.seekToSessionTime(sessionElapsed, withFadeIn: isSeekingToBeginning, fadeInDuration: fadeInDuration)
        }
    }
    
    // MARK: - Volume Control
    
    // Volume transformation constants
    // Bias: shifts the midpoint output (slider 0.5 outputs different volumes per channel)
    // Impact: steeper response curve (1.5 = 50% more impactful)
    private static let instructionsBias: Float = 0.1    // +20% at midpoint (0.5 -> 0.6)
    private static let binauralBias: Float = 0.1        // +20% at midpoint (0.5 -> 0.6)
    private static let ambienceBias: Float = -0.1       // -20% at midpoint (0.5 -> 0.4)
    private static let impactMultiplier: Float = 1.5    // 50% more impactful
    
    /// Transforms slider value (0-1) to actual audio volume with bias and enhanced impact.
    /// - Parameters:
    ///   - sliderValue: Raw value from slider (0-1)
    ///   - bias: Channel-specific bias (+0.1 for louder, -0.1 for quieter at midpoint)
    /// - Returns: Transformed volume (0-1)
    private func transformVolume(_ sliderValue: Float, bias: Float) -> Float {
        let baseline: Float = 0.5
        let delta = sliderValue - baseline
        let enhancedDelta = delta * Self.impactMultiplier
        let transformedValue = baseline + bias + enhancedDelta
        return min(1.0, max(0.0, transformedValue))
    }
    
    func setInstructionsVolume(_ value: Float) {
        instructionsVolume = value
        volumeStore.instructions = value
        let actualVolume = transformVolume(value, bias: Self.instructionsBias)
        CuePlaybackManager.shared.setVolume(actualVolume)
    }
    
    func setAmbienceVolume(_ value: Float) {
        ambienceVolume = value
        volumeStore.ambience = value
        let actualVolume = transformVolume(value, bias: Self.ambienceBias)
        backgroundSoundManager.setVolume(actualVolume)
    }
    
    func setBinauralVolume(_ value: Float) {
        binauralVolume = value
        volumeStore.binaural = value
        let actualVolume = transformVolume(value, bias: Self.binauralBias)
        binauralBeatManager.setVolume(actualVolume)
    }
    
    // MARK: - Private Helpers
    
    private func handleTimeUpdate(remaining: Int) {
        let elapsed = timerManager.totalSeconds - remaining
        
        // Update lock screen with elapsed time
        LockScreenMediaService.shared.updateElapsedTime(TimeInterval(elapsed))
        
        // Check minute-based cues
        for setting in config.cueSettings where setting.triggerType == .minute {
            if let min = setting.minute, elapsed >= min * 60, !playedCues.contains(setting.id) {
                playedCues.insert(setting.id)
                playCue(setting.cue)
            }
        }

        // Check second-based cues (fractional modules)
        for setting in config.cueSettings where setting.triggerType == .second {
            if let sec = setting.minute, elapsed >= sec, !playedCues.contains(setting.id) {
                playedCues.insert(setting.id)
                traceTimerSession("🧠 AI_DEBUG [Fractional][Player] ▶️ cue FIRED: \(setting.cue.id) at elapsed=\(elapsed)s (trigger=\(sec)s) text=\"\(String(setting.cue.name.prefix(50)))\"")
                playCue(setting.cue)
            }
        }
        
        // Start fade out when 10 seconds remaining
        if remaining <= 10 && !fadeOutStarted && (hasBackgroundSound || hasBinauralBeat) {
            fadeOutStarted = true
            if hasBackgroundSound {
                backgroundSoundManager.stop(withFadeOutDuration: 10.0)
            }
            if hasBinauralBeat {
                binauralBeatManager.stop(withFadeOutDuration: 10.0)
            }
        }
    }
    
    private func handleSessionComplete() {
        // Guard against multiple completions (e.g., if user keeps skipping)
        guard !isCompleting else {
            print("[TimerSession] handleSessionComplete() already in progress — ignoring")
            return
        }
        isCompleting = true
        print("[TimerSession] handleSessionComplete() — starting completion flow")
        
        // Play end cues (e.g., gentle bell) before tearing down the session
        playEndCues()
        
        // Stop music/binaural immediately if not already faded (end cues are protected)
        if !fadeOutStarted {
            stopAllAudio(fadeOutDuration: 1.0)
        }
        
        // Determine how long to wait before deactivating the audio session so the
        // end cue (gentle bell) can finish playing. Without this delay the session
        // was deactivated immediately, killing the bell mid-play.
        let endCueDelay: TimeInterval = {
            if let info = CuePlaybackManager.shared.getCurrentCueInfo() {
                let remaining = max(0, info.duration - CuePlaybackManager.shared.currentPosition)
                return remaining + 0.5  // small buffer
            }
            return 0.5
        }()
        
        // Call the completion callback immediately so the UI can transition
        // to the post-practice screen while the bell continues playing.
        print("[TimerSession] Calling completion callback — end cue will play for \(String(format: "%.1f", endCueDelay))s")
        _onSessionComplete?()
        
        // Delay the full session teardown until the end cue finishes.
        // AppAudioLifecycleController.meditationDidEnd() will deactivate the audio
        // session, clear the lock screen, and mark the session inactive.
        DispatchQueue.main.asyncAfter(deadline: .now() + endCueDelay) {
            AppAudioLifecycleController.shared.meditationDidEnd()
            print("[TimerSession] handleSessionComplete — session fully torn down after end cue")
        }
    }
    
    private func playStartCues() {
        traceTimerSession("🧠 AI_DEBUG [SESSION] playStartCues() - playedCues=\(playedCues.map { $0.uuidString.prefix(8) }.joined(separator: ", "))")
        for setting in config.cueSettings where setting.triggerType == .start {
            let alreadyPlayed = playedCues.contains(setting.id)
            traceTimerSession("🧠 AI_DEBUG [SESSION] Start cue \(setting.cue.id): alreadyPlayed=\(alreadyPlayed)")
            if !alreadyPlayed {
                playedCues.insert(setting.id)
                playCue(setting.cue)
            }
        }
    }
    
    private func playEndCues() {
        for setting in config.cueSettings where setting.triggerType == .end && !playedCues.contains(setting.id) {
            playedCues.insert(setting.id)
            playCue(setting.cue)
        }
    }
    
    private func playCue(_ cue: Cue) {
        if cue.name != "None" {
            let elapsed = TimeInterval(totalSeconds - remainingSeconds)
            CuePlaybackManager.shared.play(cue: cue, sessionElapsedTime: elapsed)
        }
    }
    
    private func stopAllAudio(fadeOutDuration: TimeInterval) {
        if hasBackgroundSound {
            backgroundSoundManager.stop(withFadeOutDuration: fadeOutDuration)
        }
        if hasBinauralBeat {
            binauralBeatManager.stop(withFadeOutDuration: fadeOutDuration)
        }
        // Only fade out cue if it's NOT an end cue - let end cues (e.g., gentle bell) play to completion
        if !isEndCuePlaying() {
            CuePlaybackManager.shared.fadeOutCurrentCue(withDuration: fadeOutDuration)
        } else {
            traceTimerSession("🧠 AI_DEBUG [SESSION] Skipping cue fade-out - end cue is playing")
        }
    }
    
    /// Check if the currently playing cue is an END-triggered cue (should not be faded out)
    private func isEndCuePlaying() -> Bool {
        guard let currentCueId = CuePlaybackManager.shared.currentCueId else { return false }
        return config.cueSettings.contains { $0.cue.id == currentCueId && $0.triggerType == .end }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    // MARK: - Abort Logging
    
    /// Log timer aborted event when user exits early
    func logAborted() {
        let completionRate = (timerManager.currentProgress / timerManager.totalDuration) * 100
        let progressPercent = Int(completionRate)
        
        // Use AnalyticsRouter for unified session_aborted event
        AnalyticsRouter.shared.logSessionAborted(progressPercent: progressPercent)
    }
    
    /// End session and clear context
    /// Note: stop() already calls timerManager.endSession() which clears context via AnalyticsRouter
    func endSession() {
        stop()
        // Removed duplicate AnalyticsRouter.shared.endSession() call
        // as it's already called in timerManager.endSession() via stop()
    }
}

// MARK: - MediaSessionProtocol Conformance

extension TimerMeditationSession: MediaSessionProtocol {
    var mediaTitle: String {
        // Show current cue name if one is playing, otherwise use config title or fallback
        if let currentCueId = CuePlaybackManager.shared.currentCueId,
           let setting = config.cueSettings.first(where: { $0.cue.id == currentCueId }) {
            return setting.cue.name
        }
        return config.title ?? "Custom Meditation"
    }
    
    var mediaSubtitle: String? {
        "\(totalSeconds / 60) min"
    }
    
    var mediaDuration: TimeInterval {
        TimeInterval(totalSeconds)
    }
    
    var mediaElapsedTime: TimeInterval {
        TimeInterval(totalSeconds - remainingSeconds)
    }
    
    var mediaIsPlaying: Bool {
        isPlaying
    }
    
    var mediaArtworkURL: URL? {
        // Custom meditations use local bundle artwork
        nil
    }
    
    var mediaLocalArtworkName: String? {
        // Use the default player background for custom meditations
        "PlayerBackground"
    }
    
    func mediaPlay() {
        resume()
    }
    
    func mediaPause() {
        pause()
    }
    
    func mediaSkipForward(seconds: Int) {
        skipForward(seconds: seconds)
    }
    
    func mediaSkipBackward(seconds: Int) {
        skipBackward(seconds: seconds)
    }
}

