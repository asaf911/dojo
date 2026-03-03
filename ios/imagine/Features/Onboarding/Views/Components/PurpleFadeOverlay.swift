//
//  PurpleFadeOverlay.swift
//  imagine
//
//  Reusable purple gradient fade overlay for onboarding/subscription screens.
//  Provides a smooth gradient from solid dark purple at bottom to transparent at top.
//
//  USAGE:
//  - Container views (OnboardingContainerView, SubscriptionContainerView) control the fade
//  - Each screen can specify its coverage via the container's fadeConfig
//  - Coverage is 0-1 value: 0.5 = bottom 50%, 0.7 = bottom 70%, 1.0 = full screen
//

import SwiftUI

// MARK: - Configuration

/// Configuration for the purple fade overlay
struct PurpleFadeConfig: Equatable {
    /// Coverage from bottom (0.0 = none, 0.5 = bottom 50%, 1.0 = full screen)
    let coverage: CGFloat
    
    /// Default configuration (60% coverage)
    static let `default` = PurpleFadeConfig(coverage: 0.60)
    
    /// Preset configurations for common use cases
    static let minimal = PurpleFadeConfig(coverage: 0.40)
    static let standard = PurpleFadeConfig(coverage: 0.60)
    static let extended = PurpleFadeConfig(coverage: 0.70)
    static let full = PurpleFadeConfig(coverage: 1.0)
}

// MARK: - Purple Fade Overlay View

/// A smooth purple gradient overlay that fades from solid at the bottom to transparent at the top.
/// Used across onboarding and subscription screens to provide visual depth and text readability.
struct PurpleFadeOverlay: View {
    
    let config: PurpleFadeConfig
    
    // MARK: - Initializers
    
    init(coverage: CGFloat = 0.60) {
        self.config = PurpleFadeConfig(coverage: coverage)
    }
    
    init(config: PurpleFadeConfig) {
        self.config = config
    }
    
    // MARK: - Gradient Colors (Design System)
    
    /// Base purple color for the solid bottom - matches app's dark purple theme
    private static let solidPurple = Color(red: 0.1, green: 0.04, blue: 0.13)
    
    /// Mid-tone purple for the first transition zone
    private static let midPurple = Color(red: 0.14, green: 0.06, blue: 0.17)
    
    /// Lighter purple for the upper transition zone
    private static let lightPurple = Color(red: 0.20, green: 0.10, blue: 0.28)
    
    // MARK: - Smooth Gradient Stops
    
    /// Smoother gradient with more stops for a natural, non-banded fade.
    /// Locations are relative to the fade area (0 = bottom, 1 = top of fade zone)
    private static let smoothGradientStops: [Gradient.Stop] = [
        // Solid zone (bottom 4%) - very minimal solid area
        .init(color: solidPurple, location: 0.00),
        .init(color: solidPurple.opacity(0.92), location: 0.04),
        
        // First transition (4% - 20%) - quick transition to mid tones
        .init(color: midPurple.opacity(0.85), location: 0.10),
        .init(color: midPurple.opacity(0.75), location: 0.20),
        
        // Mid section (20% - 90%) - extended mid-tone coverage
        .init(color: lightPurple.opacity(0.62), location: 0.30),
        .init(color: lightPurple.opacity(0.55), location: 0.40),
        .init(color: lightPurple.opacity(0.48), location: 0.50),
        .init(color: lightPurple.opacity(0.42), location: 0.60),
        .init(color: lightPurple.opacity(0.36), location: 0.70),
        .init(color: lightPurple.opacity(0.30), location: 0.80),
        .init(color: lightPurple.opacity(0.22), location: 0.90),
        
        // Fade out zone (90% - 100%) - quick fade to transparent at top
        .init(color: lightPurple.opacity(0.10), location: 0.95),
        .init(color: Color.clear, location: 1.00),
    ]
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: Self.smoothGradientStops,
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: geometry.size.height * clampedCoverage)
            }
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Helpers
    
    private var clampedCoverage: CGFloat {
        max(0, min(1, config.coverage))
    }
}

// MARK: - Preview

#if DEBUG
struct PurpleFadeOverlay_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 50% coverage
            ZStack {
                Color.backgroundDarkPurple
                    .overlay(
                        Image("OnboardingWelcome")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .ignoresSafeArea()
                
                PurpleFadeOverlay(coverage: 0.50)
                
                VStack {
                    Spacer()
                    Text("50% Coverage")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding(.bottom, 100)
                }
            }
            .previewDisplayName("50% Coverage")
            
            // 65% coverage
            ZStack {
                Color.backgroundDarkPurple
                    .overlay(
                        Image("OnboardingSensei")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .ignoresSafeArea()
                
                PurpleFadeOverlay(coverage: 0.65)
                
                VStack {
                    Spacer()
                    Text("65% Coverage")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding(.bottom, 100)
                }
            }
            .previewDisplayName("65% Coverage")
            
            // 80% coverage
            ZStack {
                Color.backgroundDarkPurple
                    .overlay(
                        Image("OnboardingGoals")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .ignoresSafeArea()
                
                PurpleFadeOverlay(coverage: 0.80)
                
                VStack {
                    Spacer()
                    Text("80% Coverage")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding(.bottom, 100)
                }
            }
            .previewDisplayName("80% Coverage")
        }
        .preferredColorScheme(.dark)
    }
}
#endif
