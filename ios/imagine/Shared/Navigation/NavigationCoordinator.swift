//
//  NavigationCoordinator.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-27
//

import Combine
import Foundation
import Mixpanel
import SwiftUI
import FirebaseAuth
import FirebaseAnalytics

class NavigationCoordinator: ObservableObject {
    // Static shared instance for app-wide access
    static var shared: NavigationCoordinator?
    
    @Published var currentView: AppView = .signUp {
        didSet {
            logger.eventMessage("NavigationCoordinator: currentView changed from \(oldValue.description) to \(currentView.description)")
        }
    }
    @Published var isGuest: Bool = false // Track if the user is a guest
    @Published var deepLinkedAudioFile: AudioFile? = nil // Store the deep-linked audio file
    @Published var deepLinkedMeditationConfiguration: MeditationConfiguration? = nil // Store the deep-linked meditation configuration
    @Published var showPracticeRating: Bool = false
    @Published var practiceTitle: String? = nil
    @Published var sourceTab: Int? = nil // Store the source tab when navigating to player
    @Published var sourceTabName: String? = nil // Store the source tab name for better logging
    private var navigationStack: [AppView] = [] // Navigation stack to track view history
    
    // MARK: - Unified Player Sheet Properties
    
    /// Whether to show the unified player sheet
    @Published var showPlayerSheet: Bool = false
    
    /// Whether the last player session was fully completed (100% / session_complete).
    /// Set to `true` by PlayerScreenView when the session finishes naturally.
    /// Reset to `false` each time a new player session starts.
    @Published var lastSessionFullyCompleted: Bool = false
    
    /// The session type for the current player session
    @Published var playerSessionType: SessionType = .guided
    
    // Guided session properties
    @Published var playerAudioFile: AudioFile? = nil
    @Published var playerDurationIndex: Int = 0
    @Published var playerIsDownloading: Bool = false

    // Timer session properties
    @Published var timerMinutes: Int = 0
    /// When non-nil, session length includes intro prelude (seconds). Otherwise `timerMinutes * 60`.
    @Published var timerPlaybackDurationSeconds: Int? = nil
    @Published var timerBackgroundSound: BackgroundSound = BackgroundSound(id: "None", name: "None", url: "")
    @Published var timerCueSettings: [CueSetting] = []
    @Published var timerBinauralBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
    @Published var timerIsDeepLinked: Bool = false
    @Published var timerTitle: String? = nil
    @Published var timerDescription: String? = nil
    
    /// Computed timer config from individual properties
    var timerConfig: TimerSessionConfig? {
        guard playerSessionType == .timer else { return nil }
        return TimerSessionConfig(
            minutes: timerMinutes,
            playbackDurationSeconds: timerPlaybackDurationSeconds,
            backgroundSound: timerBackgroundSound,
            binauralBeat: timerBinauralBeat,
            cueSettings: timerCueSettings,
            isDeepLinked: timerIsDeepLinked,
            title: timerTitle,
            description: timerDescription
        )
    }
    
    // Legacy: Keep showTimerSheet for backward compatibility during migration
    @Published var showTimerSheet: Bool = false
    
    // DEPRECATED: AI chat is now a main view, not a sheet
    // Kept for backward compatibility - will be removed in future cleanup
    @Published var showAISheet: Bool = false
    
    // Track where subscription was triggered from for contextual resume
    @Published var subscriptionSource: SubscriptionSource = .unknown
    
    // Store pending AI meditation to auto-play after subscription flow exits
    var pendingAIMeditation: AITimerResponse? = nil

