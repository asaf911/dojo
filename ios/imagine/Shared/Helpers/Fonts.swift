//
//  Fonts.swift
//  Dojo
//
//  Created by Michael Tabachnik on 10/8/24.
//

import Foundation
import SwiftUI

enum NunitoFontStyle: String {
    case black = "Nunito-Black"
    case blackItalic = "Nunito-Blackltalic"
    case bold = "Nunito-Bold"
    case boldItalic = "Nunito-BoldItalic"
    case extraBold = "Nunito-ExtraBold"
    case extraBoldItalic = "Nunito-ExtraBoldItalic"
    case extraLight = "Nunito-ExtraLight"
    case extraLightItalic = "Nunito-ExtraLightItalic"
    case italic = "Nunito-Italic"
    case italicVariableFont_wght = "Nunito-Italic-VariableFont_wght"
    case light = "Nunito-Light"
    case lightItalic = "Nunito-LightItalic"
    case medium = "Nunito-Medium"
    case mediumItalic = "Nunito-MediumItalic"
    case regular = "Nunito-Regular"
    case thin = "Nunito-Thin"
    case semiBold = "Nunito-SemiBold"
    case semiBoldItalic = "Nunito-SemiBoldItalic"
}

extension Font {
    static func nunito(size: CGFloat, style: NunitoFontStyle) -> Font {
        Font.custom(style.rawValue, size: size)
    }
    
    static func allenoire(size: CGFloat) -> Font {
        Font.custom("Allenoire ", size: size)
    }
}

extension Text {
    func nunitoFont(size: CGFloat, style: NunitoFontStyle = .regular) -> Text {
        self.font(Font.nunito(size: size, style: style))
    }
    func allenoireFont(size: CGFloat) -> Text {
        self.font(Font.allenoire(size: size))
    }
}

// MARK: - Onboarding Text Styles (Legacy)
// NOTE: Typography styles moved to OnboardingTypography.swift

extension View {
    /// Onboarding text style: Nunito 18 semibold, textOnboardingTitleGray color
    func onboardingTextStyle() -> some View {
        self
            .font(Font.custom("Nunito", size: 18).weight(.semibold))
            .foregroundColor(.textOnboardingTitleGray)
    }
    
    /// Onboarding question style: Nunito 16 regular, white 70% opacity
    /// Used for question labels like "Choose the obstacle that feels most true:"
    func onboardingQuestionStyle() -> some View {
        self
            .font(Font.custom("Nunito", size: 16))
            .foregroundColor(.white.opacity(0.7))
    }
}
