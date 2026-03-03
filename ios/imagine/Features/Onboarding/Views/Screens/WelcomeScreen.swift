//
//  WelcomeScreen.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Welcome screen - first screen in the onboarding flow.
//  Features splash image with inline "Get started" CTA button.
//
//  NOTE: This screen has its button inline (not in footer). Background is provided by container.
//

import SwiftUI

struct WelcomeScreen: View {
    
    // MARK: - Layout Configuration
    
    /// Tunable layout constants for positioning content relative to background
    private enum Layout {
        // ═══════════════════════════════════════════════════════════════════════
        // VERTICAL POSITIONING (relative to screen height)
        // ═══════════════════════════════════════════════════════════════════════
        
        /// How far down the screen the content block starts (0.0 = top, 1.0 = bottom)
        /// Decrease to move content UP, increase to move content DOWN
        static let contentTopRatio: CGFloat = 0.525
        
        // ═══════════════════════════════════════════════════════════════════════
        // INTERNAL SPACING (fixed values between content elements)
        // ═══════════════════════════════════════════════════════════════════════
        
        /// Space between title ("Welcome to Dojo") and subtitle ("Guided, personal meditation")
        static let titleToSubtitleSpacing: CGFloat = 48
        
        /// Space between subtitle and body text ("A practice built for you")
        static let subtitleToBodySpacing: CGFloat = 12
        
        /// Space between body text and CTA button
        static let bodyToButtonSpacing: CGFloat = 14
    }
    
    // MARK: - Properties
    
    @ObservedObject var viewModel: OnboardingViewModel
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Dynamic top spacer - scales with screen height
                Spacer()
                    .frame(height: geometry.size.height * Layout.contentTopRatio)
                
                // Content block
                VStack(spacing: 0) {
                    Text("Welcome to Dojo")
                        .onboardingDisplayStyle()
                    
                    Spacer()
                        .frame(height: Layout.titleToSubtitleSpacing)
                    
                    Text("Personal meditation training")
                        .onboardingSubtitleStyle()
                    
                    Spacer()
                        .frame(height: Layout.subtitleToBodySpacing)
                    
                    Text("Built around you")
                        .onboardingBodyLargeStyle()
                    
                    Spacer()
                        .frame(height: Layout.bodyToButtonSpacing)
                    
                    OnboardingPrimaryButton(
                        text: "Begin",
                        style: .secondary,
                        action: { viewModel.advance() }
                    )
                }
                .multilineTextAlignment(.center)
                
                // Flexible bottom spacer
                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .welcome) {
            WelcomeScreen(viewModel: OnboardingViewModel())
        }
    }
}
#endif
