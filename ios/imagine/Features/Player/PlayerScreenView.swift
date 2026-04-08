//
//  PlayerScreenView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-17
//
//  Unified player screen supporting both guided (MP3) and timer meditation sessions.
//

import SwiftUI
import MediaPlayer
import Kingfisher
import UIKit
import Combine

extension View {
    func swipeBackEntireScreen(action: @escaping () -> Void) -> some View {
        self.gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width > 50 && abs(value.translation.height) < 50 {
                        action()
                    }
                }
        )
    }
    
    func swipeDownFromTop(action: @escaping () -> Void) -> some View {
        self.gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    // Only trigger if:
                    // 1. Swipe starts from top 150px of screen
                    // 2. Swipe is primarily downward (translation.height > 50)
                    // 3. Horizontal movement is minimal (abs(translation.width) < 100)
                    if value.startLocation.y < 150 && 
                       value.translation.height > 50 && 
                       abs(value.translation.width) < 100 {
                        action()
                    }
                }
        )
    }
}

struct PlayerScreenView: View {
    // MARK: - Session Type
    
    /// The type of session being played
    var sessionType: SessionType
    
    // MARK: - Guided Session Properties
    
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    var selectedFile: AudioFile?
    @Binding var durationIndex: Int
    
    // MARK: - Timer Session Properties
    
    /// Timer session configuration (used to create timerSession on appear)
    var timerConfig: TimerSessionConfig?
    
    /// Timer session instance (created from config)
    @StateObject private var timerSessionState: TimerMeditationSessionWrapper = TimerMeditationSessionWrapper()
    
    // MARK: - Environment
    
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    // MARK: - State
    
    @State private var hasSessionCompleted = false
    @State private var isNavigatingBack = false
    @State private var capturedHeartRateResults: HeartRateResults = HeartRateResults.empty
    @State private var isPreparingTimerAssets: Bool = false
    
    // MARK: - Offline Mode State
    
    @State private var showOfflineAlert = false
    @State private var offlineAlertMessage = ""

    // MARK: - Initialization
    
    /// Initialize for guided (MP3) session
    init(audioPlayerManager: AudioPlayerManager, selectedFile: AudioFile, durationIndex: Binding<Int>) {
        self.sessionType = .guided
        self.audioPlayerManager = audioPlayerManager
        self.selectedFile = selectedFile
        self._durationIndex = durationIndex
        self.timerConfig = nil
    }
    
    /// Initialize for timer session
    init(audioPlayerManager: AudioPlayerManager, timerConfig: TimerSessionConfig) {
        self.sessionType = .timer
        self.audioPlayerManager = audioPlayerManager
        self.selectedFile = nil
        self._durationIndex = .constant(0)
        self.timerConfig = timerConfig
    }
    
    /// Unified initializer with session type
    init(
        sessionType: SessionType,
        audioPlayerManager: AudioPlayerManager,
        selectedFile: AudioFile? = nil,
        durationIndex: Binding<Int> = .constant(0),
        timerConfig: TimerSessionConfig? = nil
    ) {
        self.sessionType = sessionType
        self.audioPlayerManager = audioPlayerManager
        self.selectedFile = selectedFile
        self._durationIndex = durationIndex
        self.timerConfig = timerConfig
    }

    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.backgroundDarkPurple
                .ignoresSafeArea()
                .edgesIgnoringSafeArea(.all)
            