    init() {
        // Setup notification observer for NavigateToSignIn
        NotificationCenter.default.addObserver(self, selector: #selector(handleNavigateToSignIn), name: Notification.Name("NavigateToSignIn"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleNavigateToSignIn(notification: Notification) {
        let email = notification.userInfo?["email"] as? String ?? ""
        
        logger.eventMessage("NavigationCoordinator: Handling NavigateToSignIn notification")
        logger.eventMessage("NavigationCoordinator: - email: '\(email)'")
        
        if !email.isEmpty {
            SharedUserStorage.save(value: email, forKey: .lastUsedEmail)
            logger.eventMessage("NavigationCoordinator: Saved email to SharedUserStorage: '\(email)'")
        }
        
        DispatchQueue.main.async {
            self.currentView = .signIn(email: email)
            logger.eventMessage("NavigationCoordinator: Navigate to SignIn completed with email: '\(email)'")
        }
    }

    enum AppView: Equatable, CustomStringConvertible {
        // Onboarding flow
        case onboarding
        case subscription
        
        // EXISTING CASES
        case signUp
        case signIn(email: String = "")
        case main
        case guest
        case practiceDetail  // For practice details
        case timer           // For deep-linked timer view
        case aiChat          // For AI meditation sensei (legacy - will remove)
        // Keeping player case for backward compatibility, but we'll prefer using the sheet
        case player(audioFile: AudioFile, durationIndex: Int, isDownloading: Bool = false)
        case timerCountdown(totalMinutes: Int, backgroundSound: BackgroundSound, cueSettings: [CueSetting], isDeepLinked: Bool = false)

        var description: String {
            switch self {
            case .onboarding: return "Onboarding"
            case .subscription: return "Subscription"
            case .signUp: return "SignUp"
            case .signIn(let email):
                return "SignIn with email: \(email)"
            case .main: return "Main"
            case .guest: return "Guest"
            case .practiceDetail: return "PracticeDetail"
            case .timer: return "Timer"
            case .aiChat: return "AiChat"
            case .player(let audioFile, let durationIndex, _):
                return "Player - \(audioFile.title) (\(durationIndex))"
            case .timerCountdown(let totalMinutes, let backgroundSound, _, let isDeepLinked):
                return "TimerCountdown - \(totalMinutes) minutes, \(backgroundSound.name), deepLinked: \(isDeepLinked)"
            }
        }

        static func == (lhs: AppView, rhs: AppView) -> Bool {
            switch (lhs, rhs) {
            case (.onboarding, .onboarding),
                 (.subscription, .subscription),
                 (.signUp, .signUp),
                 (.main, .main),
                 (.guest, .guest),
                 (.practiceDetail, .practiceDetail),
                 (.timer, .timer),
                 (.aiChat, .aiChat):
                return true
            case let (.signIn(email1), .signIn(email2)):
                return email1 == email2
            case let (.player(file1, index1, _), .player(file2, index2, _)):
                return file1.id == file2.id && index1 == index2
            case let (.timerCountdown(minutes1, sound1, cues1, deepLinked1), .timerCountdown(minutes2, sound2, cues2, deepLinked2)):
                return minutes1 == minutes2 && sound1.id == sound2.id && cues1.count == cues2.count && deepLinked1 == deepLinked2
            default:
                return false
            }
        }
    }

    // Navigate to a new view and push it onto the stack.
    func navigateTo(_ view: AppView) {
        logger.eventMessage("NavigationCoordinator: Navigating to \(view.description)")
        if view != currentView {
            navigationStack.append(currentView)
            currentView = view
        } else {
            logger.eventMessage("NavigationCoordinator: Attempted to navigate to the same view: \(view.description). Skipping stack operation.")
        }
    }

    // Navigate back to the previous view in the stack.
    func navigateBack() {
        if let lastView = navigationStack.popLast() {
            logger.eventMessage("NavigationCoordinator: Navigating back to \(lastView.description)")
            currentView = lastView
        } else {
            logger.eventMessage("NavigationCoordinator: Navigation stack is empty. Cannot navigate back.")
        }
    }

    // Check if navigation stack is empty.
    func isNavigationStackEmpty() -> Bool {
        return navigationStack.isEmpty
    }

    // Navigate to PracticeDetailView, handling deep link.
    // Modified to show player as sheet
    func navigateToPracticeDetail(with audioFile: AudioFile) {
        logger.eventMessage("NavigationCoordinator: Showing Player sheet with AudioFile ID: \(audioFile.id)")
        self.deepLinkedAudioFile = audioFile
        // Show player as sheet instead of navigating
        showPlayerAsSheet(with: audioFile, isDownloading: true)
    }

    /// Reset the state for PracticeRatingView.
    func resetPracticeRating() {
        logger.eventMessage("NavigationCoordinator: Resetting PracticeRatingView state.")
        showPracticeRating = false
        practiceTitle = nil
    }

    // Updated to show PlayerScreenView as a sheet instead of navigating
    func navigateToPlayer(with audioFile: AudioFile, durationIndex: Int = 0, isDownloading: Bool = false) {
        logger.eventMessage("NavigationCoordinator: Showing Player sheet with AudioFile ID: \(audioFile.id)")
        
        // Capture the current tab for analytics purposes
        NotificationCenter.default.post(name: NSNotification.Name("StoreCurrentTab"), object: nil)
        
        logger.eventMessage("NavigationCoordinator: Source tab before player: \(sourceTab ?? -1), name: \(sourceTabName ?? "unknown")")
        
        // Instead of navigation, set up and show the player sheet
        showPlayerAsSheet(with: audioFile, durationIndex: durationIndex, isDownloading: isDownloading)
    }

    // Method to show guided player as a sheet
    private func showPlayerAsSheet(with audioFile: AudioFile, durationIndex: Int = 0, isDownloading: Bool = false) {
        self.playerSessionType = .guided
        self.playerAudioFile = audioFile
        self.playerDurationIndex = durationIndex
        self.playerIsDownloading = isDownloading
        self.lastSessionFullyCompleted = false
        self.showPlayerSheet = true
    }
    
    /// Show timer session via unified player sheet
    func showTimerPlayerSheet(minutes: Int, playbackDurationSeconds: Int? = nil, backgroundSound: BackgroundSound, cueSettings: [CueSetting], binauralBeat: BinauralBeat, isDeepLinked: Bool = false, title: String? = nil, description: String? = nil) {
        logger.eventMessage("NavigationCoordinator: Showing unified timer player sheet with duration: \(minutes) minutes, title: \(title ?? "nil")")

        // Capture the current tab for analytics purposes
        NotificationCenter.default.post(name: NSNotification.Name("StoreCurrentTab"), object: nil)

        self.playerSessionType = .timer
        self.timerMinutes = minutes
        self.timerPlaybackDurationSeconds = playbackDurationSeconds
        self.timerBackgroundSound = backgroundSound
        self.timerCueSettings = cueSettings
        self.timerBinauralBeat = binauralBeat
        self.timerIsDeepLinked = isDeepLinked
        self.timerTitle = title
        self.timerDescription = description
        self.lastSessionFullyCompleted = false
        self.showPlayerSheet = true
    }

    /// Show timer session via unified player sheet (convenience overload with TimerSessionConfig)
    func showTimerPlayerSheet(timerConfig: TimerSessionConfig) {
        showTimerPlayerSheet(
            minutes: timerConfig.minutes,
            playbackDurationSeconds: timerConfig.playbackDurationSeconds,
            backgroundSound: timerConfig.backgroundSound,
            cueSettings: timerConfig.cueSettings,
            binauralBeat: timerConfig.binauralBeat,
            isDeepLinked: timerConfig.isDeepLinked,
            title: timerConfig.title,
            description: timerConfig.description
        )
    }
    
    // Method to dismiss the player sheet
    func dismissPlayerSheet() {
        logger.eventMessage("NavigationCoordinator: Dismissing player sheet (sessionType: \(playerSessionType))")
        
        let wasTimerSession = playerSessionType == .timer
        self.showPlayerSheet = false
        
        // Auto-navigate to Sensei after timer dismissal via menu selection
        if wasTimerSession {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // Navigate to Sensei view (index 0 in new menu system)
                NotificationCenter.default.post(name: NSNotification.Name("SelectTab"), object: 0)
            }
        }
    }
    
