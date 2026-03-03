//
//  AudioPlayerManager.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-17
//

import AVFoundation
import SwiftUI
import MediaPlayer
import FirebaseAnalytics
import FirebaseStorage

class AudioPlayerManager: NSObject, ObservableObject, AudioPlaybackDelegate {
    // Static shared instance for global access
    static var shared: AudioPlayerManager?
    
    private let playbackManager = AudioPlaybackManager()

    var contentDetails: String = ""

    @Published var totalDuration: TimeInterval = 0
    @Published var remainingTime: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var selectedFile: AudioFile?
    @Published var isDownloading: Bool = false
    @Published var controlsEnabled: Bool = true
    @Published var hasReached75Percent: Bool = false
    
    @Published var didJustFinishSession: Bool = false
    
    /// Legacy recommendation source - deprecated, use SessionContextManager instead
    @Published var recommendationSource: String? = ""
    
    // New flag to ensure session_start is logged only when playback actually begins.
    private var hasLoggedSessionStart = false
    
    // Track which progress milestones have been logged
    private var loggedMilestones: Set<Int> = []
    
    var onSessionComplete: (() -> Void)?
    private var elapsedTime: TimeInterval = 0

    private var completionLogs: [(threshold: Double, logged: Bool, eventName: String)] = []

    private var sessionStartDate: Date?
    private var currentPracticeID: String?
    private var hasLoggedPracticeComplete: Bool = false

    private var wasPlayingBeforeRouteChange = false
    private var wasPlayingBeforeInterruption = false

    override init() {
        super.init()
        setup()
    }

    private func setup() {
        playbackManager.delegate = self
        setupNotifications()
    }