            // Player view (all sessions now route to AI chat for post-practice)
            PlayerView(
                sessionType: sessionType,
                audioPlayerManager: audioPlayerManager,
                selectedFile: selectedFile,
                durationIndex: $durationIndex,
                timerSessionWrapper: timerSessionState,
                isPreparingTimerAssets: $isPreparingTimerAssets,
                onBackButtonPress: handleBackButtonPress
            )
        }
        .onFirstAppear {
            setupSession()
        }
        .onDisappear {
            cleanupSession()
        }
        .onChange(of: hasSessionCompleted) { _, newValue in
            if newValue {
                handleSessionCompletion()
            }
        }
        .onChange(of: audioPlayerManager.hasReached75Percent) { _, newValue in
            if newValue && sessionType == .guided, let file = selectedFile {
                navigationCoordinator.practiceTitle = file.title
                navigationCoordinator.showPracticeRating = true
            }
        }
        .onChange(of: timerSessionState.session?.hasReached75Percent) { _, newValue in
            if newValue == true && sessionType == .timer {
                navigationCoordinator.practiceTitle = "Meditation Session"
                navigationCoordinator.showPracticeRating = true
            }
        }
        .onChange(of: selectedFile) { oldFile, newFile in
            if let oldFile = oldFile, let newFile = newFile {
                handleFileChange(from: oldFile, to: newFile)
            }
        }
        .navigationBarHidden(true)
        .swipeDownFromTop {
            handleBackButtonPress()
        }
        .background(InteractivePopGestureSetter())
        .environmentObject(navigationCoordinator)
        .background(Color.black.opacity(0.4).edgesIgnoringSafeArea(.all))
        .edgesIgnoringSafeArea(.all)
        .zIndex(100)
        .alert("No Internet Connection", isPresented: $showOfflineAlert) {
            Button("OK") {
                dismissPlayerSheet()
            }
        } message: {
            Text(offlineAlertMessage)
        }
    }
    
    // MARK: - Session Setup & Cleanup
    
    private func setupSession() {
        switch sessionType {
        case .guided:
            setupGuidedSession()
        case .timer:
            setupTimerSession()
        }
    }
    
    private func setupGuidedSession() {
        guard let file = selectedFile else {
            logger.errorMessage("PlayerScreenView: Guided session requires selectedFile")
            return
        }
        
        // Check if assets are available offline
        let availability = OfflineAssetChecker.checkGuidedMeditation(file, durationIndex: durationIndex)
        
        if !availability.allAvailable && !NetworkMonitor.shared.isConnected {
            // Assets missing and no internet - show alert and exit
            logger.eventMessage("PlayerScreenView: Cannot play guided meditation offline - assets not cached")
            offlineAlertMessage = "This meditation hasn't been downloaded yet. Please connect to the internet to download it first."
            showOfflineAlert = true
            return
        }
        
        UIApplication.shared.beginReceivingRemoteControlEvents()
        audioPlayerManager.onSessionComplete = {
            self.hasSessionCompleted = true
        }
        
        // Reset captured heart rate results for new session
        capturedHeartRateResults = HeartRateResults.empty
        logger.eventMessage("PlayerScreenView: RESET captured heart rate results for new practice session: '\(file.title)'")
        
        // Notify the central audio controller that a meditation is starting.
        // This mutes background music and activates the .playback audio session.
        AppAudioLifecycleController.shared.meditationDidStart()
        
        // Reset session state
        resetSessionState()
    }
    
    private func setupTimerSession() {
        guard let config = timerConfig else {
            logger.errorMessage("PlayerScreenView: Timer session requires timerConfig")
            return
        }
        
        // Check if assets are available offline
        let availability = OfflineAssetChecker.checkTimerMeditation(config)
        
        if !availability.allAvailable && !NetworkMonitor.shared.isConnected {
            // Assets missing and no internet - show alert and exit
            logger.eventMessage("PlayerScreenView: Cannot play timer meditation offline - \(availability.missingAssets.count) assets not cached")
            offlineAlertMessage = "Some audio files for this meditation aren't downloaded yet. Please connect to the internet to download them."
            showOfflineAlert = true
            return
        }
        
        // Create timer session from config
        let session = TimerMeditationSession(config: config)
        timerSessionState.session = session
        
        // Set completion handler
        session.onSessionComplete = {
            self.hasSessionCompleted = true
        }
        
        // Reset captured heart rate results
        capturedHeartRateResults = HeartRateResults.empty
        logger.eventMessage("PlayerScreenView: Setup timer session for \(config.minutes) minutes")
        
        // Timer session's start() will call meditationDidStart() via the controller,
        // so we don't need to call it here. Just reset session state.
        
        // Reset session state
        resetSessionState()
        
        // Prepare timer assets (background sound, binaural beat, cues) before playback
        // Skip if all assets are already cached
        if availability.allAvailable {
            logger.eventMessage("PlayerScreenView: All timer assets already cached - skipping download")
        } else {
            isPreparingTimerAssets = true
            Task { @MainActor in
                await prepareTimerAssets(for: config)
                isPreparingTimerAssets = false
                logger.eventMessage("PlayerScreenView: Timer assets prepared and ready")
            }
        }
    }
    
    /// Downloads and caches all audio assets needed for the timer session
    private func prepareTimerAssets(for config: TimerSessionConfig) async {
        let uniqueURLs = config.allTimerAssetRemoteURLStrings()
        guard !uniqueURLs.isEmpty else {
            logger.eventMessage("PlayerScreenView: No timer assets to prepare")
            return
        }
        
        logger.eventMessage("PlayerScreenView: Preparing \(uniqueURLs.count) timer assets...")
        
        // Download all assets in parallel
        await withTaskGroup(of: Void.self) { group in
            for urlString in uniqueURLs {
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        FileManagerHelper.shared.ensureLocalFile(forRemoteURLString: urlString, setDownloading: { _ in }, completion: { _ in
                            continuation.resume()
                        })
                    }
                }
            }
            await group.waitForAll()
        }
    }
    
    private func cleanupSession() {
        switch sessionType {
        case .guided:
            cleanupGuidedSession()
        case .timer:
            cleanupTimerSession()
        }
    }
    
    private func cleanupGuidedSession() {
        UIApplication.shared.endReceivingRemoteControlEvents()
        
        if let file = selectedFile {
            AnalyticsManager.shared.logEvent("automatic_heart_rate_monitoring_stopped", parameters: [
                "practice_id": file.id,
                "practice_title": file.title,
                "reason": isNavigatingBack ? "user_navigation" : "session_cleanup"
            ])
        }
        
        if !isNavigatingBack {
            audioPlayerManager.stopAudio() { }
            AppAudioLifecycleController.shared.meditationDidEnd()
        }
    }
    
    private func cleanupTimerSession() {
        if !isNavigatingBack {
            // Only call stop() if session didn't complete naturally.
            // When the session completed, handleSessionComplete() already
            // scheduled a delayed meditationDidEnd() to let the end cue
            // (gentle bell) finish playing. We must not call it here or
            // the bell gets killed early.
            if !hasSessionCompleted {
                timerSessionState.session?.stop()
            }
        }
    }
    
    // MARK: - Session Management
    
    private func handleSessionCompletion() {
        // Mark that this session was fully completed (100%) so recommendation cards
        // can distinguish a true completion from a partial play that was manually closed.
        navigationCoordinator.lastSessionFullyCompleted = true
        
        switch sessionType {
        case .guided:
            handleGuidedSessionCompletion()
        case .timer:
            handleTimerSessionCompletion()
        }
    }
    
    private func handleGuidedSessionCompletion() {
        let completionRate = (audioPlayerManager.currentTime / audioPlayerManager.totalDuration) * 100
        
        if audioPlayerManager.didJustFinishSession {
            // Capture heart rate results
            capturedHeartRateResults = HeartRateResults.from(PracticeBPMTracker.shared)
            
            if let file = selectedFile {
                logger.eventMessage("PlayerScreenView: CAPTURED SNAPSHOT for '\(file.title)' - hasValidData: \(capturedHeartRateResults.hasValidData), samples: \(capturedHeartRateResults.sampleCount)")
                
                // Route to AI chat - Path steps go through AIPathPostSessionManager, others through AIExplorePostSessionManager
                if file.tags.contains("path") {
                    handlePathStepCompletion(file: file)
                } else {
                    handleExploreSessionCompletion(file: file)
                }
            }
        } else if completionRate >= 75 {
            if let file = selectedFile {
                navigationCoordinator.practiceTitle = file.title
                navigationCoordinator.showPracticeRating = true
            }
            dismissPlayerSheet()
        }
    }
    
    /// Handle Path step completion - route to AI chat
    private func handlePathStepCompletion(file: AudioFile) {
        logger.aiChat("📋 [POST_PRACTICE] COMPLETION_TRIGGERED type=path step=\(file.id)")
        
        let durationMinutes = Int(ceil(audioPlayerManager.totalDuration / 60))
        let hrResults = capturedHeartRateResults
        
        // Queue the Path post-practice message for AI chat via unified manager
        // Path progress resolution happens inside the manager
        // Use Task to await the async handler - ensures report is persisted before continuing
        Task { @MainActor in
            logger.aiChat("📋 [POST_PRACTICE] COMPLETION_AWAIT_START type=path")
            await UnifiedPostSessionManager.shared.handleCompletedSession(
                type: .path(stepId: file.id, step: nil, nextStep: nil, isPathComplete: false),
                durationMinutes: durationMinutes,
                heartRateResults: hrResults
            )
            logger.aiChat("📋 [POST_PRACTICE] COMPLETION_AWAIT_DONE type=path")
        }
        
        // Navigate to AI chat
        navigationCoordinator.dismissPlayerSheetToAI()
    }
    
    /// Handle Explore session completion - route to AI chat
    private func handleExploreSessionCompletion(file: AudioFile) {
        logger.aiChat("📋 [POST_PRACTICE] COMPLETION_TRIGGERED type=explore file=\(file.id)")
        
        let durationMinutes = Int(ceil(audioPlayerManager.totalDuration / 60))
        let hrResults = capturedHeartRateResults
        
        // Queue the Explore post-practice message for AI chat via unified manager
        // Use Task to await the async handler - ensures report is persisted before continuing
        Task { @MainActor in
            logger.aiChat("📋 [POST_PRACTICE] COMPLETION_AWAIT_START type=explore")
            await UnifiedPostSessionManager.shared.handleCompletedSession(
                type: .explore(file: file),
                durationMinutes: durationMinutes,
                heartRateResults: hrResults
            )
            logger.aiChat("📋 [POST_PRACTICE] COMPLETION_AWAIT_DONE type=explore")
        }
        
        // Navigate to AI chat
        navigationCoordinator.dismissPlayerSheetToAI()
    }
    
    private func handleTimerSessionCompletion() {
        // Timer sessions skip post practice - dismiss directly
        // NavigationCoordinator will show AI sheet after dismissal
        logger.eventMessage("PlayerScreenView: Timer session completed, dismissing")
        dismissPlayerSheet()
    }
    
    private func resetSessionState() {
        hasSessionCompleted = false
        capturedHeartRateResults = HeartRateResults.empty
        
        if sessionType == .guided {
            audioPlayerManager.didJustFinishSession = false
        }
        
        // NOTE: Do NOT call PracticeBPMTracker.shared.resetData() here.
        // PlayerView.handleOnAppear() calls startNewSession() which already clears data.
        // Calling resetData() here creates a race condition that wipes out tracking state.
        logger.eventMessage("PlayerScreenView: Session state reset")
    }
    
    private func handleFileChange(from oldFile: AudioFile, to newFile: AudioFile) {
        guard sessionType == .guided else { return }
        
        if oldFile.id != newFile.id {
            logger.eventMessage("PlayerScreenView: File changed from \(oldFile.title) to \(newFile.title)")
            resetSessionState()
            
            audioPlayerManager.endSession {
                audioPlayerManager.preloadAudioFile(file: newFile, durationIndex: durationIndex) {
                    logger.eventMessage("New audio file preloaded and ready for playback")
                }
            }
        }
    }
    
    // MARK: - Navigation
    
    private func handleBackButtonPress() {
        isNavigatingBack = true
        
        switch sessionType {
        case .guided:
            handleGuidedBackPress()
        case .timer:
            handleTimerBackPress()
        }
    }
    
    private func handleGuidedBackPress() {
        audioPlayerManager.endSession { [self] in
            let completionRate = (audioPlayerManager.currentTime / audioPlayerManager.totalDuration) * 100
            if completionRate >= 75, let file = selectedFile {
                navigationCoordinator.practiceTitle = file.title
                navigationCoordinator.showPracticeRating = true
            }
            if !hasSessionCompleted {
                logPracticeAborted()
            }
            
            AppAudioLifecycleController.shared.meditationDidEnd()
            
            dismissPlayerSheet()
        }
    }
    
    private func handleTimerBackPress() {
        // Log abort if session hasn't completed
        if !hasSessionCompleted {
            timerSessionState.session?.logAborted()
        }
        
        // stop() calls meditationDidEnd() via the controller
        timerSessionState.session?.stop()
        
        dismissPlayerSheet()
    }
    
    private func dismissPlayerSheet() {
        navigationCoordinator.dismissPlayerSheet()
    }
    
    // MARK: - Helper Functions
    
    private func logPracticeAborted() {
        guard sessionType == .guided, let file = selectedFile else { return }
        
        let abortTimeSeconds = audioPlayerManager.currentTime
        let completionRate = (audioPlayerManager.currentTime / audioPlayerManager.totalDuration) * 100
        let abortedAt = AppFunctions.formatTime(audioPlayerManager.currentTime)
        let contentDetails = audioPlayerManager.contentDetails
        let practiceDurationMinutes = Int(ceil(audioPlayerManager.totalDuration / 60))
        
        AnalyticsManager.shared.logEvent("practice_aborted", parameters: [
            "abort_time_seconds": abortTimeSeconds,
            "aborted_at": abortedAt,
            "completion_rate": completionRate,
            "content_details": contentDetails,
            "practice_duration_minutes": practiceDurationMinutes,
            "title": file.title,
            "source": audioPlayerManager.recommendationSource ?? ""
        ])
    }
}

