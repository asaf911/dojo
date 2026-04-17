//
//  MainContainerView.swift
//  imagine
//
//  Created for Side Menu Navigation Migration
//  Replaces DojoTabView as the main authenticated view container
//

import SwiftUI

struct MainContainerView: View {
    @State private var selectedMenuItem: MenuItem = .sensei  // Default to Sensei
    @State private var isMenuOpen: Bool = false
    @State private var hasTriggeredAIOnboarding = false
    
    /// Keyboard controller for centralized keyboard state management
    @ObservedObject private var keyboardController = ChatKeyboardController.shared
    
    // Gesture tracking for edge swipe
    @State private var dragOffset: CGFloat = 0
    private let edgeSwipeThreshold: CGFloat = 20 // Distance from left edge to trigger
    private let menuOpenThreshold: CGFloat = 100 // Minimum drag distance to open menu
    
    // Publishers for external navigation
    private let menuSelectionPublisher = NotificationCenter.default.publisher(
        for: NSNotification.Name("SelectTab")
    )
    private let switchMenuPublisher = NotificationCenter.default.publisher(
        for: NSNotification.Name("SwitchToTab")
    )
    
    @StateObject private var authViewModel = AuthViewModel()
    private let aiOnboardingCoordinator = SenseiOnboardingCoordinator.shared
    
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var audioPlayerManager: AudioPlayerManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var appState: AppState
    
    // Bindings for views that need them
    @State private var showCommunitySheet = false
    @State private var communitySheetSource: String? = "Learn"
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Active content view
                contentView
                    .environment(\.toggleMenu, toggleMenu)
                
                // Side menu overlay
                SideMenuView(
                    isOpen: $isMenuOpen,
                    selectedItem: $selectedMenuItem,
                    onDismissWithoutSelection: {
                        // Release menu suppression and restore keyboard if it was expanded before
                        keyboardController.releaseMenuSuppression(restore: true)
                    }
                )
            }
            // Edge swipe gesture to open menu
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        // Only respond to swipes starting from left edge (20pt)
                        if !isMenuOpen && value.startLocation.x < edgeSwipeThreshold {
                            dragOffset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        // Open menu if dragged far enough from left edge
                        if !isMenuOpen && value.startLocation.x < edgeSwipeThreshold {
                            if value.translation.width > menuOpenThreshold {
                                // Suppress keyboard for menu (tracks if it was expanded)
                                keyboardController.suppressForMenu()
                                
                                // Dismiss keyboard via system
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                
                                withAnimation(.easeOut(duration: 0.25)) {
                                    isMenuOpen = true
                                }
                            }
                        }
                        dragOffset = 0
                    }
            )
        }
        .onReceive(menuSelectionPublisher) { notification in
            if let menuIndex = notification.object as? Int,
               let menuItem = MenuItem(rawValue: menuIndex) {
                logger.eventMessage("MainContainerView: Setting selectedMenuItem to \(menuItem.title) via notification")
                selectedMenuItem = menuItem
                isMenuOpen = false
            }
        }
        .onReceive(switchMenuPublisher) { notification in
            if let userInfo = notification.userInfo,
               let menuIndex = userInfo["tabIndex"] as? Int,
               let menuItem = MenuItem(rawValue: menuIndex) {
                logger.eventMessage("MainContainerView: Switching to \(menuItem.title)")
                selectedMenuItem = menuItem
                isMenuOpen = false
            }
        }
        .task {
            guard !hasTriggeredAIOnboarding else { return }
            aiOnboardingCoordinator.launchIfNeeded(origin: "main_container") {
                hasTriggeredAIOnboarding = true
                // AI onboarding now happens in-place since Sensei is default view
            }
        }
        .onAppear {
            // Trigger ATT flow for users who skip AuthenticationScreen (already authenticated)
            if UserIdentityManager.shared.isIdentityReady {
                print("📊 TRACKING: [ATT] MainContainerView is ready - triggering ATT flow")
                DojoApp.triggerATTFlowIfNeeded()
            }
            
            // Store current menu item for analytics
            navigationCoordinator.sourceTab = selectedMenuItem.rawValue
            navigationCoordinator.sourceTabName = selectedMenuItem.title
        }
        .onChange(of: selectedMenuItem) { _, newValue in
            // Update navigation coordinator with current selection
            navigationCoordinator.sourceTab = newValue.rawValue
            navigationCoordinator.sourceTabName = newValue.title
        }
    }
    
    // MARK: - Content View Switch
    
    @ViewBuilder
    private var contentView: some View {
        Group {
            switch selectedMenuItem {
            case .sensei:
                AIChatView()
                
            case .explore:
                ExploreView(
                    showCommunitySheet: $showCommunitySheet,
                    source: $communitySheetSource
                )
                
            case .path:
                PathView(
                    showCommunitySheet: $showCommunitySheet,
                    source: $communitySheetSource
                )
                
            case .timer:
                CreateView()
                
            case .history:
                HistoryContainerView()
                
            case .insights:
                InsightsView()
                
            case .settings:
                SettingsContainerView(authViewModel: authViewModel)
            }
        }
        .environmentObject(authViewModel)
        .environmentObject(navigationCoordinator)
        .environmentObject(subscriptionManager)
        .environmentObject(audioPlayerManager)
        .environmentObject(PracticeManager.shared)
    }
    
    // MARK: - Menu Toggle
    
    private func toggleMenu() {
        if !isMenuOpen {
            // Opening menu - suppress keyboard (tracks if it was expanded)
            keyboardController.suppressForMenu()
            
            // Dismiss keyboard via system
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        } else {
            // Closing menu via toggle (hamburger button) - don't restore focus
            keyboardController.releaseMenuSuppression(restore: false)
        }
        
        withAnimation(.easeOut(duration: 0.25)) {
            isMenuOpen.toggle()
        }
    }
}

// MARK: - History Container View (Standalone wrapper)

struct HistoryContainerView: View {
    @Environment(\.toggleMenu) private var toggleMenu
    
    var body: some View {
        DojoScreenContainer(
            headerTitle: "History",
            headerSubtitle: nil,
            backgroundImageName: "HistoryBackground",
            backAction: nil,
            showBackButton: false,
            menuAction: toggleMenu,
            showMenuButton: true
        ) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 5)
                    HistoryView()
                        .padding(.horizontal, 16)
                    Spacer().frame(height: 100)
                }
            }
            .topFadeMask(height: 5)
        }
    }
}

// MARK: - Settings Container View (Standalone wrapper)

struct SettingsContainerView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.toggleMenu) private var toggleMenu
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        DojoScreenContainer(
            headerTitle: "Settings",
            headerSubtitle: nil,
            backgroundImageName: nil,
            backAction: nil,
            showBackButton: false,
            menuAction: toggleMenu,
            showMenuButton: true
        ) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 5)
                    SettingsView(authViewModel: authViewModel, showTitle: false)
                        .environmentObject(navigationCoordinator)
                        .environmentObject(appState)
                }
            }
            .topFadeMask(height: 5)
        }
        .background(Color.backgroundNavy)
    }
}

#if DEBUG
#Preview {
    MainContainerView()
        .environmentObject(NavigationCoordinator())
        .environmentObject(AudioPlayerManager())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(AppState())
        .environmentObject(GlobalErrorManager.shared)
}
#endif

