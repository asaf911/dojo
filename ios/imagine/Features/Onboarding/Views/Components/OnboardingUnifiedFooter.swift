//
//  OnboardingUnifiedFooter.swift
//  imagine
//
//  Created by Cursor on 1/16/26.
//
//  Unified footer component for onboarding and subscription screens.
//  
//  NOTE: The new OnboardingFlowContainer handles footer rendering directly.
//  This file is kept for backward compatibility with legacy subscription views.
//

import SwiftUI

// MARK: - Unified Footer

struct OnboardingUnifiedFooter: View {
    
    // MARK: - Configuration Types
    
    /// Configuration for the primary action button
    struct PrimaryButtonConfig {
        let text: String
        let style: OnboardingButtonStyle
        let isEnabled: Bool
        let isLoading: Bool
        let action: () -> Void
        
        init(
            text: String,
            style: OnboardingButtonStyle = .primary,
            isEnabled: Bool = true,
            isLoading: Bool = false,
            action: @escaping () -> Void
        ) {
            self.text = text
            self.style = style
            self.isEnabled = isEnabled
            self.isLoading = isLoading
            self.action = action
        }
    }
    
    /// Configuration for the secondary/skip action
    struct SecondaryActionConfig {
        let text: String
        let action: () -> Void
        
        init(text: String, action: @escaping () -> Void) {
            self.text = text
            self.action = action
        }
    }
    
    // MARK: - Layout Constants
    
    /// Standard horizontal padding for footer content
    static let horizontalPadding: CGFloat = 32
    
    /// Distance from SCREEN bottom (not safe area) to the bottom edge of the primary button.
    static let primaryButtonBottomFromScreen: CGFloat = 50
    
    /// Standard primary button height (matches OnboardingPrimaryButton)
    static let primaryButtonHeight: CGFloat = 46
    
    /// Legacy aliases
    static var primaryButtonBottomPadding: CGFloat { primaryButtonBottomFromScreen }
    static var bottomPadding: CGFloat { primaryButtonBottomFromScreen }
    
    // MARK: - Properties
    
    let primaryButton: PrimaryButtonConfig?
    let secondaryAction: SecondaryActionConfig?
    
    // MARK: - Initializers
    
    init(
        primaryButton: PrimaryButtonConfig? = nil,
        secondaryAction: SecondaryActionConfig? = nil
    ) {
        self.primaryButton = primaryButton
        self.secondaryAction = secondaryAction
    }
    
    init(
        primaryText: String,
        primaryStyle: OnboardingButtonStyle = .primary,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.primaryButton = PrimaryButtonConfig(
            text: primaryText,
            style: primaryStyle,
            isEnabled: isEnabled,
            isLoading: isLoading,
            action: action
        )
        self.secondaryAction = nil
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            if let config = primaryButton {
                OnboardingPrimaryButton(
                    text: config.text,
                    style: config.style,
                    isEnabled: config.isEnabled,
                    isLoading: config.isLoading,
                    action: config.action
                )
            }
            
            if let secondary = secondaryAction {
                Button(action: {
                    HapticManager.shared.impact(.light)
                    secondary.action()
                }) {
                    // Text/Supporting/Medium - ColorTextSecondary
                    Text(secondary.text)
                        .onboardingTypography(.supporting)
                        .foregroundColor(Color("ColorTextSecondary"))
                }
                .frame(height: Self.primaryButtonBottomFromScreen)
            } else {
                Spacer()
                    .frame(height: Self.primaryButtonBottomFromScreen)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - View Modifier (Legacy - for backward compatibility)

extension View {
    /// Legacy overlay modifier - kept for backward compatibility with older subscription views
    func unifiedFooterOverlay(
        primaryButton: OnboardingUnifiedFooter.PrimaryButtonConfig? = nil,
        secondaryAction: OnboardingUnifiedFooter.SecondaryActionConfig? = nil
    ) -> some View {
        self.overlay(alignment: .bottom) {
            OnboardingUnifiedFooter(
                primaryButton: primaryButton,
                secondaryAction: secondaryAction
            )
        }
    }
    
    /// Legacy convenience overlay
    func unifiedFooterOverlay(
        primaryText: String,
        primaryStyle: OnboardingButtonStyle = .primary,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        self.overlay(alignment: .bottom) {
            OnboardingUnifiedFooter(
                primaryText: primaryText,
                primaryStyle: primaryStyle,
                isEnabled: isEnabled,
                isLoading: isLoading,
                action: action
            )
        }
    }
    
    /// Legacy footer height calculation
    static var footerReservedHeight: CGFloat {
        OnboardingUnifiedFooter.primaryButtonBottomFromScreen + OnboardingUnifiedFooter.primaryButtonHeight
    }
}
