//
//  SubscriptionContainerView.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Container view for the subscription flow.
//  Uses OnboardingFlowContainer for fixed header/footer positioning.
//
//  ARCHITECTURE:
//  - Container provides: Background config, Header config, Footer config, screen content
//  - OnboardingFlowContainer handles: Fixed positioning of all zones + fade overlay
//  - Individual screens provide: Content only (no header, no footer)
//

import SwiftUI

struct SubscriptionContainerView: View {
    
    @StateObject private var viewModel = SubscriptionViewModel()
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var appState: AppState
    
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
            print("💳 SUBSCRIPTION_CONTAINER: ═══════════════════════════════════════")
            print("💳 SUBSCRIPTION_CONTAINER: View appeared")
            print("💳 SUBSCRIPTION_CONTAINER: ═══════════════════════════════════════")
            viewModel.onFlowStart()
        }
        .onReceive(NotificationCenter.default.publisher(for: .subscriptionCompleted)) { notification in
            let subscribed = notification.userInfo?["subscribed"] as? Bool ?? false
            print("💳 SUBSCRIPTION_CONTAINER: Received completion notification (subscribed=\(subscribed))")
            enterMainApp(subscribed: subscribed)
        }
    }
    
    // MARK: - Background Configuration
    
    private var backgroundConfig: OnboardingBackgroundConfig {
        switch viewModel.currentStep {
        case .freeTrial:
            return .init(imageName: "SubscriptionTrial")
        case .choosePlan:
            return .init(imageName: "SubscriptionPlans")
        }
    }
    
    // MARK: - Fade Configuration
    
    /// Fade overlay coverage per screen (0-1, where 0.65 = bottom 65% of screen)
    private var fadeConfig: PurpleFadeConfig {
        switch viewModel.currentStep {
        case .freeTrial:
            return .init(coverage: 0.65)   // Extended coverage for subscription content
        case .choosePlan:
            return .init(coverage: 0.65)   // Extended coverage for plan cards
        }
    }
    
    // MARK: - Header Configuration
    
    private var headerConfig: OnboardingFlowHeaderConfig {
        .init(
            actionButton: headerActionButton,
            showsProgressBar: false,
            progress: 0,
            title: viewModel.currentStep.title,
            subtitle: nil
        )
    }
    
    /// Determines the action button type for the current step
    private var headerActionButton: OnboardingUnifiedHeader.ActionButton {
        switch viewModel.currentStep {
        case .freeTrial:
            return .close(action: { viewModel.skipSubscription() })
            
        case .choosePlan:
            return .backAndClose(
                back: { viewModel.goBackToFreeTrial() },
                close: { viewModel.skipSubscription() }
            )
        }
    }
    
    // MARK: - Footer Configuration
    
    private var footerConfig: OnboardingFlowFooterConfig? {
        switch viewModel.currentStep {
        case .freeTrial:
            return .init(
                primaryButton: .init(
                    text: "Start Your 7-Day Trial",
                    isLoading: viewModel.isProcessingPurchase,
                    action: { viewModel.startFreeTrial() }
                ),
                secondaryAction: .init(
                    text: "View all plans",
                    action: { viewModel.showAllPlans() }
                )
            )
            
        case .choosePlan:
            let isAnnualSelected = viewModel.selectedPackage?.identifier == viewModel.annualPackage?.identifier
            let buttonText = isAnnualSelected ? "Start Your 7-Day Trial" : "Subscribe Now"
            
            return .init(
                primaryButton: .init(
                    text: buttonText,
                    isEnabled: viewModel.selectedPackage != nil,
                    isLoading: viewModel.isProcessingPurchase,
                    action: {
                        if let package = viewModel.selectedPackage {
                            viewModel.purchasePackage(package)
                        }
                    }
                ),
                secondaryAction: .init(
                    text: "Restore purchases",
                    action: { viewModel.restorePurchases() }
                )
            )
        }
    }
    
    // MARK: - Screen Content
    
    @ViewBuilder
    private var screenContent: some View {
        Group {
            switch viewModel.currentStep {
            case .freeTrial:
                FreeTrialScreen(viewModel: viewModel)
                
            case .choosePlan:
                ChoosePlanScreen(viewModel: viewModel)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
    }
    
    // MARK: - Navigation
    
    /// Detects if this view was triggered from in-app (navigation-based) vs post-onboarding (state-based)
    private var isInAppTrigger: Bool {
        navigationCoordinator.currentView == .subscription
    }
    
    private func enterMainApp(subscribed: Bool) {
        print("💳 SUBSCRIPTION_CONTAINER: ═══════════════════════════════════════")
        print("💳 SUBSCRIPTION_CONTAINER: Entering main app")
        print("💳 SUBSCRIPTION_CONTAINER: subscribed=\(subscribed), isInAppTrigger=\(isInAppTrigger)")
        
        if isInAppTrigger {
            // In-app trigger: return to main view
            let source = navigationCoordinator.subscriptionSource
            // If user dismissed without subscribing, clear pending meditation to prevent
            // handleOnAppear from auto-playing and re-triggering the gate (endless loop)
            if !subscribed && (source == .aiFirstMeditationPlay || source == .aiMeditationRequest) {
                navigationCoordinator.pendingAIMeditation = nil
            }
            navigationCoordinator.currentView = .main
            
            // Handle contextual resume (AI chat, etc.)
            if source == .aiFirstMeditationPlay || source == .aiMeditationRequest {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: NSNotification.Name("SelectTab"), object: 0)
                }
            }
            navigationCoordinator.subscriptionSource = .unknown
            
            print("💳 SUBSCRIPTION_CONTAINER: In-app trigger - returned to main, source=\(source.rawValue)")
        } else {
            // Post-onboarding: mark complete and enter app
            appState.isAuthenticated = true
            navigationCoordinator.currentView = .main
            
            print("💳 SUBSCRIPTION_CONTAINER: Post-onboarding - Navigation set to .main")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: NSNotification.Name("SelectTab"), object: 0)
            }
        }
        
        print("💳 SUBSCRIPTION_CONTAINER: ═══════════════════════════════════════")
    }
}

// MARK: - Preview

#if DEBUG
struct SubscriptionContainerView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionContainerView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(AppState())
            .preferredColorScheme(.dark)
    }
}
#endif
