//
//  OnboardingPrimaryButton.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Primary CTA button component for the onboarding flow.
//

import SwiftUI

// MARK: - Button Style

enum OnboardingButtonStyle {
    case primary    // Gradient purple-to-pink
    case secondary  // Glassy button (unselected state)
    case tertiary   // Text only
}

// MARK: - Primary Button

struct OnboardingPrimaryButton: View {
    
    let text: String
    var style: OnboardingButtonStyle = .primary
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void
    
    // MARK: - Gradient Colors
    
    private var primaryGradient: LinearGradient {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.55, green: 0.33, blue: 1), location: 0.00),
                Gradient.Stop(color: Color(red: 0.88, green: 0.28, blue: 0.64), location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.496, y: 0),
            endPoint: UnitPoint(x: 0.504, y: 1)
        )
    }
    
    var body: some View {
        Button(action: {
            guard isEnabled, !isLoading else { return }
            HapticManager.shared.impact(.light)
            action()
        }) {
            HStack(alignment: .center, spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(text)
                        .onboardingButtonTextStyle()
                }
            }
            .padding(0)
            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .center)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .modifier(ButtonGlassEffectModifier(style: style))
            .overlay(buttonOverlay)
            .modifier(SecondaryButtonSpecularBorder(style: style))
            .contentShape(RoundedRectangle(cornerRadius: 23))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 23))
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled || isLoading)
    }
    
    // MARK: - Background
    
    @ViewBuilder
    private var buttonBackground: some View {
        switch style {
        case .primary:
            primaryGradient
        case .secondary:
            // Clean background - let glassEffect handle the glass treatment
            RoundedRectangle(cornerRadius: 23)
                .fill(Color.clear)
        case .tertiary:
            Color.clear
        }
    }
    
    // MARK: - Overlay
    
    @ViewBuilder
    private var buttonOverlay: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: 23)
                .inset(by: 0.5)
                .stroke(Color(red: 0.95, green: 0.96, blue: 0.98).opacity(0.25), lineWidth: 1)
        case .secondary:
            // Specular border for glassy effect
            EmptyView()
        case .tertiary:
            EmptyView()
        }
    }
}

// MARK: - Button Glass Effect Modifier

struct ButtonGlassEffectModifier: ViewModifier {
    let style: OnboardingButtonStyle
    
    func body(content: Content) -> some View {
        switch style {
        case .primary:
            content.liquidGlass(cornerRadius: 23, style: .primary)
        case .secondary:
            content.liquidGlass(cornerRadius: 23, style: .secondary)
        case .tertiary:
            content
        }
    }
}

// MARK: - Secondary Button Specular Border Modifier

struct SecondaryButtonSpecularBorder: ViewModifier {
    let style: OnboardingButtonStyle
    
    func body(content: Content) -> some View {
        if style == .secondary {
            content.specularBorder(cornerRadius: 23)
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingPrimaryButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            OnboardingPrimaryButton(text: "Set intention", style: .primary) {}
            OnboardingPrimaryButton(text: "Start free 7-day trial", style: .primary) {}
            OnboardingPrimaryButton(text: "Get started", style: .secondary) {}
            OnboardingPrimaryButton(text: "View all plans", style: .tertiary) {}
            OnboardingPrimaryButton(text: "Disabled", style: .primary, isEnabled: false) {}
            OnboardingPrimaryButton(text: "Loading", style: .primary, isLoading: true) {}
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .background(Color.backgroundDarkPurple)
        .previewLayout(.sizeThatFits)
    }
}
#endif