    /// Dismiss player sheet and navigate to AI chat (used for Path step completion)
    func dismissPlayerSheetToAI() {
        logger.eventMessage("NavigationCoordinator: Dismissing player sheet to AI (Path completion)")
        self.showPlayerSheet = false
        
        // Navigate to Sensei view (index 0 in menu system) after sheet dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(name: NSNotification.Name("SelectTab"), object: 0)
        }
    }

    // Updated method to show timer via unified player sheet
    func navigateToTimerCountdown(totalMinutes: Int, playbackDurationSeconds: Int? = nil, backgroundSound: BackgroundSound, cueSettings: [CueSetting], binauralBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil), isDeepLinked: Bool = false, title: String? = nil, description: String? = nil) {
        logger.eventMessage("NavigationCoordinator: Showing Timer via unified player sheet with duration: \(totalMinutes) minutes, title: \(title ?? "nil")")

        logger.eventMessage("NavigationCoordinator: Source tab before timer: \(sourceTab ?? -1), name: \(sourceTabName ?? "unknown")")

        // Use unified player sheet for timer sessions
        showTimerPlayerSheet(minutes: totalMinutes, playbackDurationSeconds: playbackDurationSeconds, backgroundSound: backgroundSound, cueSettings: cueSettings, binauralBeat: binauralBeat, isDeepLinked: isDeepLinked, title: title, description: description)
    }

    // Legacy method to show timer as separate sheet (for backward compatibility)
    private func showTimerAsSheet(minutes: Int, backgroundSound: BackgroundSound, cueSettings: [CueSetting], binauralBeat: BinauralBeat, isDeepLinked: Bool) {
        self.timerMinutes = minutes
        self.timerBackgroundSound = backgroundSound
        self.timerCueSettings = cueSettings
        self.timerBinauralBeat = binauralBeat
        self.timerIsDeepLinked = isDeepLinked
        self.showTimerSheet = true
    }
    
    // Legacy method to dismiss the timer sheet (for backward compatibility)
    func dismissTimerSheet() {
        logger.eventMessage("NavigationCoordinator: Dismissing timer sheet (legacy)")
        self.showTimerSheet = false
        // Auto-navigate to Sensei after timer dismissal via menu selection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // Navigate to Sensei view (index 0 in new menu system)
            NotificationCenter.default.post(name: NSNotification.Name("SelectTab"), object: 0)
        }
    }

    /// Shows the Player directly from a deep-linked meditation configuration (skips Create UI).
    func showPlayerFromDeepLink(meditationConfiguration: MeditationConfiguration) {
        logger.eventMessage("NavigationCoordinator: Showing Player from deep link - duration: \(meditationConfiguration.duration), sound: \(meditationConfiguration.backgroundSound.name)")

        let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
        let timerConfig = meditationConfiguration.toTimerSessionConfig(voiceId: voiceId, isDeepLinked: true)
        Task { @MainActor in
            logger.timerDeepLink("player_sheet path=MeditationConfiguration pre_cues=\(timerConfig.cueSettings.count)")
            let hydrated = await FractionalDeepLinkPlaybackHydrator.hydrateIfNeeded(timerConfig)
            logger.timerDeepLink("player_sheet path=MeditationConfiguration post_cues=\(hydrated.cueSettings.count)")
            self.presentPlayerForDeepLinkedTimer(timerConfig: hydrated)
        }
    }

    /// Shows the Player from a portable-plan deep link (`dlv=2` + `pz` / fragment / `plan=`) — may hydrate collapsed `_FRAC` rows via `postFractionalPlan`.
    func showPlayerFromDeepLinkedTimerConfig(_ timerConfig: TimerSessionConfig) {
        logger.timerDeepLink("player_sheet path=portable_plan pre_cues=\(timerConfig.cueSettings.count) durMin=\(timerConfig.minutes)")
        Task { @MainActor in
            let hydrated = await FractionalDeepLinkPlaybackHydrator.hydrateIfNeeded(timerConfig)
            logger.timerDeepLink("player_sheet path=portable_plan post_cues=\(hydrated.cueSettings.count)")
            self.presentPlayerForDeepLinkedTimer(timerConfig: hydrated)
        }
    }

    private func presentPlayerForDeepLinkedTimer(timerConfig: TimerSessionConfig) {
        // Subscription gate: if user must subscribe first, show subscription flow
        if SubscriptionManager.shared.shouldGatePlay {
            logger.timerDeepLink("player_present blocked reason=subscription_gate cues=\(timerConfig.cueSettings.count)")
            SubscriptionManager.shared.logGateState()
            subscriptionSource = .createScreen
            navigateTo(.subscription)
            return
        }

        logger.timerDeepLink("player_present ok cues=\(timerConfig.cueSettings.count) durMin=\(timerConfig.minutes)")

        // Navigate to main view to ensure proper view hierarchy for sheet presentation
        currentView = .main

        SessionContextManager.shared.setupCustomMeditationSession(
            entryPoint: .deepLink,
            timerConfig: timerConfig,
            origin: .userSelected,
            customizationLevel: .none
        )

        GeneralBackgroundMusicController.shared.fadeOutForPractice()

        showTimerPlayerSheet(
            minutes: timerConfig.minutes,
            playbackDurationSeconds: timerConfig.playbackDurationSeconds,
            backgroundSound: timerConfig.backgroundSound,
            cueSettings: timerConfig.cueSettings,
            binauralBeat: timerConfig.binauralBeat,
            isDeepLinked: true,
            title: timerConfig.title,
            description: timerConfig.description
        )
    }

    // Apply deep link meditation configuration and navigate to the timer menu item (legacy - used by AI flow)
    func applyDeepLinkMeditationConfiguration(_ configuration: MeditationConfiguration) {
        logger.eventMessage("NavigationCoordinator: Applying deep link meditation configuration - duration: \(configuration.duration), sound: \(configuration.backgroundSound.name)")
        
        // Set the deep linked meditation configuration
        self.deepLinkedMeditationConfiguration = configuration
        
        // Navigate to main view to ensure proper view hierarchy
        currentView = .main
        
        // Add small delay to ensure view hierarchy is properly set up before menu selection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            logger.eventMessage("NavigationCoordinator: Posting SelectTab notification for Timer menu item (index 3)")
            // Select the Timer menu item (index 3 in new menu system: Sensei=0, Explore=1, Path=2, Timer=3)
            NotificationCenter.default.post(name: NSNotification.Name("SelectTab"), object: 3)
        }
    }
    
    // Backward compatibility method
    func applyDeepLinkTimerSettings(_ timerSetting: MeditationConfiguration) {
        applyDeepLinkMeditationConfiguration(timerSetting)
    }

    // Simplified to just handle tab selection as needed for analytics
    func navigateBackToSourceTab() {
        if let tab = sourceTab {
            logger.eventMessage("NavigationCoordinator: Restoring tab \(tab), name: \(sourceTabName ?? "unknown")")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: NSNotification.Name("SelectTab"), object: tab)
                self.sourceTab = nil
                self.sourceTabName = nil
            }
        }
    }
    
    // DEPRECATED: Navigate to AI Chat - now navigates via menu selection
    // Kept for backward compatibility - will be removed in future cleanup
    func navigateToAIChat() {
        logger.eventMessage("NavigationCoordinator: Navigating to Sensei via menu selection (legacy navigateToAIChat)")
        currentView = .main
        // Navigate to Sensei view (index 0 in new menu system)
        NotificationCenter.default.post(name: NSNotification.Name("SelectTab"), object: 0)
    }

    // DEPRECATED: Dismiss AI chat sheet - AI chat is now a main view
    // Kept for backward compatibility - will be removed in future cleanup
    func dismissAISheet() {
        logger.eventMessage("NavigationCoordinator: dismissAISheet called (deprecated - AI is now main view)")
        showAISheet = false
    }
    
    // Configure for guest mode
    func configureForGuestMode() {
        logger.eventMessage("NavigationCoordinator: Configuring for guest mode")
        self.isGuest = true
        
        print("NavigationCoordinator: Configured guest mode with anonymous Firebase user")
    }
    
    // Handle guest logout and redirect to sign up
    func handleGuestLogout() {
        logger.eventMessage("NavigationCoordinator: Handling guest logout and redirecting to sign up")
        
        // Clear guest status
        self.isGuest = false
        
        // Reset navigation stack
        navigationStack = []
        
        // Set current view to sign up
        self.currentView = .signUp
    }
}

// MARK: - Subscription Source Tracking

/// Tracks where the subscription flow was triggered from for contextual resume behavior
enum SubscriptionSource: String {
    case unknown
    case onboarding
    case aiFirstMeditationPlay
    case aiMeditationRequest
    case pathStep
    case explore
    case createScreen
    case history
}