    // MARK: - Audio Session
    //
    // Audio session activation/deactivation is now managed centrally by
    // AppAudioLifecycleController. This manager only handles playback;
    // it never sets AVAudioSession category or active state directly.

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let typeVal = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal)
        else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            pause()
            print("[GuidedPlayer] Audio interruption began — paused")
        case .ended:
            // Only resume if a meditation session is still active (prevents ghost-resume
            // after the session has ended and AppAudioLifecycleController deactivated the session).
            guard AppAudioLifecycleController.shared.isMeditationSessionActive else {
                print("[GuidedPlayer] Interruption ended but no active session — skipping resume")
                wasPlayingBeforeInterruption = false
                return
            }
            if let optsVal = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optsVal).contains(.shouldResume) {
                if wasPlayingBeforeInterruption {
                    play()
                    print("[GuidedPlayer] Audio interruption ended — resumed playback")
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let reasonVal = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonVal)
        else { return }
        switch reason {
        case .oldDeviceUnavailable:
            if let prevRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                let hadHeadphones = prevRoute.outputs.contains {
                    $0.portType == .headphones || $0.portType == .bluetoothA2DP
                }
                if hadHeadphones {
                    wasPlayingBeforeRouteChange = playbackManager.isPlaying
                    if wasPlayingBeforeRouteChange {
                        pause()
                        print("[GuidedPlayer] Route change: headphones removed — paused")
                    }
                }
            }
        case .newDeviceAvailable:
            // Never auto-resume on device reconnection. The user must tap play.
            // This prevents phantom playback when AirPods switch between devices.
            wasPlayingBeforeRouteChange = false
            print("[GuidedPlayer] Route change: new device available — not auto-resuming (user must tap play)")
        default:
            break
        }
    }

    // MARK: - Playback

    func playAudioFile(file: AudioFile, durationIndex: Int) {
        // First ensure any existing playback is stopped completely
        stopAudio {
            // Audio session is already activated by AppAudioLifecycleController.meditationDidStart()
            self.selectedFile = file
            self.currentPracticeID = file.id
            self.contentDetails = "\(file.title) (\(file.durations[durationIndex].fileName))"
            self.sessionStartDate = Date()
            self.hasLoggedSessionStart = false  // Reset the session start log flag
            self.loggedMilestones = []  // Reset milestone tracking

            self.calculateTotalDuration(file: file, durationIndex: durationIndex) { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.remainingTime = self.totalDuration
                    self.elapsedTime = 0
                    self.currentTime = 0  // Reset progress
                    self.setupCompletionLogs()
                    self.hasLoggedPracticeComplete = false
                    self.didJustFinishSession = false
                    // Do not log practice_start here.
                    self.playAudio(file: file, withDuration: file.durations[durationIndex])
                }
            }
        }
    }

    /// Preloads the audio file without starting playback.
    /// Also automatically starts heart rate monitoring if Apple Watch is available.
    func preloadAudioFile(file: AudioFile, durationIndex: Int, completion: @escaping () -> Void) {
        // First ensure any existing playback is stopped completely
        stopAudio {
            // Audio session is already activated by AppAudioLifecycleController.meditationDidStart()
            self.selectedFile = file
            self.currentPracticeID = file.id
            self.contentDetails = "\(file.title) (\(file.durations[durationIndex].fileName))"
            self.sessionStartDate = Date()
            self.hasLoggedSessionStart = false  // Reset the session start log flag
            self.loggedMilestones = []  // Reset milestone tracking

            self.calculateTotalDuration(file: file, durationIndex: durationIndex) { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.remainingTime = self.totalDuration
                    self.elapsedTime = 0
                    self.currentTime = 0  // Reset progress
                    self.setupCompletionLogs()
                    self.hasLoggedPracticeComplete = false
                    self.didJustFinishSession = false
                    // Log session preload event via AnalyticsRouter (unified logging with debug output)
                    AnalyticsRouter.shared.logSessionPreload()

                    // 📊 Begin heart rate tracking during preload so LiveHeartRateCard can update before playback
                    // Note: HeartRateService is started/stopped by PlayerView lifecycle
                    if SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false) {
                        PracticeBPMTracker.shared.startNewSession()
                        logger.eventMessage("AudioPlayerManager: Started BPM tracking session during preload")
                    }
                    
                    let duration = file.durations[durationIndex]
                    let fileName = duration.fileName.components(separatedBy: "/").last ?? duration.fileName
                    let localURL = FileManagerHelper.shared.localFilePath(for: fileName)
                    if FileManagerHelper.shared.fileExists(at: localURL) {
                        self.playbackManager.prepareToPlay(from: localURL)
                        completion()
                    } else if let remoteURL = self.getURL(for: duration.fileName) {
                        self.downloadAndPreload(url: remoteURL, completion: completion)
                    } else {
                        logger.eventMessage("Failed to find URL for file: \(duration.fileName)")
                        completion()
                    }
                }
            }
        }
    }

    private func playAudio(file: AudioFile, withDuration duration: Duration) {
        let fileName = duration.fileName.components(separatedBy: "/").last ?? duration.fileName
        let localURL = FileManagerHelper.shared.localFilePath(for: fileName)
        if FileManagerHelper.shared.fileExists(at: localURL) {
            startPlaying(from: localURL)
        } else if let remoteURL = getURL(for: duration.fileName) {
            downloadAndPlay(url: remoteURL)
        } else {
            logger.eventMessage("Failed to find URL for file: \(duration.fileName)")
        }
    }

    private func startPlaying(from url: URL) {
        playbackManager.startPlaying(from: url)
        DispatchQueue.main.async {
            self.isPlaying = true
        }
    }

    private func getURL(for fileName: String) -> URL? {
        if fileName.hasPrefix(Config.storagePathPrefix) {
            return URL(string: fileName)
        } else {
            return Bundle.main.url(forResource: fileName, withExtension: nil)
        }
    }

    private func downloadAndPlay(url: URL) {
        isDownloading = true
        FileManagerHelper.shared.downloadFile(from: url, setDownloading: { [weak self] downloading in
            DispatchQueue.main.async {
                self?.isDownloading = downloading
            }
        }) { [weak self] localURL in
            guard let self = self, let localURL = localURL else {
                DispatchQueue.main.async { self?.isDownloading = false }
                return
            }
            DispatchQueue.main.async {
                self.startPlaying(from: localURL)
                self.isDownloading = false
            }
        }
    }

    private func downloadAndPreload(url: URL, completion: @escaping () -> Void) {
        isDownloading = true
        FileManagerHelper.shared.downloadFile(from: url, setDownloading: { [weak self] downloading in
            DispatchQueue.main.async {
                self?.isDownloading = downloading
            }
        }) { [weak self] localURL in
            guard let self = self, let localURL = localURL else {
                DispatchQueue.main.async {
                    self?.isDownloading = false
                    completion()
                }
                return
            }
            DispatchQueue.main.async {
                self.playbackManager.prepareToPlay(from: localURL)
                self.isDownloading = false
                completion()
            }
        }
    }

    func play() {
        // Audio session is managed by AppAudioLifecycleController —
        // .playback category and activation happen in meditationDidStart().
        playbackManager.play()
        DispatchQueue.main.async {
            self.isPlaying = true
            // Register with lock screen service
            LockScreenMediaService.shared.registerSession(self)
            // Log "session_start" only when the user initiates playback.
            if !self.hasLoggedSessionStart {
                // Use AnalyticsRouter for the new unified session_start event
                AnalyticsRouter.shared.logSessionStart()
                self.hasLoggedSessionStart = true
                
                // Log ai_onboarding_meditation_played when AI meditation from onboarding actually starts
                if let context = SessionContextManager.shared.currentContext,
                   context.contentOrigin == .aiRecommended && SenseiOnboardingState.shared.isComplete {
                    AnalyticsManager.shared.logEvent("ai_onboarding_meditation_played", parameters: [
                        "steps_completed": SenseiOnboardingState.shared.stepsCompletedBeforeExit,
                        "skipped_early": SenseiOnboardingState.shared.didSkipEarly
                    ])
                }
                
                // Also log path_step_started if this is a path session
                AnalyticsRouter.shared.logPathStepStarted()
            }
            
            // Note: Heart rate monitoring connectivity is handled during preload
            // But actual data tracking starts here when audio plays
        }
    }

    func pause() {
        playbackManager.pause()
        DispatchQueue.main.async {
            self.isPlaying = false
            LockScreenMediaService.shared.updatePlaybackState(isPlaying: false)
            
            // Note: We don't stop meditation session on pause, 
            // only when the session actually ends
        }
    }

    func stopAudio(completion: (() -> Void)? = nil) {
        playbackManager.stop()
        LockScreenMediaService.shared.unregisterSession()

        // Audio session deactivation is handled by AppAudioLifecycleController.meditationDidEnd().
        // We only reset local state here.

        // Reset stale route/interruption state to prevent ghost-resume
        wasPlayingBeforeRouteChange = false
        wasPlayingBeforeInterruption = false

        DispatchQueue.main.async {
            self.isPlaying = false
            print("[GuidedPlayer] Audio stopped and cleaned up")
            completion?()
        }
    }

    func endSession(completion: (() -> Void)? = nil) {
        stopAudio {
            self.selectedFile = nil
            self.currentPracticeID = nil
            self.sessionStartDate = nil
            // Clear session context after audio session ends
            AnalyticsRouter.shared.endSession()
            
            completion?()
        }
    }

    func skipForward() {
        playbackManager.skipForward(seconds: 15)
    }

    func skipBackward() {
        playbackManager.skipBackward(seconds: 15)
    }

    // MARK: - AudioPlaybackDelegate

    func playbackDidFinishSuccessfully() {
        didJustFinishSession = true
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "CompleteMeditationSession") {
            // Background task expiration handler - iOS is about to suspend/terminate
            logger.aiChat("📋 [POST_PRACTICE] BG_TASK_EXPIRING id=\(bgTask.rawValue)")
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        
        logger.aiChat("📋 [POST_PRACTICE] BG_TASK_START id=\(bgTask.rawValue)")
        
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = self.totalDuration
            self.remainingTime = 0
            LockScreenMediaService.shared.updateElapsedTime(self.totalDuration)
            if !self.hasLoggedPracticeComplete {
                // Use AnalyticsRouter for session completion
                AnalyticsRouter.shared.logSessionComplete()
                AnalyticsRouter.shared.logPathStepCompleted()
                self.hasLoggedPracticeComplete = true
            } else {
                logger.eventMessage("Skipped duplicate session_complete log for current session")
            }
            
            // 📊 IMPORTANT: Stop and lock heart rate tracking BEFORE triggering session complete callback
            // This ensures PostPracticeView gets the final locked results, not live data
            PracticeBPMTracker.shared.stopTracking()
            
            // Note: HeartRateService is stopped by PlayerView lifecycle when it disappears
            
            logger.aiChat("📋 [POST_PRACTICE] BG_TASK_CALLBACK_INVOKING")
            self.onSessionComplete?()
            logger.aiChat("📋 [POST_PRACTICE] BG_TASK_CALLBACK_RETURNED")
            
            LockScreenMediaService.shared.unregisterSession()
            logger.eventMessage("Audio playback finished. Now Playing cleared.")
            
            // Add to session history using the new comprehensive manager
            if let file = self.selectedFile {
                print("🧠 AI_DEBUG HISTORY AudioPlayerManager recording session for '\(file.title)'")
                
                // Check HR tracker state before recording
                let tracker = PracticeBPMTracker.shared
                print("🧠 AI_DEBUG HISTORY tracker state: hasLocked=\(tracker.hasLockedResults) bestFirst=\(Int(tracker.bestFirstThreeAverage)) bestLast=\(Int(tracker.bestLastThreeAverage))")
                
                // Determine source based on SessionContextManager
                let source: MeditationSessionSource = {
                    guard let context = SessionContextManager.shared.currentContext else {
                        if file.tags.contains("path") {
                            return .path
                        }
                        return .explore
                    }
                    
                    switch context.entryPoint {
                    case .aiChat:
                        return .aiChat
                    case .pathScreen, .postPracticeRec:
                        if context.contentType == .pathStep {
                            return .path
                        }
                        return .explore
                    case .createScreen:
                        return .timer
                    case .deepLink:
                        return .deeplink
                    default:
                        return .explore
                    }
                }()
                
                SessionHistoryManager.shared.recordPracticeCompletion(
                    audioFile: file,
                    actualDurationSeconds: Int(self.totalDuration),
                    completionRate: 1.0,
                    source: source
                )
                print("🧠 AI_DEBUG HISTORY AudioPlayerManager done recording")
            } else {
                print("🧠 AI_DEBUG HISTORY AudioPlayerManager selectedFile is nil - NOT recording!")
            }
            
            guard let practiceID = self.currentPracticeID,
                  let startDate = self.sessionStartDate else {
                logger.errorMessage("Cannot complete session: Missing practiceID or startDate.")
                // Safety delay before ending background task to allow MainActor tasks to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    logger.aiChat("📋 [POST_PRACTICE] BG_TASK_END_EARLY id=\(bgTask.rawValue)")
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
                return
            }
            
            // Only complete the meditation session if it wasn't already completed at 95%
            if !self.completionLogs.contains(where: { $0.threshold == 0.95 && $0.logged }) {
                let endDate = Date()
                PracticeManager.shared.completeMeditationSession(
                    practiceID: practiceID,
                    startDate: startDate,
                    endDate: endDate
                )
            }
            
            self.currentPracticeID = nil
            self.sessionStartDate = nil
            self.selectedFile = nil
            
            // Safety delay before ending background task to allow MainActor tasks to complete.
            // The handleCompletedSession runs synchronously on MainActor via await MainActor.run,
            // but the Task wrapper in PlayerScreenView needs a tick to dispatch. This 0.3s delay
            // ensures the post-practice report is fully persisted before iOS can suspend the app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                logger.aiChat("📋 [POST_PRACTICE] BG_TASK_END id=\(bgTask.rawValue)")
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
    }

    func playbackProgressDidUpdate(currentTime: TimeInterval, duration: TimeInterval) {
        DispatchQueue.main.async {
            self.currentTime = currentTime
            self.totalDuration = duration
            self.remainingTime = max(0, self.totalDuration - self.elapsedTime - currentTime)
            self.checkCompletionRates()
            LockScreenMediaService.shared.updateElapsedTime(currentTime)
        }
    }

    func playbackDidFail(with error: Error) {
        logger.eventMessage("Playback failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isPlaying = false
            LockScreenMediaService.shared.unregisterSession()
        }
    }

    // MARK: - Completion Logs

    private func setupCompletionLogs() {
        completionLogs = [
            (0.25, false, "practice_25_percent_complete"),
            (0.50, false, "practice_50_percent_complete"),
            (0.75, false, "practice_75_percent_complete"),
            (0.95, false, "practice_95_percent_complete")
        ]
    }

    func checkCompletionRates() {
        let progress = elapsedTime + currentTime
        let completionRate = progress / totalDuration
        
        // Check each milestone and log using AnalyticsRouter
        for milestone in ProgressMilestone.allCases {
            let threshold = Double(milestone.rawValue) / 100.0
            if !loggedMilestones.contains(milestone.rawValue) && completionRate >= threshold {
                loggedMilestones.insert(milestone.rawValue)
                
                // Use AnalyticsRouter for progress events
                AnalyticsRouter.shared.logSessionProgress(milestone: milestone.rawValue)
                
                if milestone == .seventyFive {
                    DispatchQueue.main.async {
                        self.hasReached75Percent = true
                    }
                }
                
                // When the user reaches 95% of the practice, mark it as completed
                if milestone == .ninetyFive {
                    markPracticeAsCompleted()
                }
            }
        }
        
        // Also maintain legacy completion logs for backward compatibility
        for i in completionLogs.indices where !completionLogs[i].logged && completionRate >= completionLogs[i].threshold {
            completionLogs[i].logged = true
        }
    }
    
    // Helper function to mark the practice as completed at 95%
    private func markPracticeAsCompleted() {
        guard let practiceID = self.currentPracticeID,
              let startDate = self.sessionStartDate,
              !didJustFinishSession else {
            return
        }
        
        let endDate = Date()
        
        // IMPORTANT: Do NOT call the onSessionComplete callback here
        // This would cause the PlayerScreenView to dismiss at 95%
        // Instead, we only want to mark the practice as complete in the database
        // while allowing the UI to continue until 100% completion
        // 
        // NOTE: We don't log the event here because it's already logged in checkCompletionRates()
        // when the 95% threshold is reached
        
        PracticeManager.shared.completeMeditationSession(
            practiceID: practiceID,
            startDate: startDate,
            endDate: endDate
        )
        
        // 📊 Track routine completion for journey phase progression
        // If this is a routine session, increment the counter for customization unlock
        if let audioFile = selectedFile, audioFile.category == .routines {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Routine session completed: \(practiceID) title=\(audioFile.title)")
            Task { @MainActor in
                ProductJourneyManager.shared.incrementRoutineCompletionCount()
            }
        }
        
        // 📊 Finalize heart rate tracking at 95% completion to ensure averaged values are calculated
        // Note: This will be called again at 100% completion, but stopTracking() is safe to call multiple times
        PracticeBPMTracker.shared.stopTracking()
        
        // Post a special notification specifically for UI refresh
        // This is critical for PathProgressManager to refresh immediately
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .pathStepCompletedNotification,
                object: nil,
                userInfo: ["completedPathStepID": practiceID]
            )
        }
        
        // Log that we marked the practice complete at 95% threshold for analytics purposes
        logger.infoMessage("Practice \(practiceID) marked as completed at 95% threshold")
    }

    // MARK: - Log Events & Notifications

    /// Legacy event logging - used for backward compatibility with PathAnalyticsHandler notifications
    /// Note: session_preload now uses AnalyticsRouter.shared.logSessionPreload() for unified logging
    private func logEvent(for eventName: String) {
        // Get context parameters from SessionContextManager
        var parameters = SessionContextManager.shared.getAnalyticsParameters()
        
        // Add legacy parameters for backward compatibility
        parameters["content_details"] = contentDetails
        parameters["practice_duration_minutes"] = ceil(totalDuration / 60)
        parameters["title"] = selectedFile?.title ?? "Unknown Title"
        
        // Add tags if available to help identify content type
        if let audioFile = selectedFile {
            if !audioFile.tags.isEmpty {
                parameters["tags"] = audioFile.tags.joined(separator: ",")
            }
        }
        
        // Check if this is a Path session by looking at the tags
        if let audioFile = selectedFile, audioFile.tags.contains("path") {
            if let practiceID = currentPracticeID, let stepNumber = extractStepNumber(from: practiceID) {
                parameters["path_step_number"] = stepNumber
            }
        }
        
        AnalyticsManager.shared.logEvent(eventName, parameters: parameters)
        
        // Post notification for session events (used by PathAnalyticsHandler)
        if eventName.hasPrefix("session_") || eventName.hasPrefix("practice_") {
            var userInfo: [String: Any] = [
                "eventName": eventName,
                "parameters": parameters
            ]
            
            // Include the practice ID to identify Path steps
            if let practiceID = currentPracticeID {
                userInfo["practiceID"] = practiceID
            }
            
            NotificationCenter.default.post(
                name: .didLogPracticeEvent,
                object: nil,
                userInfo: userInfo
            )
        }
    }
    
    /// Extracts a step number from a practice ID or title
    private func extractStepNumber(from id: String) -> Int? {
        // Path IDs might follow a pattern like 'path_step_1' or contain step number information
        // Try to extract numeric part using regular expression
        let pattern = "[0-9]+"
        let regex = try? NSRegularExpression(pattern: pattern)
        
        if let regex = regex,
           let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
           let range = Range(match.range, in: id) {
            return Int(id[range])
        }
        
        // If no numeric part found, check if there's a tag with a number
        if let audioFile = selectedFile, 
           let numericTag = audioFile.tags.first(where: { Int($0) != nil }) {
            return Int(numericTag)
        }
        
        return nil
    }

    // MARK: - Duration Calculation

    func calculateTotalDuration(file: AudioFile, durationIndex: Int, completion: @escaping () -> Void) {
        let selDur = file.durations[durationIndex]
        let fileName = selDur.fileName.components(separatedBy: "/").last ?? selDur.fileName
        let localURL = FileManagerHelper.shared.localFilePath(for: fileName)
        if FileManagerHelper.shared.fileExists(at: localURL) {
            let asset = AVURLAsset(url: localURL)
            Task {
                do {
                    let dur = try await asset.load(.duration)
                    let secs = CMTimeGetSeconds(dur)
                    DispatchQueue.main.async {
                        self.totalDuration = secs
                        self.remainingTime = secs
                        completion()
                    }
                } catch {
                    logger.eventMessage("Failed to load duration: \(error)")
                    DispatchQueue.main.async { completion() }
                }
            }
        } else {
            fetchAndCalculateRemoteDuration(selectedDuration: selDur, completion: completion)
        }
    }

    private func fetchAndCalculateRemoteDuration(selectedDuration: Duration, completion: @escaping () -> Void) {
        if ConnectivityHelper.isConnectedToInternet(),
           let url = getURL(for: selectedDuration.fileName) {
            isDownloading = true
            FileManagerHelper.shared.downloadFile(from: url, setDownloading: { dl in
                DispatchQueue.main.async {
                    self.isDownloading = dl
                }
            }) { localURL in
                guard let localURL = localURL else {
                    DispatchQueue.main.async {
                        self.isDownloading = false
                        completion()
                    }
                    return
                }
                let asset = AVURLAsset(url: localURL)
                Task {
                    do {
                        let dur = try await asset.load(.duration)
                        let secs = CMTimeGetSeconds(dur)
                        DispatchQueue.main.async {
                            self.totalDuration = secs
                            self.remainingTime = secs
                            self.isDownloading = false
                            completion()
                        }
                    } catch {
                        logger.eventMessage("Failed to load duration: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.isDownloading = false
                            completion()
                        }
                    }
                }
            }
        } else {
            showAlert(title: "Internet Connection Needed",
                      message: "Connect to the internet to download new files.")
            completion()
        }
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.controlsEnabled = false
        }
        DispatchQueue.main.async {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first,
               let root = window.rootViewController {
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                root.present(alert, animated: true)
            } else {
                logger.eventMessage("Unable to present alert: No root VC found.")
            }
        }
    }
}

// MARK: - MediaSessionProtocol Conformance

extension AudioPlayerManager: MediaSessionProtocol {
    var mediaTitle: String {
        selectedFile?.title ?? "Meditation"
    }
    
    var mediaSubtitle: String? {
        selectedFile?.description
    }
    
    var mediaDuration: TimeInterval {
        totalDuration
    }
    
    var mediaElapsedTime: TimeInterval {
        currentTime
    }
    
    var mediaIsPlaying: Bool {
        isPlaying
    }
    
    var mediaArtworkURL: URL? {
        guard let imageFile = selectedFile?.imageFile else { return nil }
        return URL(string: imageFile)
    }
    
    var mediaLocalArtworkName: String? {
        // Guided meditations use remote artwork URLs, not local assets
        // But fall back to PlayerBackground if no remote URL is available
        selectedFile?.imageFile == nil ? "PlayerBackground" : nil
    }
    
    func mediaPlay() {
        play()
    }
    
    func mediaPause() {
        pause()
    }
    
    func mediaSkipForward(seconds: Int) {
        skipForward()
    }
    
    func mediaSkipBackward(seconds: Int) {
        skipBackward()
    }
}
