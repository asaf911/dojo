//
//  DojoApp.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-04-08
//

import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseStorage
import FirebaseAnalytics
import GoogleSignIn
import AuthenticationServices
import Mixpanel
import RevenueCat
import UserNotifications
import HealthKit
@main
struct DojoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var authViewModel = AuthViewModel()
    @StateObject var audioPlayerManager = AudioPlayerManager()
    @StateObject var navigationCoordinator = NavigationCoordinator()
    @StateObject var subscriptionManager = SubscriptionManager.shared
    @StateObject var timerManager = MeditationSessionTimer(totalSeconds: 600)
    @StateObject var appState = AppState()
    
    // GlobalErrorManager is injected here and observed at the top level.
    @StateObject var globalErrorManager = GlobalErrorManager.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Firebase is already configured in AppDelegate - don't configure it again
        
        // Start network connectivity monitoring for offline mode support
        NetworkMonitor.shared.start()
        
        // Audio session is no longer configured globally at launch.
        // .playback is set on-demand when a meditation session starts.
        // GeneralBackgroundMusicController uses .ambient for lobby music.
        
        print("📊 TRACKING: [INIT] DojoApp initialization complete")
        print("[Server][Config] Active server: \(Config.serverLabel)")
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    // Settings sheet modifier removed - settings is now a main view in the side menu
                    // MARK: - Protocol-based Service Injection (DI Foundation)
                    .environment(\.analyticsService, AnalyticsManager.shared)
                    .environment(\.subscriptionService, SubscriptionManager.shared)
                    .environment(\.authService, AuthService.shared)
                    .environment(\.dataService, FirestoreManager.shared)
                    .environment(\.healthService, HealthKitManager.shared)
                    .environment(\.statsService, StatsManager.shared)
                    // MARK: - Legacy EnvironmentObject Injection (for backward compatibility)
                    .environmentObject(navigationCoordinator)
                    .environmentObject(subscriptionManager)
                    .environmentObject(timerManager)
                    .environmentObject(audioPlayerManager)
                    .environmentObject(appState)
                    .environmentObject(GlobalErrorManager.shared) // Inject global error manager
                    .onFirstAppear {
                        print("DojoApp: onFirstAppear called")
                        print("[Server][Config] Active server: \(Config.serverLabel)")
                        // Set the shared NavigationCoordinator instance
                        NavigationCoordinator.shared = navigationCoordinator
                        // Set the shared AudioPlayerManager instance
                        AudioPlayerManager.shared = audioPlayerManager
                                // Set the shared MeditationSessionTimer instance
        MeditationSessionTimer.shared = timerManager
                        
                        // Initialize WatchAnalyticsManager to start tracking
                        _ = WatchAnalyticsManager.shared
                        
                        // Provide references to AppDelegate.
                        delegate.navigationCoordinator = navigationCoordinator
                        delegate.audioPlayerManager = audioPlayerManager
                        delegate.timerManager = timerManager
                        
                        // Register audio players with the central lifecycle controller.
                        AppAudioLifecycleController.shared.registerBackgroundMusic(GeneralBackgroundMusicController.shared)
                        AppAudioLifecycleController.shared.registerGuidedPlayer(audioPlayerManager)
                        
                        // Initialize app navigation and features
                        initializeApp()
                        
                        
                        // Now that AppDelegate has finished initialization with Mixpanel,
                        // we can safely configure our identity services
                        DispatchQueue.main.async {
                            print("📊 TRACKING: [INIT] UserIdentityManager configured in AppDelegate")
                            
                            // Configure UserIdentityManager with AppState reference for onboarding refresh
                            UserIdentityManager.shared.setAppState(self.appState)
                            
                            // Install/Reinstall tracking is handled by AppsFlyer
                            print("📊 TRACKING: [INIT] Install/Reinstall tracking delegated to AppsFlyer")
                        }
                        
                        // Continue with other initializations
                        handleAppVersionCheck()
                        updateAudioFiles()
                        // Note: HealthKit authorization is handled explicitly by user action:
                        // - During onboarding: HealthScreen "Connect Apple Health" button
                        // - After onboarding: Settings > Health Integration > "Connect Apple Health"
                        // We no longer auto-prompt at app launch to avoid premature permission requests.
                        
                        // 🚀 ENHANCED BODY SCAN SYSTEM ACTIVATED (STANDALONE MODE)
                        logger.eventMessage("🎯 MODEL_SYSTEM: Enhanced body scan AI system is ACTIVE")
                        logger.eventMessage("✨ MODEL_SYSTEM: V4 logic with smart session analysis enabled")
                    }
                    .onOpenURL { url in
                        if let nav = delegate.navigationCoordinator {
                            DeepLinkHandler.handleIncomingURL(
                                url,
                                source: "universalLink",
                                navigationCoordinator: nav
                            )
                        } else {
                            print("DojoApp: ERROR - navigationCoordinator is nil")
                        }
                    }
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        if newPhase == .active {
                            print("📊 TRACKING: [LIFECYCLE] ScenePhase became .active")
                            
                            // Sync session history from Firebase (smart sync - only downloads if needed)
                            SessionFirebaseSync.shared.smartSync()
                            
                            // Note: AppsFlyer session tracking is handled by AppsFlyerManager.handleAppForeground()
                            // which is called from AppDelegate.applicationDidBecomeActive
                            
                            if let pendingURL = delegate.pendingPushNotificationURL {
                                print("DojoApp: Handling pending Push Notification URL: \(pendingURL.absoluteString)")
                                delegate.handleDeepLink(pendingURL)
                                delegate.pendingPushNotificationURL = nil
                            }
                            if let storedLink = SharedUserStorage.retrieve(forKey: .pendingPushNotificationLink, as: String.self),
                               let storedURL = URL(string: storedLink) {
                                print("DojoApp: Handling stored pendingPushNotificationLink: \(storedLink)")
                                delegate.handleDeepLink(storedURL)
                                SharedUserStorage.delete(forKey: .pendingPushNotificationLink)
                            }
                            StatsManager.shared.resetStreakIfNeededOnAppLaunch()
                            // Audio session reactivation and silent audio are handled
                            // by AppAudioLifecycleController's foreground observer.
                        }
                    }
            }
            // Attach the native global error alert at the root.
            .alert(item: $globalErrorManager.error) { error in
                print("DojoApp: Presenting native alert for error: \(error.localizedDescription)")
                return Alert(
                    title: Text("Error"),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text("OK"), action: {
                        print("DojoApp: Dismissing native error alert")
                        GlobalErrorManager.shared.error = nil
                    })
                )
            }
        }
    }
    
    private func initializeApp() {
        // CRITICAL FIX: Check APP authentication state first, not Firebase user existence
        // Firebase users can exist without completing the app's authentication flow
        let isAppAuthenticated = SharedUserStorage.retrieve(forKey: .isAuthenticated, as: Bool.self) ?? false
        let isGuest = SharedUserStorage.retrieve(forKey: .isGuest, as: Bool.self) ?? false
        
        print("DojoApp: App authentication state - isAuthenticated: \(isAppAuthenticated), isGuest: \(isGuest)")
        
        if isAppAuthenticated {
            print("DojoApp: User is authenticated according to app state")
            
            // Verify Firebase user still exists and is valid
            if let currentUser = Auth.auth().currentUser {
                print("DojoApp: Found Firebase user: \(currentUser.uid)")
                
                if currentUser.isAnonymous && !isGuest {
                    print("DojoApp: ⚠️ Inconsistent state: App shows authenticated but Firebase user is anonymous")
                    print("DojoApp: Resetting to unauthenticated state - will show AuthenticationScreen")
                    resetToUnauthenticatedState()
                    return
                }
                
                // Set up authenticated user state
                appState.setAuthenticated(isGuest: isGuest)
                print("DojoApp: User is authenticated. Presenting main experience.")

                if navigationCoordinator.currentView != .practiceDetail &&
                    navigationCoordinator.currentView != .timer {
                    navigationCoordinator.currentView = .main
                }

                // Migrate stats to Firebase if needed (one-time), then sync from Firebase
                StatsManager.shared.migrateAndSyncStats { success in
                    print("DojoApp: migrateAndSyncStats completed with success: \(success)")
                }
            } else {
                print("DojoApp: ⚠️ App shows authenticated but no Firebase user found")
                print("DojoApp: Resetting to unauthenticated state - will show AuthenticationScreen")
                resetToUnauthenticatedState()
            }
        } else {
            print("DojoApp: User is NOT authenticated according to app state")
            
            // Check if Firebase user exists (for tracking purposes)
            if let currentUser = Auth.auth().currentUser {
                print("DojoApp: Found Firebase user: \(currentUser.uid) (for tracking only)")
                if currentUser.isAnonymous {
                    print("DojoApp: Firebase user is anonymous (created for tracking) - showing AuthenticationScreen")
                } else {
                    print("DojoApp: Firebase user exists but app is not authenticated - showing AuthenticationScreen")
                    print("DojoApp: This handles cases where user started but didn't complete authentication flow")
                }
            } else {
                print("DojoApp: No Firebase user found - showing AuthenticationScreen")
            }
            
            // Ensure unauthenticated state
            resetToUnauthenticatedState()
        }
    }
    
    private func resetToUnauthenticatedState() {
        print("DojoApp: Setting unauthenticated state - will show AuthenticationScreen")
        appState.isAuthenticated = false
        appState.isGuest = false
        appState.needsOnboarding = false
        SharedUserStorage.save(value: false, forKey: .isAuthenticated)
        SharedUserStorage.save(value: false, forKey: .isGuest)
        // navigationCoordinator.currentView already defaults to .signUp
    }
    
    /// Trigger ATT flow when identity is ready and first view is loaded
    /// Called by AuthenticationScreen or DojoTabView when they're ready
    static func triggerATTFlowIfNeeded() {
        // Only trigger if identity is ready
        guard UserIdentityManager.shared.isIdentityReady else {
            print("📊 TRACKING: [ATT] Identity not ready yet, deferring ATT trigger")
            return
        }
        
        // Check if ATT prompt is needed
        if AppsFlyerManager.shared.needsATTPrompt {
            print("📊 TRACKING: [ATT] ATT prompt needed - requesting authorization")
            AppsFlyerManager.shared.requestATTAuthorization { status in
                print("📊 TRACKING: [ATT] ATT flow completed with status: \(status)")
            }
        } else {
            print("📊 TRACKING: [ATT] ATT already resolved - starting AppsFlyer")
            // ATT already resolved, just ensure AppsFlyer is started
            AppsFlyerManager.shared.handleAppForeground()
        }
    }
    
    private func updateAudioFiles() {
        AppFunctions.loadAudioFiles { audioFiles in
            DispatchQueue.main.async {
                if audioPlayerManager.selectedFile == nil, let first = audioFiles.first {
                    audioPlayerManager.selectedFile = first
                    print("DojoApp: Selected file set to first audioFile: \(first.title)")
                } else {
                    print("DojoApp: Skipping setting selectedFile because it's already set or audioFiles is empty.")
                }
            }
        }
    }
    
    private func handleAppVersionCheck() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let storedVersion = SharedUserStorage.retrieve(forKey: .appVersion, as: String.self)
        if storedVersion != currentVersion {
            print("DojoApp: App updated from version \(storedVersion ?? "none") to \(currentVersion ?? "unknown")")
            SharedUserStorage.save(value: currentVersion, forKey: .appVersion)
        }
    }
    
    // MARK: - HealthKit Authorization
    // 
    // HealthKit authorization is now handled ONLY by explicit user action:
    // 1. During onboarding: HealthScreen "Connect Apple Health" button
    // 2. After onboarding: Settings > Health Integration > "Connect Apple Health"
    //
    // This ensures users are prompted at the appropriate moment (when they understand 
    // the context) rather than at app launch, which led to poor UX and lower consent rates.
    
    // MARK: - Debug Functions for Testing
    
    /// Debug function to reset first_open tracking for testing purposes
    /// NOTE: This is no longer needed since we use AppsFlyer for install detection
    /// Call this temporarily to test the first_open event on your test device
    private func resetFirstOpenForTesting() {
        #if DEBUG
        print("📊 TRACKING: [DEBUG] resetFirstOpenForTesting called")
        print("📊 TRACKING: [DEBUG] To test install events: uninstall app and reinstall")
        #endif
    }
}
