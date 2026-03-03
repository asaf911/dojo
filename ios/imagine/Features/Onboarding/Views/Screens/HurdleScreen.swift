//
//  HurdleScreen.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Hurdle selection screen - Dynamic content based on selected goal.
//  Single-select hurdle for personalization.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//

import SwiftUI

struct HurdleScreen: View {
    
    @ObservedObject var viewModel: OnboardingViewModel
    
    /// Content derived from the selected goal
    private var content: HurdleScreenContent {
        viewModel.responses.selectedGoal?.hurdleScreenContent ?? .relaxation
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ═══════════════════════════════════════════════
            // FLEXIBLE SPACE (title is in unified header)
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(minHeight: 20, maxHeight: 40)
            
            // ═══════════════════════════════════════════════
            // SENSEI WITH AURA
            // ═══════════════════════════════════════════════
            SenseiView(style: .listening, topSpacing: 50)
            
            // ═══════════════════════════════════════════════
            // SUBTITLE (dynamic based on goal)
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(height: 4)
            
            Text(content.subtitle)
                .onboardingBodyLargeStyle()
                .foregroundColor(Color("ColorTextPrimary"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // ═══════════════════════════════════════════════
            // QUESTION (dynamic based on goal)
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(height: 14)
            
            Text(content.question)
                .onboardingBodyStyle()
                .foregroundColor(Color("ColorTextPrimary"))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // ═══════════════════════════════════════════════
            // OPTIONS (single-select, dynamic based on goal)
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(height: 14)
            
            VStack(spacing: 12) {
                ForEach(content.options) { option in
                    HurdleOptionButton(
                        title: option.displayName,
                        isSelected: viewModel.responses.selectedHurdle?.id == option.id
                    ) {
                        viewModel.selectHurdle(option)
                    }
                }
            }
            
            // ═══════════════════════════════════════════════
            // BOTTOM SPACER (fills remaining space)
            // ═══════════════════════════════════════════════
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Hurdle Option Button

/// Option button for single-select hurdles (centered text, no icon)
private struct HurdleOptionButton: View {
    let title: String
    var isSelected: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            Text(title)
                .onboardingButtonTextStyle()
                .foregroundColor(Color("ColorTextPrimary"))
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 23)
                        .fill(isSelected ? Color.onboardingButtonSelected : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 23))
                .liquidGlass(cornerRadius: 23, style: .secondary)
                .specularBorder(cornerRadius: 23)
                .contentShape(RoundedRectangle(cornerRadius: 23))
        }
        .contentShape(RoundedRectangle(cornerRadius: 23))
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#if DEBUG
struct HurdleScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Relaxation
            OnboardingPreviewContainer(
                step: .hurdle,
                customTitle: HurdleScreenContent.relaxation.title,
                footerConfig: .init(primaryText: HurdleScreenContent.relaxation.ctaText, isEnabled: true, action: {})
            ) {
                HurdleScreen(viewModel: makeViewModel(for: .relaxation))
            }
            .previewDisplayName("Relaxation")
            
            // Spiritual Growth
            OnboardingPreviewContainer(
                step: .hurdle,
                customTitle: HurdleScreenContent.spiritualGrowth.title,
                footerConfig: .init(primaryText: HurdleScreenContent.spiritualGrowth.ctaText, isEnabled: true, action: {})
            ) {
                HurdleScreen(viewModel: makeViewModel(for: .spiritualGrowth))
            }
            .previewDisplayName("Spiritual Growth")
            
            // Better Sleep
            OnboardingPreviewContainer(
                step: .hurdle,
                customTitle: HurdleScreenContent.betterSleep.title,
                footerConfig: .init(primaryText: HurdleScreenContent.betterSleep.ctaText, isEnabled: true, action: {})
            ) {
                HurdleScreen(viewModel: makeViewModel(for: .betterSleep))
            }
            .previewDisplayName("Better Sleep")
            
            // Focus
            OnboardingPreviewContainer(
                step: .hurdle,
                customTitle: HurdleScreenContent.focus.title,
                footerConfig: .init(primaryText: HurdleScreenContent.focus.ctaText, isEnabled: true, action: {})
            ) {
                HurdleScreen(viewModel: makeViewModel(for: .focus))
            }
            .previewDisplayName("Focus")
            
            // Visualization
            OnboardingPreviewContainer(
                step: .hurdle,
                customTitle: HurdleScreenContent.visualization.title,
                footerConfig: .init(primaryText: HurdleScreenContent.visualization.ctaText, isEnabled: true, action: {})
            ) {
                HurdleScreen(viewModel: makeViewModel(for: .visualization))
            }
            .previewDisplayName("Visualization")
            
            // Energy
            OnboardingPreviewContainer(
                step: .hurdle,
                customTitle: HurdleScreenContent.energy.title,
                footerConfig: .init(primaryText: HurdleScreenContent.energy.ctaText, isEnabled: true, action: {})
            ) {
                HurdleScreen(viewModel: makeViewModel(for: .energy))
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
