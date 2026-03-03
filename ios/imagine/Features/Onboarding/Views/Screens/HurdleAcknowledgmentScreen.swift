//
//  HurdleAcknowledgmentScreen.swift
//  imagine
//
//  Created by Cursor on 2/5/26.
//
//  Hurdle acknowledgment screen - Reinforces user's hurdle selection.
//  Shows hurdle-specific acknowledgment text with Sensei animation.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//

import SwiftUI

struct HurdleAcknowledgmentScreen: View {
    
    @ObservedObject var viewModel: OnboardingViewModel
    
    /// Content derived from the selected hurdle
    private var content: HurdleAcknowledgmentContent {
        viewModel.responses.selectedHurdle?.acknowledgmentContent ?? .default
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
struct HurdleAcknowledgmentScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Mind Won't Slow Down (Relaxation)
            OnboardingPreviewContainer(
                step: .hurdleAcknowledgment,
                customTitle: HurdleAcknowledgmentContent.mindWontSlowDown.title,
                footerConfig: .init(primaryText: HurdleAcknowledgmentContent.mindWontSlowDown.ctaText, isEnabled: true, action: {})
            ) {
                HurdleAcknowledgmentScreen(viewModel: makeViewModel(hurdleId: "mind_wont_slow_down"))
            }
            .previewDisplayName("Mind Won't Slow Down")
            
            // Can't Fall Asleep (Sleep)
            OnboardingPreviewContainer(
                step: .hurdleAcknowledgment,
                customTitle: HurdleAcknowledgmentContent.cantFallAsleep.title,
                footerConfig: .init(primaryText: HurdleAcknowledgmentContent.cantFallAsleep.ctaText, isEnabled: true, action: {})
            ) {
                HurdleAcknowledgmentScreen(viewModel: makeViewModel(hurdleId: "cant_fall_asleep"))
            }
            .previewDisplayName("Can't Fall Asleep")
            
            // Mind Too Noisy (Focus)
            OnboardingPreviewContainer(
                step: .hurdleAcknowledgment,
                customTitle: HurdleAcknowledgmentContent.mindTooNoisy.title,
                footerConfig: .init(primaryText: HurdleAcknowledgmentContent.mindTooNoisy.ctaText, isEnabled: true, action: {})
            ) {
                HurdleAcknowledgmentScreen(viewModel: makeViewModel(hurdleId: "mind_too_noisy"))
            }
            .previewDisplayName("Mind Too Noisy")
            
            // No Drive (Energy)
            OnboardingPreviewContainer(
                step: .hurdleAcknowledgment,
                customTitle: HurdleAcknowledgmentContent.noDrive.title,
                footerConfig: .init(primaryText: HurdleAcknowledgmentContent.noDrive.ctaText, isEnabled: true, action: {})
            ) {
                HurdleAcknowledgmentScreen(viewModel: makeViewModel(hurdleId: "no_drive"))
            }
            .previewDisplayName("No Drive")
        }
    }
    
    /// Creates a viewModel with a pre-selected hurdle for preview purposes
    private static func makeViewModel(hurdleId: String) -> OnboardingViewModel {
        let viewModel = OnboardingViewModel()
        // Create a hurdle option with the given id
        let hurdleOption = HurdleScreenContent.HurdleOption(id: hurdleId, displayName: "")
        viewModel.selectHurdle(hurdleOption)
        return viewModel
    }
}
#endif
