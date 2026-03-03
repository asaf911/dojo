//
//  GoalsAcknowledgmentScreen.swift
//  imagine
//
//  Created by Cursor on 2/5/26.
//
//  Goals acknowledgment screen - Reinforces user's goal selection.
//  Shows goal-specific acknowledgment text with Sensei animation.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//

import SwiftUI

struct GoalsAcknowledgmentScreen: View {
    
    @ObservedObject var viewModel: OnboardingViewModel
    
    /// Content derived from the selected goal
    private var content: GoalsAcknowledgmentContent {
        viewModel.responses.selectedGoal?.acknowledgmentContent ?? .relaxation
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ═══════════════════════════════════════════════
            // AUTO SPACE (pushes Sensei toward vertical center)
            // ═══════════════════════════════════════════════
            Spacer()
            
            // ═══════════════════════════════════════════════
            // SENSEI WITH AURA (vertically centered)
            // ═══════════════════════════════════════════════
            SenseiView(style: .listening, topSpacing: 0)
            
            // ═══════════════════════════════════════════════
            // AUTO SPACE (pushes Sensei toward vertical center)
            // ═══════════════════════════════════════════════
            Spacer()
            
            // ═══════════════════════════════════════════════
            // ACKNOWLEDGMENT TEXT
            // ═══════════════════════════════════════════════
            Text(content.acknowledgmentText)
                .onboardingBodyLargeStyle()
                .foregroundColor(Color("ColorTextPrimary"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // ═══════════════════════════════════════════════
            // FIXED 84px SPACE (before footer)
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(height: 84)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Preview

#if DEBUG
struct GoalsAcknowledgmentScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Relaxation
            OnboardingPreviewContainer(
                step: .goalsAcknowledgment,
                customTitle: GoalsAcknowledgmentContent.relaxation.title,
                footerConfig: .init(primaryText: GoalsAcknowledgmentContent.relaxation.ctaText, isEnabled: true, action: {})
            ) {
                GoalsAcknowledgmentScreen(viewModel: makeViewModel(for: .relaxation))
            }
            .previewDisplayName("Relaxation")
            
            // Spiritual Growth
            OnboardingPreviewContainer(
                step: .goalsAcknowledgment,
                customTitle: GoalsAcknowledgmentContent.spiritualGrowth.title,
                footerConfig: .init(primaryText: GoalsAcknowledgmentContent.spiritualGrowth.ctaText, isEnabled: true, action: {})
            ) {
                GoalsAcknowledgmentScreen(viewModel: makeViewModel(for: .spiritualGrowth))
            }
            .previewDisplayName("Spiritual Growth")
            
            // Better Sleep
            OnboardingPreviewContainer(
                step: .goalsAcknowledgment,
                customTitle: GoalsAcknowledgmentContent.betterSleep.title,
                footerConfig: .init(primaryText: GoalsAcknowledgmentContent.betterSleep.ctaText, isEnabled: true, action: {})
            ) {
                GoalsAcknowledgmentScreen(viewModel: makeViewModel(for: .betterSleep))
            }
            .previewDisplayName("Better Sleep")
            
            // Focus
            OnboardingPreviewContainer(
                step: .goalsAcknowledgment,
                customTitle: GoalsAcknowledgmentContent.focus.title,
                footerConfig: .init(primaryText: GoalsAcknowledgmentContent.focus.ctaText, isEnabled: true, action: {})
            ) {
                GoalsAcknowledgmentScreen(viewModel: makeViewModel(for: .focus))
            }
            .previewDisplayName("Focus")
            
            // Visualization
            OnboardingPreviewContainer(
                step: .goalsAcknowledgment,
                customTitle: GoalsAcknowledgmentContent.visualization.title,
                footerConfig: .init(primaryText: GoalsAcknowledgmentContent.visualization.ctaText, isEnabled: true, action: {})
            ) {
                GoalsAcknowledgmentScreen(viewModel: makeViewModel(for: .visualization))
            }
            .previewDisplayName("Visualization")
            
            // Energy
            OnboardingPreviewContainer(
                step: .goalsAcknowledgment,
                customTitle: GoalsAcknowledgmentContent.energy.title,
                footerConfig: .init(primaryText: GoalsAcknowledgmentContent.energy.ctaText, isEnabled: true, action: {})
            ) {
                GoalsAcknowledgmentScreen(viewModel: makeViewModel(for: .energy))
            }
            .previewDisplayName("Energy")
        }
    }
    
    /// Creates a viewModel with a pre-selected goal for preview purposes
    private static func makeViewModel(for goal: OnboardingGoal) -> OnboardingViewModel {
        let viewModel = OnboardingViewModel()
        viewModel.selectGoal(goal)
        return viewModel
    }
}
#endif
