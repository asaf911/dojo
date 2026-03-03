//
//  HeartRateScreen.swift
//  imagine
//
//  Created by Cursor on 2/5/26.
//
//  Heart Rate screen - Asks for Apple Health read permission to track heart rate.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//  HealthKit connection is handled by the container's footer.
//
//  IMPORTANT: iOS does not reliably confirm read authorization for heart rate.
//  After prompting, we show a soft message and proceed - actual availability
//  is validated at runtime when HR data is received.
//

import SwiftUI

// MARK: - Heart Rate Screen

struct HeartRateScreen: View {
    
    @ObservedObject var viewModel: OnboardingViewModel
    
    // MARK: - Layout Configuration
    // Adjust these values to fine-tune image positions
    
    /// Overall container size for the HR illustration
    private let illustrationHeight: CGFloat = 420
    
    /// hrGraph (background) positioning — 30% larger than original 304x308
    private let graphWidth: CGFloat = 395
    private let graphHeight: CGFloat = 400
    private let graphOffsetX: CGFloat = 0
    private let graphOffsetY: CGFloat = 0
    
    /// hrWatch (bottom-left) positioning
    private let watchWidth: CGFloat = 96
    private let watchHeight: CGFloat = 139
    private let watchOffsetX: CGFloat = -111
    private let watchOffsetY: CGFloat = 120
    
    /// hrSummary (bottom-right) positioning
    private let summaryWidth: CGFloat = 218
    private let summaryOffsetX: CGFloat = 54
    private let summaryOffsetY: CGFloat = 160
    
    // MARK: - Content
    
    private let bodyText = "See how your body responds. Deepen your practice.\n\nWorks with Apple Watch, Fitbit, and compatible AirPods."
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            illustration
            
            // 32px below illustration (matching Mindful Minutes screen spacing)
            Spacer().frame(height: 32)
            
            // 16px below (matching icon-to-text gap from Mindful Minutes screen)
            Spacer().frame(height: 16)
            
            // Body text (center-aligned)
            Text(bodyText)
                .font(.custom("Nunito", size: 18).weight(.semibold))
                .foregroundColor(Color("ColorTextSecondary"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 32)
            
            // Auto space to footer
            Spacer()
        }
    }
    
    // MARK: - Illustration
    
    /// Layered HR measurement imagery (hrGlow, hrGraph, hrWatch, hrSummary)
    @ViewBuilder
    private var illustration: some View {
        ZStack {
            // Layer 0: hrGlow (behind graph, full screen width)
            Image("hrGlow")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: UIScreen.main.bounds.width)
                .offset(x: graphOffsetX, y: graphOffsetY)
            
            // Layer 1: hrGraph (background)
            Image("hrGraph")
                .resizable()
                .frame(width: graphWidth, height: graphHeight)
                .offset(x: graphOffsetX, y: graphOffsetY)
            
            // Layer 2: hrWatch (bottom-left)
            Image("hrWatch")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: watchWidth, height: watchHeight)
                .offset(x: watchOffsetX, y: watchOffsetY)
            
            // Layer 3: hrSummary (bottom-right)
            Image("hrSummary")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: summaryWidth)
                .offset(x: summaryOffsetX, y: summaryOffsetY)
        }
        .frame(height: illustrationHeight)
    }
}

// MARK: - Previews

#if DEBUG
struct HeartRateScreen_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .healthHeartRate) {
            HeartRateScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("Heart Rate Screen")
    }
}
#endif
