//
//  OnboardingPreviewContainer.swift
//  imagine
//
//  Created by Cursor on 1/16/26.
//
//  Reusable preview containers that use OnboardingFlowContainer
//  to ensure preview fidelity matches production exactly.
//

import SwiftUI

#if DEBUG

// MARK: - Onboarding Preview Container

/// Preview container for onboarding screens - uses OnboardingFlowContainer
struct OnboardingPreviewContainer<Content: View>: View {
    
    let step: OnboardingStep
    let content: Content
    let customFooterConfig: OnboardingFlowFooterConfig?
    let customTitle: String?
    let useDefaultFooter: Bool
    
    /// Standard initializer - uses default footer for the step (matches production)
    init(
        step: OnboardingStep,
        @ViewBuilder content: () -> Content
    ) {
        self.step = step
        self.customFooterConfig = nil
        self.customTitle = nil
        self.useDefaultFooter = true
        self.content = content()
    }
    
    /// Custom footer initializer - override the default footer
    init(
        step: OnboardingStep,
        footerConfig: OnboardingFlowFooterConfig?,
        @ViewBuilder content: () -> Content
    ) {
        self.step = step
        self.customFooterConfig = footerConfig
        self.customTitle = nil
        self.useDefaultFooter = false
        self.content = content()
    }
    
    /// Full customization initializer - override title and footer (useful for dynamic screens like Hurdle)
    init(
        step: OnboardingStep,
        customTitle: String?,
        footerConfig: OnboardingFlowFooterConfig?,
        @ViewBuilder content: () -> Content
    ) {
        self.step = step
        self.customFooterConfig = footerConfig
        self.customTitle = customTitle
        self.useDefaultFooter = false
        self.content = content()
    }
    
