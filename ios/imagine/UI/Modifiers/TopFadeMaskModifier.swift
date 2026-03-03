//
//  TopFadeMaskModifier.swift
//  imagine
//
//  Reusable modifier for smooth top fade effect on scrollable content
//

import SwiftUI

// MARK: - Top Fade Mask Modifier

/// Applies a gradient mask that fades content from transparent at top to opaque below.
/// Used for smooth content scrolling under headers.
struct TopFadeMaskModifier: ViewModifier {
    let fadeHeight: CGFloat
    
    func body(content: Content) -> some View {
        content
            .mask(
                VStack(spacing: 0) {
                    // Top fade: transparent → opaque (sharp but smooth)
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.1),
                            .init(color: .white.opacity(0.3), location: 0.4),
                            .init(color: .white.opacity(0.7), location: 0.7),
                            .init(color: .white, location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: fadeHeight)
                    
                    // Rest of content: fully opaque
                    Color.white
                }
            )
    }
}

// MARK: - View Extension

extension View {
    /// Applies a top fade mask effect for smooth content scrolling under headers
    /// - Parameter height: Height of the fade zone (default: 24px)
    func topFadeMask(height: CGFloat = 24) -> some View {
        modifier(TopFadeMaskModifier(fadeHeight: height))
    }
}

