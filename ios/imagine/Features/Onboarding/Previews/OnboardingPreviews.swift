//
//  OnboardingPreviews.swift
//  imagine
//
//  Master preview file for all Onboarding screens and components.
//  Open this file in Xcode and press ⌥⌘↩ (Option+Command+Return) to see all previews.
//
//  Preview Names:
//  - 📱 All Screens Gallery: Horizontal scroll of all 10 onboarding screens
//  - Individual screens: Welcome, Sensei, Goals, Goals Acknowledgment, Hurdle, Hurdle Acknowledgment, Mindful Minutes, Heart Rate, Building, Ready
//  - 💳 Subscription Screens: Free Trial and Choose Plan
//  - 🧩 Components: All UI components in isolation
//  - 📐 Device Sizes: Compare layouts on SE, Pro, Pro Max
//
//  NOTE: All previews use OnboardingPreviewContainer to match production safe area behavior.
//

import SwiftUI

#if DEBUG

// MARK: - All Screens Gallery (Horizontal Scroll)

struct Onboarding_AllScreens_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    OnboardingPreviewContainer(step: step) {
                        screenContent(for: step, viewModel: OnboardingViewModel())
                    }
                    .frame(width: 393, height: 852) // iPhone 15 Pro dimensions
                    .clipShape(RoundedRectangle(cornerRadius: 40))
                    .overlay(
                        Text(step.title)
                            .font(.caption.bold())
                            .padding(8)
                            .background(.black.opacity(0.7))
                            .cornerRadius(8)
                            .padding(8),
                        alignment: .topLeading
                    )
                }
            }
            .padding()
        }
        .previewDisplayName("📱 All Screens Gallery")
        .previewLayout(.fixed(width: 2900, height: 920))
    }
    
    @ViewBuilder
    static func screenContent(for step: OnboardingStep, viewModel: OnboardingViewModel) -> some View {
        switch step {
        case .welcome: WelcomeScreen(viewModel: viewModel)
        case .sensei: SenseiScreen(viewModel: viewModel)
        case .goals: GoalsScreen(viewModel: viewModel)
        case .goalsAcknowledgment: GoalsAcknowledgmentScreen(viewModel: viewModel)
        case .hurdle: HurdleScreen(viewModel: viewModel)
        case .hurdleAcknowledgment: HurdleAcknowledgmentScreen(viewModel: viewModel)
        case .healthMindfulMinutes: MindfulMinutesScreen(viewModel: viewModel)
        case .healthHeartRate: HeartRateScreen(viewModel: viewModel)
        case .building: BuildingScreen(viewModel: viewModel)
        case .ready: ReadyScreen(viewModel: viewModel)
        }
    }
}

// MARK: - Individual Screen Previews
// All use OnboardingPreviewContainer for accurate safe area rendering

struct Onboarding_Welcome_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .welcome) {
            WelcomeScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("1️⃣ Welcome")
    }
}

struct Onboarding_Sensei_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .sensei) {
            SenseiScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("2️⃣ Sensei")
    }
}

struct Onboarding_Goals_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .goals) {
            GoalsScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("3️⃣ Goals")
    }
}

struct Onboarding_GoalsAcknowledgment_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = OnboardingViewModel()
        viewModel.selectGoal(.relaxation)
        return OnboardingPreviewContainer(step: .goalsAcknowledgment) {
            GoalsAcknowledgmentScreen(viewModel: viewModel)
        }
        .previewDisplayName("4️⃣ Goals Acknowledgment")
    }
}

struct Onboarding_Hurdle_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .hurdle) {
            HurdleScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("5️⃣ Hurdle")
    }
}

struct Onboarding_HurdleAcknowledgment_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = OnboardingViewModel()
        // Select a hurdle option for the preview
        let hurdleOption = HurdleScreenContent.HurdleOption(id: "mind_wont_slow_down", displayName: "My mind won't slow down")
        viewModel.selectHurdle(hurdleOption)
        return OnboardingPreviewContainer(step: .hurdleAcknowledgment) {
            HurdleAcknowledgmentScreen(viewModel: viewModel)
        }
        .previewDisplayName("6️⃣ Hurdle Acknowledgment")
    }
}

struct Onboarding_MindfulMinutes_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .healthMindfulMinutes) {
            MindfulMinutesScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("7️⃣ Mindful Minutes")
    }
}

struct Onboarding_HeartRate_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .healthHeartRate) {
            HeartRateScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("8️⃣ Heart Rate")
    }
}

struct Onboarding_Building_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .building) {
            BuildingScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("9️⃣ Building")
    }
}

struct Onboarding_Ready_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .ready) {
            ReadyScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("🔟 Ready")
    }
}

// MARK: - Subscription Screens

struct Subscription_AllScreens_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                FreeTrialScreen(viewModel: SubscriptionViewModel())
                    .frame(width: 390, height: 844)
                    .clipShape(RoundedRectangle(cornerRadius: 40))
                    .overlay(
                        Text("Free Trial")
                            .font(.caption.bold())
                            .padding(8)
                            .background(.black.opacity(0.7))
                            .cornerRadius(8)
                            .padding(8),
                        alignment: .topLeading
                    )
                
                ChoosePlanScreen(viewModel: SubscriptionViewModel())
                    .frame(width: 390, height: 844)
                    .clipShape(RoundedRectangle(cornerRadius: 40))
                    .overlay(
                        Text("Choose Plan")
                            .font(.caption.bold())
                            .padding(8)
                            .background(.black.opacity(0.7))
                            .cornerRadius(8)
                            .padding(8),
                        alignment: .topLeading
                    )
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("💳 Subscription Screens")
        .previewLayout(.fixed(width: 900, height: 900))
    }
}

