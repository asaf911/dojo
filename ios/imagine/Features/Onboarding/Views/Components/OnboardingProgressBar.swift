//
//  OnboardingProgressBar.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Progress bar component for the onboarding flow.
//

import SwiftUI

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    
    /// Progress value from 0.0 to 1.0
    let progress: Double
    
    /// Height of the progress bar
    var height: CGFloat = 4
    
    /// Corner radius
    var cornerRadius: CGFloat = 23
    
    /// The width of the gradient transition zone (as a fraction of total width)
    private let transitionWidth: Double = 0.10
    
    /// Clamped progress value
    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
    
    /// Computed gradient stops based on current progress
    private var gradientStops: [Gradient.Stop] {
        // Calculate where the transition should start and end
        // The transition creates the soft glow effect at the progress boundary
        let transitionStart = max(0, clampedProgress - transitionWidth)
        let transitionEnd = clampedProgress
        
        // Build gradient stops:
        // - Full color (progressBarFull) from start to just before transition
        // - Transition zone with soft edge
        // - Empty color (progressBarEmpty) after transition
        
        if clampedProgress <= 0 {
            // No progress - all empty
            return [
                Gradient.Stop(color: Color("progressBarEmpty"), location: 0),
                Gradient.Stop(color: Color("progressBarEmpty"), location: 1)
            ]
        } else if clampedProgress >= 1 {
            // Full progress - all filled
            return [
                Gradient.Stop(color: Color("progressBarFull"), location: 0),
                Gradient.Stop(color: Color("progressBarFull"), location: 1)
            ]
        } else {
            // Partial progress - gradient with glow effect
            return [
                Gradient.Stop(color: Color("progressBarFull"), location: 0),
                Gradient.Stop(color: Color("progressBarFull"), location: transitionStart),
                Gradient.Stop(color: Color("progressBarEmpty"), location: transitionEnd),
                Gradient.Stop(color: Color("progressBarEmpty"), location: 1)
            ]
        }
    }
    
    var body: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(height: height)
            .background(
                LinearGradient(
                    stops: gradientStops,
                    startPoint: UnitPoint(x: 0, y: 0.5),
                    endPoint: UnitPoint(x: 1, y: 0.5)
                )
            )
            .cornerRadius(cornerRadius)
            // Outer glow - larger and softer
            .shadow(
                color: Color("progressBarFull").opacity(0.3),
                radius: 10,
                x: 0,
                y: 0
            )
            // Middle glow - medium intensity
            .shadow(
                color: Color("progressBarFull").opacity(0.35),
                radius: 6,
                x: 0,
                y: 0
            )
            // Inner glow - tight and bright
            .shadow(
                color: Color("progressBarFull").opacity(0.4),
                radius: 2,
                x: 0,
                y: 0
            )
            .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            OnboardingProgressBar(progress: 0)
            OnboardingProgressBar(progress: 0.14)
            OnboardingProgressBar(progress: 0.25)
            OnboardingProgressBar(progress: 0.5)
            OnboardingProgressBar(progress: 0.75)
            OnboardingProgressBar(progress: 1.0)
        }
        .padding(.horizontal, 40)
        .frame(height: 200)
        .background(Color.backgroundDarkPurple)
        .previewLayout(.sizeThatFits)
    }
}
#endif