// MARK: - Timer Session Wrapper

/// Wrapper to hold optional timer session as StateObject and forward its changes
class TimerMeditationSessionWrapper: ObservableObject {
    @Published var session: TimerMeditationSession? {
        didSet {
            // Cancel old subscription
            cancellable?.cancel()
            // Subscribe to new session's changes so parent view re-renders
            if let newSession = session {
                cancellable = newSession.objectWillChange
                    .sink { [weak self] _ in
                        self?.objectWillChange.send()
                    }
            }
        }
    }
    private var cancellable: AnyCancellable?
}

// MARK: - Preview

#if DEBUG
#Preview("Guided Session") {
    let audioPlayerManager = AudioPlayerManager()
    audioPlayerManager.isPlaying = false
    
    return PlayerScreenView(
        audioPlayerManager: audioPlayerManager,
        selectedFile: AudioFile(
            id: "deepdive_002",
            title: "Transform Anger",
            category: .deepdive,
            description: "Experience a profound transformation as you learn to channel anger into positive energy.",
            imageFile: "practicePreview",
            durations: [
                Duration(length: 8, fileName: "gs://imagine-c6162.appspot.com/learn/Session_1.mp3")
            ],
            premium: false,
            tags: ["Breath work", "Visualization"]
        ),
        durationIndex: .constant(0)
    )
    .withPreviewEnvironment()
    .environmentObject(NavigationCoordinator())
    .preferredColorScheme(.dark)
}