struct Subscription_FreeTrial_Previews: PreviewProvider {
    static var previews: some View {
        FreeTrialScreen(viewModel: SubscriptionViewModel())
            .preferredColorScheme(.dark)
            .previewDisplayName("💳 Free Trial")
    }
}

struct Subscription_ChoosePlan_Previews: PreviewProvider {
    static var previews: some View {
        ChoosePlanScreen(viewModel: SubscriptionViewModel())
            .preferredColorScheme(.dark)
            .previewDisplayName("💳 Choose Plan")
    }
}

// MARK: - Components Preview

struct Onboarding_Components_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 40) {
                // Buttons Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("BUTTONS")
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                    
                    OnboardingPrimaryButton(text: "Set Intention", style: .primary) {}
                    OnboardingPrimaryButton(text: "Begin Your Practice", style: .primary) {}
                    OnboardingPrimaryButton(text: "Start Your 7-Day Trial", style: .primary) {}
                    OnboardingPrimaryButton(text: "Step Inside", style: .secondary) {}
                    OnboardingPrimaryButton(text: "View all plans", style: .tertiary) {}
                    
                    Divider().background(Color.gray.opacity(0.3))
                    
                    Text("BUTTON STATES")
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                    
                    OnboardingPrimaryButton(text: "Disabled Button", style: .primary, isEnabled: false) {}
                    OnboardingPrimaryButton(text: "Loading...", style: .primary, isLoading: true) {}
                }
                
                // Progress Bar Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("PROGRESS BAR")
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                    
                    HStack {
                        Text("0%")
                            .font(.caption)
                            .foregroundColor(.gray)
                        OnboardingProgressBar(progress: 0.0)
                    }
                    HStack {
                        Text("33%")
                            .font(.caption)
                            .foregroundColor(.gray)
                        OnboardingProgressBar(progress: 0.33)
                    }
                    HStack {
                        Text("66%")
                            .font(.caption)
                            .foregroundColor(.gray)
                        OnboardingProgressBar(progress: 0.66)
                    }
                    HStack {
                        Text("100%")
                            .font(.caption)
                            .foregroundColor(.gray)
                        OnboardingProgressBar(progress: 1.0)
                    }
                }
                
                // Selectable Cards Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("SELECTABLE CARDS")
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                    
                    OnboardingSelectableCard(
                        title: "Reduce Stress",
                        icon: "leaf.fill",
                        isSelected: false
                    ) {}
                    
                    OnboardingSelectableCard(
                        title: "Better sleep",
                        icon: "moon.fill",
                        isSelected: true
                    ) {}
                    
                    OnboardingSelectableCard(
                        title: "Improve Focus",
                        icon: "brain.head.profile",
                        isSelected: false
                    ) {}
                }
                
                // Fade Style Section (Single Source of Truth)
                VStack(alignment: .leading, spacing: 16) {
                    Text("FADE COVERAGE")
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 12) {
                        VStack {
                            ZStack {
                                Color.backgroundDarkPurple
                                PurpleFadeOverlay(coverage: 0.30)
                            }
                            .frame(width: 100, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("30%")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        
                        VStack {
                            ZStack {
                                Color.backgroundDarkPurple
                                PurpleFadeOverlay(coverage: 0.50)
                            }
                            .frame(width: 100, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("50%")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        
                        VStack {
                            ZStack {
                                Color.backgroundDarkPurple
                                PurpleFadeOverlay(coverage: 0.70)
                            }
                            .frame(width: 100, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("70%")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .padding(30)
        }
        .background(Color.backgroundDarkPurple)
        .preferredColorScheme(.dark)
        .previewDisplayName("🧩 Components")
    }
}

// MARK: - Device Size Comparison

struct Onboarding_DeviceSizes_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // iPhone SE (smallest screen, no Dynamic Island)
            OnboardingPreviewContainer(step: .sensei) {
                SenseiScreen(viewModel: OnboardingViewModel())
            }
            .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
            .previewDisplayName("📐 iPhone SE")
            
            // iPhone 16 Pro (Dynamic Island)
            OnboardingPreviewContainer(step: .sensei) {
                SenseiScreen(viewModel: OnboardingViewModel())
            }
            .previewDevice(PreviewDevice(rawValue: "iPhone 16 Pro"))
            .previewDisplayName("📐 iPhone 16 Pro")
            
            // iPhone 16 Pro Max (largest Dynamic Island device)
            OnboardingPreviewContainer(step: .sensei) {
                SenseiScreen(viewModel: OnboardingViewModel())
            }
            .previewDevice(PreviewDevice(rawValue: "iPhone 16 Pro Max"))
            .previewDisplayName("📐 iPhone 16 Pro Max")
        }
    }
}

// MARK: - Full Flow Preview (Interactive)

struct Onboarding_FullFlow_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingContainerView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(AppState())
            .preferredColorScheme(.dark)
            .previewDisplayName("🔄 Full Flow (Interactive)")
    }
}

#endif
