//
//  OnboardingContainerView.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Container view for the onboarding flow.
//  Uses OnboardingFlowContainer for fixed header/footer positioning.
//
//  ARCHITECTURE:
//  - Container provides: Background config, Header config, Footer config, screen content
//  - OnboardingFlowContainer handles: Fixed positioning of all zones + fade overlay
//  - Individual screens provide: Content only (no header, no footer)
//

import SwiftUI

struct OnboardingContainerView: View {
    
    @StateObject private var viewModel: OnboardingViewModel
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var appState: AppState
    
    // MARK: - Alert State
    
    @State private var showMindfulMinutesAlreadyConnectedAlert = false
    @State private var showHeartRateEnabledAlert = false
    
    // MARK: - Initialization
    
    init(configuration: OnboardingConfiguration = .default) {
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(configuration: configuration))
    }
    
    // MARK: - Body
    
    var body: some View {
        OnboardingFlowContainer(
            backgroundConfig: backgroundConfig,
            headerConfig: headerConfig,
            footerConfig: footerConfig,
            fadeConfig: fadeConfig
        ) {
            screenContent
        }
        .onAppear {
            print("🚀 ONBOARDING_CONTAINER: ═══════════════════════════════════════")
            print("🚀 ONBOARDING_CONTAINER: View appeared")
            print("🚀 ONBOARDING_CONTAINER: ═══════════════════════════════════════")
            viewModel.onFlowStart()
            
            // Ensure AppsFlyer SDK is running for attribution (no ATT prompt here).
            // ATT is requested exclusively from AuthenticationScreen on first launch.
            if UserIdentityManager.shared.isIdentityReady {
                AppsFlyerManager.shared.handleAppForeground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
            print("🚀 ONBOARDING_CONTAINER: Received completion notification")
            transitionToSubscription()
        }
        .alert("You're All Set", isPresented: $showMindfulMinutesAlreadyConnectedAlert) {
            Button("OK") {
                viewModel.advance()
            }
        } message: {
            Text("Mindful Minutes is ready to sync your practice.")
        }
        .alert("Heart Rate Enabled", isPresented: $showHeartRateEnabledAlert) {
            Button("Continue") {
                viewModel.advance()
            }
        } message: {
            Text("Heart rate will be used when available.")
        }
    }
    
    // MARK: - Background Configuration
    
    private var backgroundConfig: OnboardingBackgroundConfig {
        switch viewModel.currentStep {
        case .welcome:
            return .init(imageName: "OnboardingWelcome")
        case .sensei:
            return .init(imageName: "OnboardingSensei")
        case .goals:
            return .init(imageName: "OnboardingGoals")
        case .goalsAcknowledgment:
            return .init(imageName: "OnboardingHurdle")  // Same background as Hurdle screen
        case .hurdle:
            return .init(imageName: "OnboardingHurdle")
        case .hurdleAcknowledgment:
            return .init(imageName: "OnboardingHealth")  // Same background as Health screen
        case .healthMindfulMinutes:
            return .init(imageName: "OnboardingHealth")
        case .healthHeartRate:
            return .init(imageName: "OnboardingHealth")
        case .building:
            return .init(imageName: "OnboardingBuilding")
        case .ready:
            return .init(imageName: "OnboardingReady")
        }
    }
    
    // MARK: - Fade Configuration
    
    /// Fade overlay coverage per screen (0-1, where 0.6 = bottom 60% of screen)
    private var fadeConfig: PurpleFadeConfig {
        switch viewModel.currentStep {
        case .welcome:
            return .init(coverage: 0.55)   // Less coverage for splash imagery
        case .sensei:
            return .init(coverage: 0.70)   // 70% coverage for sensei
        case .goals:
            return .init(coverage: 0.70)   // 70% coverage for card content
        case .goalsAcknowledgment:
            return .init(coverage: 0.75)   // 75% coverage matching hurdle
        case .hurdle:
            return .init(coverage: 0.75)   // 75% coverage for card content
        case .hurdleAcknowledgment:
            return .init(coverage: 0.60)   // 60% coverage matching health
        case .healthMindfulMinutes:
            return .init(coverage: 0.60)   // Standard coverage for Mindful Minutes
        case .healthHeartRate:
            return .init(coverage: 0.60)   // Standard coverage for Heart Rate
        case .building:
            return .init(coverage: 0.50)   // Less fade during animation
        case .ready:
            return .init(coverage: 0.65)   // More coverage for final screen
        }
    }
    
    // MARK: - Header Configuration
    
    private var headerConfig: OnboardingFlowHeaderConfig {
        .init(
            actionButton: .mute,
            showsProgressBar: viewModel.currentStep.showsProgressBar,
            progress: viewModel.progress,
            title: headerTitle,
            subtitle: headerSubtitle
        )
    }
    
    /// Dynamically resolved title for the unified header
    /// GoalsAcknowledgmentScreen, HurdleScreen, and HurdleAcknowledgmentScreen have dynamic titles
    private var headerTitle: String? {
        guard viewModel.currentStep.showsTitleInHeader else { return nil }
        
        switch viewModel.currentStep {
        case .goalsAcknowledgment:
            // GoalsAcknowledgmentScreen title depends on selected goal
            return viewModel.responses.selectedGoal?.acknowledgmentContent.title ?? OnboardingStep.goalsAcknowledgment.title
        case .hurdle:
            // HurdleScreen title depends on selected goal
            return viewModel.responses.selectedGoal?.hurdleScreenContent.title ?? OnboardingStep.hurdle.title
        case .hurdleAcknowledgment:
            // HurdleAcknowledgmentScreen title depends on selected hurdle
            return viewModel.responses.selectedHurdle?.acknowledgmentContent.title ?? OnboardingStep.hurdleAcknowledgment.title
        default:
            return viewModel.currentStep.title
        }
    }
    
    /// Dynamically resolved subtitle for the unified header
    private var headerSubtitle: String? {
        guard viewModel.currentStep.showsTitleInHeader else { return nil }
        
        // Acknowledgment screens don't show subtitle in header (it's in the content area)
        switch viewModel.currentStep {
        case .goalsAcknowledgment, .hurdle, .hurdleAcknowledgment:
            return nil
        default:
            return viewModel.currentStep.subtitle
        }
    }
    
    // MARK: - Footer Configuration
    
    private var footerConfig: OnboardingFlowFooterConfig? {
        switch viewModel.currentStep {
        case .welcome:
            // No footer - button is inline in WelcomeScreen
            return nil
            
        case .sensei:
            // No footer - auto-advances on selection
            return nil
            
        case .goals:
            return .init(
                primaryText: viewModel.configuration.ctaText(for: .goals),
                isEnabled: viewModel.responses.selectedGoal != nil,
                action: { viewModel.advance() }
            )
            
        case .goalsAcknowledgment:
            let ctaText = viewModel.responses.selectedGoal?.acknowledgmentContent.ctaText ?? "Continue"
            return .init(
                primaryText: ctaText,
                isEnabled: true,
                action: { viewModel.advance() }
            )
            
        case .hurdle:
            let ctaText = viewModel.responses.selectedGoal?.hurdleScreenContent.ctaText ?? "Continue"
            return .init(
                primaryText: ctaText,
                isEnabled: viewModel.responses.selectedHurdle != nil,
                action: { viewModel.advance() }
            )
            
        case .hurdleAcknowledgment:
            let ctaText = viewModel.responses.selectedHurdle?.acknowledgmentContent.ctaText ?? "Continue"
            return .init(
                primaryText: ctaText,
                isEnabled: true,
                action: { viewModel.advance() }
            )
            
        case .healthMindfulMinutes:
            return .init(
                primaryButton: .init(
                    text: viewModel.configuration.ctaText(for: .healthMindfulMinutes),
                    isLoading: viewModel.isConnectingMindfulMinutes,
                    action: { connectMindfulMinutes() }
                ),
                secondaryAction: .init(
                    text: "Skip for now",
                    action: {
                        viewModel.markMindfulMinutesConnected(false, result: "skipped")
                        viewModel.advance()
                    }
                )
            )
            
        case .healthHeartRate:
            return .init(
                primaryButton: .init(
                    text: viewModel.configuration.ctaText(for: .healthHeartRate),
                    isLoading: viewModel.isConnectingHeartRate,
                    action: { enableHeartRate() }
                ),
                secondaryAction: .init(
                    text: "Skip for now",
                    action: {
                        viewModel.markHeartRateEnabled(result: "skipped")
                        viewModel.advance()
                    }
                )
            )
            
        case .building:
            // No footer - auto-advances after animation
            return nil
            
        case .ready:
            return .init(
                primaryText: "Begin your practice",
                action: { viewModel.advance() }
            )
        }
    }
    
    // MARK: - Mindful Minutes Connection
    
    private func connectMindfulMinutes() {
        // Check if already authorized
        let currentStatus = HealthKitManager.shared.getMindfulMinutesAuthorizationStatus()
        if currentStatus == .sharingAuthorized {
            viewModel.markMindfulMinutesConnected(true, result: "already_authorized")
            showMindfulMinutesAlreadyConnectedAlert = true
            return
        }
        
        viewModel.isConnectingMindfulMinutes = true
        
        HealthKitManager.shared.requestMindfulMinutesAuthorization { success, error in
            DispatchQueue.main.async {
                viewModel.isConnectingMindfulMinutes = false
                
                // Check actual authorization status (works for write permissions)
                let status = HealthKitManager.shared.getMindfulMinutesAuthorizationStatus()
                let actuallyAuthorized = (status == .sharingAuthorized)
                
                let result = actuallyAuthorized ? "authorized" : "denied"
                viewModel.markMindfulMinutesConnected(actuallyAuthorized, result: result)
                
                // Only advance if user actually granted permission
                if actuallyAuthorized {
                    viewModel.advance()
                }
                // Otherwise stay on screen - user can tap again or use "Skip for now"
            }
        }
    }
    
    // MARK: - Heart Rate Enable
    
    private func enableHeartRate() {
        viewModel.isConnectingHeartRate = true
        
        HealthKitManager.shared.requestHeartRateAuthorization { success, error in
            DispatchQueue.main.async {
                viewModel.isConnectingHeartRate = false
                
                // For heart rate (read permission), we cannot reliably check if granted
                // We always show soft confirmation and proceed
                viewModel.markHeartRateEnabled(result: "prompted")
                
                // Auto-enable HR monitoring for users who grant permission
                PhoneConnectivityManager.shared.updateHRFeatureEnabled(true)
                
                // Show soft confirmation alert then advance
                showHeartRateEnabledAlert = true
            }
        }
    }
    
    // MARK: - Screen Content
    
    @ViewBuilder
    private var screenContent: some View {
        Group {
            switch viewModel.currentStep {
            case .welcome:
                WelcomeScreen(viewModel: viewModel)
                
            case .sensei:
                SenseiScreen(viewModel: viewModel)
                
            case .goals:
                GoalsScreen(viewModel: viewModel)
                
            case .goalsAcknowledgment:
                GoalsAcknowledgmentScreen(viewModel: viewModel)
                
            case .hurdle:
                HurdleScreen(viewModel: viewModel)
                
            case .hurdleAcknowledgment:
                HurdleAcknowledgmentScreen(viewModel: viewModel)
                
            case .healthMindfulMinutes:
                MindfulMinutesScreen(viewModel: viewModel)
                
            case .healthHeartRate:
                HeartRateScreen(viewModel: viewModel)
                
            case .building:
                BuildingScreen(viewModel: viewModel)
                
            case .ready:
                ReadyScreen(viewModel: viewModel)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: viewModel.currentStep)
    }
    
    // MARK: - Navigation
    
    private func transitionToSubscription() {
        navigationCoordinator.currentView = .subscription
        
        #if DEBUG
        print("📋 ONBOARDING: Transitioning to subscription phase")
        #endif
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingContainerView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingContainerView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(AppState())
            .preferredColorScheme(.dark)
    }
}
#endif