#Preview("Timer Session") {
    let audioPlayerManager = AudioPlayerManager()
    audioPlayerManager.isPlaying = false
    
    return PlayerScreenView(
        audioPlayerManager: audioPlayerManager,
        timerConfig: TimerSessionConfig(minutes: 10)
    )
    .withPreviewEnvironment()
    .environmentObject(NavigationCoordinator())
    .preferredColorScheme(.dark)
}

#Preview("Timer Session – Full") {
    let audioPlayerManager = AudioPlayerManager()
    audioPlayerManager.isPlaying = false
    
    let richConfig = TimerSessionConfig(
        minutes: 8,
        backgroundSound: BackgroundSound(id: "B1", name: "Nature ambience", url: "test"),
        binauralBeat: BinauralBeat(id: "BB1", name: "6 Hz (vision)", url: "test", description: nil),
        cueSettings: [
            CueSetting(triggerType: .start, cue: Cue(id: "C1", name: "General Introduction", url: "test")),
            CueSetting(triggerType: .minute, minute: 1, cue: Cue(id: "C2", name: "Perfect breath", url: "test")),
            CueSetting(triggerType: .minute, minute: 3, cue: Cue(id: "C3", name: "Body scan", url: "test")),
            CueSetting(triggerType: .end, cue: Cue(id: "C4", name: "Gentle Bell", url: "test"))
        ],
        title: "Morning Focus"
    )
    
    return PlayerScreenView(
        audioPlayerManager: audioPlayerManager,
        timerConfig: richConfig
    )
    .withPreviewEnvironment()
    .environmentObject(NavigationCoordinator())
    .preferredColorScheme(.dark)
}
#endif
