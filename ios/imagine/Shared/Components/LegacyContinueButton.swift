//
//  LegacyContinueButton.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-03-XX
//
//  Legacy continue button used by AccountCreationValueView and other non-onboarding screens.
//  For onboarding screens, use OnboardingPrimaryButton and OnboardingUnifiedFooter instead.
//

import SwiftUI
import UIKit

/// Legacy continue button for screens outside the onboarding flow.
/// - Note: For onboarding screens, use `OnboardingPrimaryButton` with `OnboardingUnifiedFooter`.
struct LegacyContinueButton: View {
    var text: String = "Continue"
    var action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            // Wrap the text in a container that takes up the full frame and makes the entire area tappable.
            Text(text)
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.foregroundLightGray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .contentShape(Rectangle())
        }
        .frame(width: 280, height: 46)
        .overlay(
            RoundedRectangle(cornerRadius: 23)
                .stroke(Color.foregroundLightGray, lineWidth: 1)
        )
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Legacy Extension

/// Legacy extension to place a continue button near the bottom.
/// - Note: For onboarding screens, use `.unifiedFooterOverlay()` from `OnboardingUnifiedFooter` instead.
extension View {
    @ViewBuilder
    func continueButtonOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        self.overlay(
            VStack {
                Spacer()
                content()
                    .padding(.bottom, 70)
            }
        )
    }
}

struct LegacyContinueButton_Previews: PreviewProvider {
    static var previews: some View {
        LegacyContinueButton() {
            print("Continue tapped")
        }
        .background(Color.backgroundDarkPurple)
        .previewLayout(.sizeThatFits)
    }
}
