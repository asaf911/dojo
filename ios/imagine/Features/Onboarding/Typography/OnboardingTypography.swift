//
//  OnboardingTypography.swift
//  imagine
//
//  Onboarding Typography System
//  Based on Figma Design System specifications
//

import SwiftUI

// MARK: - Onboarding Typography Role

/// Typography roles for Onboarding screens
/// Maps to Figma classification: Type/Display/Medium, Type/Heading/Large, etc.
enum OnboardingTypography {
    /// Display - Hero headlines and rare in-app moments
    /// Figma: Type/Display/Medium | Allenoire 32px Medium, 0.32px tracking
    case display
    
    /// Subtitles - Onboarding screen subtitles
    /// Figma: Type/Heading/Large | Nunito 22px Bold, line height 28, 0.32px tracking
    case subtitle
    
    /// BodyLarge - Supporting paragraphs
    /// Figma: Type/Body/Emphasis | Nunito 18px Semibold, 0.32px tracking
    case bodyLarge
    
    /// Body - Primary body text
    /// Figma: Type/Body/Primary | Nunito 16px Medium, line height 28, 0.32px tracking
    case body
    
    /// Labels - Sensei animation support text
    /// Figma: Type/Body/Label | Nunito 18px Bold, line height 18, -0.41px tracking
    case label
    
    /// Buttons - Button text
    /// Figma: Type/Buttons | Nunito 16px Semibold, line height 20, -0.24px tracking
    case button
    
    /// Supporting - Secondary UI support
    /// Figma: Type/Supporting/Medium | Nunito 14px Medium, line height 15.3, 0px tracking
    case supporting
    
    /// Card Title - For card headings
    /// Figma: Text/Heading/Card title | Nunito 16px Bold
    case cardTitle
    
    // MARK: - Font Properties
    
    var font: Font {
        switch self {
        case .display:
            return Font.custom("Allenoire ", size: 32)
        case .subtitle:
            return Font.custom("Nunito-Bold", size: 22)
        case .bodyLarge:
            return Font.custom("Nunito-SemiBold", size: 18)
        case .body:
            return Font.custom("Nunito-Medium", size: 16)
        case .label:
            return Font.custom("Nunito-Bold", size: 18)
        case .button:
            return Font.custom("Nunito-SemiBold", size: 16)
        case .supporting:
            return Font.custom("Nunito-Medium", size: 14)
        case .cardTitle:
            return Font.custom("Nunito-Bold", size: 16)
        }
    }
    
    var tracking: CGFloat {
        switch self {
        case .display, .subtitle, .bodyLarge, .body:
            return 0.32
        case .label:
            return -0.41
        case .button:
            return -0.24
        case .supporting, .cardTitle:
            return 0
        }
    }
    
    var lineSpacing: CGFloat? {
        switch self {
        case .subtitle:
            return 6  // 28 line height - 22 font size = 6
        case .body:
            return 12 // 28 line height - 16 font size = 12
        case .label:
            return 0  // 18 line height - 18 font size = 0
        case .button:
            return 4  // 20 line height - 16 font size = 4
        case .supporting:
            return 1.3 // 15.3 line height - 14 font size = 1.3
        default:
            return nil // Auto
        }
    }
}

// MARK: - View Extension for Typography

extension View {
    /// Apply onboarding typography style
    func onboardingTypography(_ style: OnboardingTypography) -> some View {
        self
            .font(style.font)
            .tracking(style.tracking)
            .modifier(OnboardingLineSpacingModifier(spacing: style.lineSpacing))
    }
    
    // MARK: - Convenience Methods with Default Colors
    
    /// Display style - for hero headlines
    /// Figma: Type/Display/Medium | Allenoire 32px, tracking 0.32, textOnboardingTitleGray
    func onboardingDisplayStyle() -> some View {
        self
            .onboardingTypography(.display)
            .foregroundColor(.textOnboardingTitleGray)
    }
    
    /// Subtitle style - for onboarding screen subtitles
    /// Figma: Type/Heading/Large | Nunito 22px Bold, line height 28, tracking 0.32, ColorTextPrimary
    func onboardingSubtitleStyle() -> some View {
        self
            .onboardingTypography(.subtitle)
            .foregroundColor(.textOnboardingTitleGray)
    }
    
    /// BodyLarge style - for supporting paragraphs
    /// Figma: Type/Body/Emphasis | Nunito 18px Semibold, tracking 0.32, ColorTextSecondary
    func onboardingBodyLargeStyle() -> some View {
        self
            .onboardingTypography(.bodyLarge)
            .foregroundColor(.white.opacity(0.7))
    }
    
    /// Body style - for primary body text
    /// Figma: Type/Body/Primary | Nunito 16px Medium, line height 28, tracking 0.32, ColorTextSecondary
    func onboardingBodyStyle() -> some View {
        self
            .onboardingTypography(.body)
            .foregroundColor(.white.opacity(0.7))
    }
    
    /// Label style - for loading/status text
    /// Figma: Type/Body/Label | Nunito 18px Bold, line height 18, tracking -0.41, ColorTextPrimary
    func onboardingLabelStyle() -> some View {
        self
            .onboardingTypography(.label)
            .foregroundColor(.textOnboardingTitleGray)
    }
    
    /// Button text style - for button labels
    /// Figma: Type/Button | Nunito 16px Semibold, line height 20, tracking -0.24, ColorTextPrimary
    func onboardingButtonTextStyle() -> some View {
        self
            .onboardingTypography(.button)
            .foregroundColor(.white)
    }
    
    /// Quote style (small) - for review/testimonial text
    /// Figma: Text/Quote/Small | Nunito 14px Italic, tracking 0.32, ColorTextTertiary
    func onboardingQuoteStyle() -> some View {
        self
            .font(Font.custom("Nunito-Italic", size: 14))
            .tracking(0.32)
            .foregroundColor(.white.opacity(0.5))
    }
    
    /// Quote style (medium) - for main testimonial statements
    /// Figma: Text/Quote/Medium | Nunito 16px Italic, tracking 0.32, ColorTextTertiary
    func onboardingQuoteMediumStyle() -> some View {
        self
            .font(Font.custom("Nunito-Italic", size: 16))
            .tracking(0.32)
            .foregroundColor(.white.opacity(0.5))
    }
}

// MARK: - Line Spacing Modifier

private struct OnboardingLineSpacingModifier: ViewModifier {
    let spacing: CGFloat?
    
    func body(content: Content) -> some View {
        if let spacing = spacing {
            content.lineSpacing(spacing)
        } else {
            content
        }
    }
}
