import SwiftUI

/// Root view for the app that determines which flow to display based on the AppState.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var audioPlayerManager: AudioPlayerManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var timerManager: MeditationSessionTimer
    
    // Observe ProductJourneyManager for pre-app phase state changes (enables reactive routing)
    @ObservedObject private var journeyManager = ProductJourneyManager.shared
    
    // Keep state for tracking download state in sheets
    @State private var isDownloading: Bool = false
    
    var body: some View {
        ZStack {
            if !appState.isAuthenticated {
                // User is not authenticated, show authentication flow
                authenticationFlow
            } else if !journeyManager.isOnboardingComplete {
                // Onboarding not complete, show onboarding flow
                // Uses published property for SwiftUI reactivity (enables dev mode skip-to)
                OnboardingContainerView()
                    .environmentObject(navigationCoordinator)
                    .environmentObject(appState)
                    .transition(.opacity)
            } else if navigationCoordinator.currentView == .subscription {
                // In-app subscription trigger (uses same view as post-onboarding)
                SubscriptionContainerView()
                    .environmentObject(navigationCoordinator)
                    .environmentObject(subscriptionManager)
                    .environmentObject(appState)
                    .transition(.opacity)
            } else {
                // User is authenticated and pre-app phases complete, show main app
                mainAppFlow
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: appState.isAuthenticated)
        .animation(.easeInOut, value: navigationCoordinator.currentView)
        .animation(.easeInOut, value: journeyManager.isOnboardingComplete)
        // Unified player sheet - supports both guided and timer sessions
        .sheet(
            isPresented: Binding(
                get: { navigationCoordinator.showPlayerSheet },
                set: { navigationCoordinator.showPlayerSheet = $0 }
            )
        ) {
            unifiedPlayerSheetContent
        }
        // Timer sheet - now uses unified PlayerScreenView
        .sheet(
            isPresented: Binding(
                get: { navigationCoordinator.showTimerSheet },
                set: { navigationCoordinator.showTimerSheet = $0 }
            )
        ) {
            PlayerScreenView(
                audioPlayerManager: audioPlayerManager,
                timerConfig: TimerSessionConfig(
                    minutes: navigationCoordinator.timerMinutes,
                    backgroundSound: navigationCoordinator.timerBackgroundSound,
                    binauralBeat: navigationCoordinator.timerBinauralBeat,
                    cueSettings: navigationCoordinator.timerCueSettings,
                    isDeepLinked: navigationCoordinator.timerIsDeepLinked
                )
            )
            .environmentObject(navigationCoordinator)
            .environmentObject(subscriptionManager)
        }
        // AI Chat sheet removed - Sensei is now a main view in the side menu navigation
        .onAppear {
            logger.eventMessage("ContentView appeared - Auth: \(appState.isAuthenticated), CurrentView: \(navigationCoordinator.currentView)")
        }
        .onChange(of: appState.isAuthenticated) { _, newValue in
            print("ContentView: AppState.isAuthenticated changed to: \(newValue)")
        }
        .onChange(of: appState.isGuest) { _, newValue in
            print("ContentView: AppState.isGuest changed to: \(newValue)")
        }
    }
    
    /// Authentication flow - either sign in or sign up.
    private var authenticationFlow: some View {
        Group {
            switch navigationCoordinator.currentView {
            case .signIn(let email):
                AuthenticationScreen(mode: .signIn, authViewModel: AuthViewModel(), email: email)
                    .environmentObject(navigationCoordinator)
                    .environmentObject(subscriptionManager)
                    .environmentObject(appState)
            default:
                AuthenticationScreen(mode: .signUp, authViewModel: AuthViewModel())
                    .environmentObject(navigationCoordinator)
                    .environmentObject(subscriptionManager)
                    .environmentObject(appState)
            }
        }
    }
    
    /// Main app flow - includes the main container view for side menu navigation.
    private var mainAppFlow: some View {
        ZStack {
            // Main container with side menu navigation
            if case .main = navigationCoordinator.currentView {
                mainContainerView
                    .zIndex(0)
            }

            // Overlay other views on top with appropriate transitions
            Group {
                switch navigationCoordinator.currentView {
                case .practiceDetail:
                    if navigationCoordinator.deepLinkedAudioFile != nil {
                        // We now handle this with the sheet presentation
                        EmptyView()
                    }
                case .player(let audioFile, _, let initialDownloadingState):
                    // For backward compatibility, show the player view when navigated to directly
                    PlayerScreenView(
                        audioPlayerManager: audioPlayerManager,
                        selectedFile: audioFile,
                        durationIndex: .constant(0)
                    )
                    .environmentObject(navigationCoordinator)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
                    .background(Color.black.edgesIgnoringSafeArea(.all))
                    .onAppear {
                        isDownloading = initialDownloadingState
                        audioPlayerManager.preloadAudioFile(file: audioFile, durationIndex: 0) {
                            DispatchQueue.main.async {
                                isDownloading = false
                            }
                        }
                    }
                case .timerCountdown(let totalMinutes, let backgroundSound, let cueSettings, let isDeepLinked):
                    PlayerScreenView(
                        audioPlayerManager: audioPlayerManager,
                        timerConfig: TimerSessionConfig(
                            minutes: totalMinutes,
                            backgroundSound: backgroundSound,
                            binauralBeat: navigationCoordinator.timerBinauralBeat,
                            cueSettings: cueSettings,
                            isDeepLinked: isDeepLinked
                        )
                    )
                    .environmentObject(navigationCoordinator)
                    .environmentObject(subscriptionManager)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
                    .background(Color.black.edgesIgnoringSafeArea(.all))
                case .aiChat:
                    // Legacy AI overlay - navigation now uses Sensei as main view
                    AIChatView()
                        .environmentObject(navigationCoordinator)
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                        .background(Color.black.edgesIgnoringSafeArea(.all))
                case .main:
                    EmptyView()
                case .guest:
                    // Handle guest mode - show main container
                    mainContainerView
                        .zIndex(0)
                default:
                    // Default to main container
                    mainContainerView
                        .zIndex(0)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: navigationCoordinator.currentView)
    }
    
    /// The main container view of the app (side menu navigation).
    private var mainContainerView: some View {
        MainContainerView()
            .environmentObject(audioPlayerManager)
            .environmentObject(navigationCoordinator)
            .environmentObject(subscriptionManager)
            .environmentObject(PracticeManager.shared)
            .environmentObject(appState)
            .preferredColorScheme(.dark)
            .onAppear {
                logger.eventMessage("ContentView: MainContainerView appeared")
                if appState.isGuest {
                    navigationCoordinator.isGuest = true
                }
            }
    }
    
    // MARK: - Unified Player Sheet Content
    
    /// Content for the unified player sheet - handles both guided and timer sessions
    @ViewBuilder
    private var unifiedPlayerSheetContent: some View {
        switch navigationCoordinator.playerSessionType {
        case .guided:
            // Guided (MP3) session
            if let audioFile = navigationCoordinator.playerAudioFile {
                PlayerScreenView(
                    audioPlayerManager: audioPlayerManager,
                    selectedFile: audioFile,
                    durationIndex: .constant(navigationCoordinator.playerDurationIndex)
                )
                .environmentObject(navigationCoordinator)
                .environmentObject(subscriptionManager)
                .onAppear {
                    audioPlayerManager.selectedFile = audioFile
                    audioPlayerManager.preloadAudioFile(file: audioFile, durationIndex: navigationCoordinator.playerDurationIndex) {
                        DispatchQueue.main.async {
                            navigationCoordinator.playerIsDownloading = false
                        }
                    }
                }
            }
            
        case .timer:
            // Timer session via unified player
            if let timerConfig = navigationCoordinator.timerConfig {
                PlayerScreenView(
                    audioPlayerManager: audioPlayerManager,
                    timerConfig: timerConfig
                )
                .environmentObject(navigationCoordinator)
                .environmentObject(subscriptionManager)
            }
        }
    }
}