    var body: some View {
        OnboardingFlowContainer(
            backgroundConfig: backgroundConfig,
            headerConfig: headerConfig,
            footerConfig: useDefaultFooter ? defaultFooterConfig : customFooterConfig,
            fadeConfig: fadeConfig
        ) {
            content
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Fade Configuration (matches OnboardingContainerView)
    
    private var fadeConfig: PurpleFadeConfig {
        switch step {
        case .welcome:
            return .init(coverage: 0.55)
        case .sensei:
            return .init(coverage: 0.70)
        case .goals:
            return .init(coverage: 0.70)
        case .goalsAcknowledgment:
            return .init(coverage: 0.75)  // Matching hurdle
        case .hurdle:
            return .init(coverage: 0.75)
        case .hurdleAcknowledgment:
            return .init(coverage: 0.60)  // Matching health
        case .healthMindfulMinutes:
            return .init(coverage: 0.60)
        case .healthHeartRate:
            return .init(coverage: 0.60)
        case .building:
            return .init(coverage: 0.50)
        case .ready:
            return .init(coverage: 0.65)
        }
    }
    
    // MARK: - Background Configuration (matches OnboardingContainerView)
    
    private var backgroundConfig: OnboardingBackgroundConfig {
        switch step {
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
    
    // MARK: - Header Configuration
    
    private var headerConfig: OnboardingFlowHeaderConfig {
        .init(
            actionButton: .mute,
            showsProgressBar: step.showsProgressBar,
            progress: progress,
            title: step.showsTitleInHeader ? (customTitle ?? step.title) : nil,
            subtitle: step.showsTitleInHeader ? step.subtitle : nil
        )
    }
    
    private var progress: Double {
        guard step != .welcome else { return 0 }
        return Double(step.rawValue) / 9.0  // 10 steps total (0-9)
    }
    
    // MARK: - Footer Configuration (matches OnboardingContainerView)
    
    private var defaultFooterConfig: OnboardingFlowFooterConfig? {
        switch step {
        case .welcome:
            // No footer - button is inline in WelcomeScreen
            return nil
            
        case .sensei:
            // No footer - auto-advances on selection
            return nil
            
        case .goals:
            return .init(
                primaryText: "Set intention",
                isEnabled: true, // In preview, show enabled state
                action: {}
            )
            
        case .goalsAcknowledgment:
            return .init(
                primaryText: "Continue",
                isEnabled: true, // Always enabled - no input required
                action: {}
            )
            
        case .hurdle:
            return .init(
                primaryText: "Continue",
                isEnabled: true, // In preview, show enabled state
                action: {}
            )
            
        case .hurdleAcknowledgment:
            return .init(
                primaryText: "Continue",
                isEnabled: true, // Always enabled - no input required
                action: {}
            )
            
        case .healthMindfulMinutes:
            return .init(
                primaryButton: .init(
                    text: "Connect Apple Health",
                    action: {}
                ),
                secondaryAction: .init(
                    text: "Skip for now",
                    action: {}
                )
            )
            
        case .healthHeartRate:
            return .init(
                primaryButton: .init(
                    text: "Enable Heart Rate",
                    action: {}
                ),
                secondaryAction: .init(
                    text: "Skip for now",
                    action: {}
                )
            )
            
        case .building:
            // No footer - auto-advances after animation
            return nil
            
        case .ready:
            return .init(
                primaryText: "Begin your practice",
                action: {}
            )
        }
    }
}

// MARK: - Subscription Preview Container

/// Preview container for subscription screens - uses OnboardingFlowContainer
struct SubscriptionPreviewContainer<Content: View>: View {
    
    let step: SubscriptionStep
    let content: Content
    let customFooterConfig: OnboardingFlowFooterConfig?
    let useDefaultFooter: Bool
    
    /// Standard initializer - uses default footer for the step (matches production)
    init(
        step: SubscriptionStep,
        @ViewBuilder content: () -> Content
    ) {
        self.step = step
        self.customFooterConfig = nil
        self.useDefaultFooter = true
        self.content = content()
    }
    
    /// Custom footer initializer - override the default footer
    init(
        step: SubscriptionStep,
        footerConfig: OnboardingFlowFooterConfig?,
        @ViewBuilder content: () -> Content
    ) {
        self.step = step
        self.customFooterConfig = footerConfig
        self.useDefaultFooter = false
        self.content = content()
    }
    
    var body: some View {
        OnboardingFlowContainer(
            backgroundConfig: backgroundConfig,
            headerConfig: headerConfig,
            footerConfig: useDefaultFooter ? defaultFooterConfig : customFooterConfig,
            fadeConfig: fadeConfig
        ) {
            content
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Fade Configuration (matches SubscriptionContainerView)
    
    private var fadeConfig: PurpleFadeConfig {
        switch step {
        case .freeTrial:
            return .init(coverage: 0.65)
        case .choosePlan:
            return .init(coverage: 0.65)
        }
    }
    
    // MARK: - Background Configuration (matches SubscriptionContainerView)
    
    private var backgroundConfig: OnboardingBackgroundConfig {
        switch step {
        case .freeTrial:
            return .init(imageName: "SubscriptionTrial")
        case .choosePlan:
            return .init(imageName: "SubscriptionPlans")
        }
    }
    
    // MARK: - Header Configuration
    
    private var headerConfig: OnboardingFlowHeaderConfig {
        .init(
            actionButton: actionButton,
            showsProgressBar: false,
            progress: 0,
            title: step.title,
            subtitle: nil
        )
    }
    
    private var actionButton: OnboardingUnifiedHeader.ActionButton {
        switch step {
        case .freeTrial: return .close(action: {})
        case .choosePlan: return .backAndClose(back: {}, close: {})
        }
    }
    
    // MARK: - Footer Configuration (matches SubscriptionContainerView)
    
    private var defaultFooterConfig: OnboardingFlowFooterConfig? {
        switch step {
        case .freeTrial:
            return .init(
                primaryButton: .init(
                    text: "Start Your 7-Day Trial",
                    action: {}
                ),
                secondaryAction: .init(
                    text: "View all plans",
                    action: {}
                )
            )
            
        case .choosePlan:
            return .init(
                primaryButton: .init(
                    text: "Continue",
                    isEnabled: true, // In preview, show enabled state
                    action: {}
                ),
                secondaryAction: .init(
                    text: "Restore purchases",
                    action: {}
                )
            )
        }
    }
}

// MARK: - Preview Device Helper

/// Standard device configurations for consistent previews
enum OnboardingPreviewDevice: String, CaseIterable {
    case iPhone17Pro = "iPhone 17 Pro"
    case iPhone17ProMax = "iPhone 17 Pro Max"
    case iPhone16Pro = "iPhone 16 Pro"
    case iPhoneSE = "iPhone SE (3rd generation)"
    
    var displayName: String {
        switch self {
        case .iPhone17Pro: return "iPhone 17 Pro"
        case .iPhone17ProMax: return "iPhone 17 Pro Max"
        case .iPhone16Pro: return "iPhone 16 Pro"
        case .iPhoneSE: return "iPhone SE"
        }
    }
}

#endif
