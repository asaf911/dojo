//
//  RecommendationCardShell.swift
//  imagine
//
//  Created for Clean Recommendation Card Architecture
//
//  Base container component that provides consistent card styling
//  for both primary and secondary presentation modes.
//

import SwiftUI
import Kingfisher

// MARK: - Recommendation Card Shell

/// Base card container with consistent styling for primary and secondary modes
struct RecommendationCardShell<Content: View>: View {
    let presentationMode: CardPresentationMode
    let contentType: MeditationContentType
    let accentColor: Color
    let onTap: () -> Void
    var isCompleted: Bool = false  // For path cards - affects stroke/shadow intensity
    var isSelected: Bool = false   // For secondary cards - selected state before navigation
    var isDeselected: Bool = false // For primary cards - deselected when secondary is tapped
    var backgroundImageURL: URL? = nil  // For pre-recorded cards with dynamic images
    @ViewBuilder let content: () -> Content
    
    // MARK: - Computed Properties
    
    /// Whether this is a primary card (all primary cards get enhanced stroke/shadow)
    private var isPrimaryCard: Bool {
        presentationMode == .primary
    }
    
    /// Whether to use enhanced (primary-like) styling
    /// Primary cards use enhanced unless deselected; secondary cards use enhanced when selected or completed
    private var useEnhancedStyling: Bool {
        // Completed cards always use enhanced styling
        if isCompleted {
            return true
        }
        if isPrimaryCard {
            return !isDeselected
        }
        return isSelected
    }
    
    private var strokeColor: Color {
        // Completed cards always get accent (purple) stroke
        if isCompleted {
            return accentColor.opacity(0.5)
        }
        
        switch presentationMode {
        case .primary:
            // Deselected primary cards get gray stroke like secondary
            return isDeselected ? Color(red: 0.95, green: 0.96, blue: 0.98).opacity(0.35) : accentColor.opacity(0.5)
        case .secondary:
            // Selected secondary cards get turquoise stroke like primary
            return isSelected ? accentColor.opacity(0.5) : Color(red: 0.95, green: 0.96, blue: 0.98).opacity(0.35)
        }
    }
    
    private var strokeWidth: CGFloat {
        useEnhancedStyling ? 2 : 1
    }
    
    private var shadowColor: Color {
        accentColor.opacity(useEnhancedStyling ? 0.375 : 0.25)
    }
    
    private var shadowRadius: CGFloat {
        useEnhancedStyling ? 3 : 2
    }
    
    private var cornerRadius: CGFloat {
        18
    }
    
    /// Whether to show shadow (primary cards unless deselected, secondary when selected or completed)
    private var showShadow: Bool {
        // Completed cards always show shadow
        if isCompleted {
            return true
        }
        if isPrimaryCard {
            return !isDeselected
        }
        return isSelected
    }
    
    // MARK: - Body
    
    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .cornerRadius(cornerRadius)
            .shadow(color: showShadow ? shadowColor : .clear, radius: shadowRadius, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .inset(by: 0.5)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .animation(.easeOut(duration: 0.25), value: isSelected)
            .animation(.easeOut(duration: 0.25), value: isDeselected)
            .contentShape(Rectangle())
            .onTapGesture {
                // Haptic for primary cards only (secondary cards handle haptic in their own tap handler)
                if presentationMode == .primary {
                    HapticManager.shared.impact(.medium)
                }
                onTap()
            }
    }
    
    // MARK: - Card Background
    
    @ViewBuilder
    private var cardBackground: some View {
        ZStack {
            // Base background (image or gradient)
            if let imageURL = backgroundImageURL {
                // Pre-recorded cards with dynamic Firebase image
                imageBackgroundWithURL(url: imageURL)
            } else if let imageName = contentType.backgroundImageName {
                // Custom/Path cards with static asset image
                imageBackgroundWithAsset(imageName: imageName)
            } else {
                // Standard gradient background (fallback)
                fallbackGradientBackground
            }
            
            // Dark overlay for secondary mode
            if presentationMode == .secondary {
                Color.black.opacity(presentationMode.darkOverlayOpacity)
            }
        }
    }
    
    // MARK: - Image Background with URL (Pre-Recorded)
    
    @ViewBuilder
    private func imageBackgroundWithURL(url: URL) -> some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1: Background image from URL (aspect fill, clipped to frame)
                KFImage(url)
                    .placeholder {
                        fallbackGradientBackground
                    }
                    .onFailure { _ in }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                
                // Layer 2: Smooth gradient overlay for text readability
                smoothTextReadabilityGradient(width: geometry.size.width)
            }
        }
    }
    
    // MARK: - Image Background with Asset (Custom/Path)
    
    @ViewBuilder
    private func imageBackgroundWithAsset(imageName: String) -> some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1: Background image (aspect fill, clipped to frame)
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                
                // Layer 2: Smooth gradient overlay for text readability
                smoothTextReadabilityGradient(width: geometry.size.width)
            }
        }
    }
    
    // MARK: - Smooth Text Readability Gradient
    
    /// Creates a smooth, gradual horizontal gradient for text readability over images
    /// Transitions: Darkest (left) >> Bright (middle) >> Clear (right)
    @ViewBuilder
    private func smoothTextReadabilityGradient(width: CGFloat) -> some View {
        let darkColor = Color(red: 0.08, green: 0.08, blue: 0.14)
        
        HStack(spacing: 0) {
            LinearGradient(
                stops: [
                    // Darkest zone (solid coverage for text)
                    Gradient.Stop(color: darkColor.opacity(0.98), location: 0.00),
                    Gradient.Stop(color: darkColor.opacity(0.95), location: 0.15),
                    // Transition to bright zone (gradual fade)
                    Gradient.Stop(color: darkColor.opacity(0.85), location: 0.30),
                    Gradient.Stop(color: darkColor.opacity(0.70), location: 0.45),
                    // Bright zone (semi-transparent)
                    Gradient.Stop(color: darkColor.opacity(0.50), location: 0.58),
                    Gradient.Stop(color: darkColor.opacity(0.30), location: 0.70),
                    // Fade to clear (smooth exit)
                    Gradient.Stop(color: darkColor.opacity(0.12), location: 0.82),
                    Gradient.Stop(color: darkColor.opacity(0.00), location: 1.00),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.70)
            
            Spacer()
        }
    }
    
    // MARK: - Fallback Gradient Background
    
    @ViewBuilder
    private var fallbackGradientBackground: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.00),
                Gradient.Stop(color: Color(red: 0.08, green: 0.08, blue: 0.14), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
        .opacity(0.95)
    }
}

// MARK: - Preview

#if DEBUG
struct RecommendationCardShell_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundNavy.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Primary Path card shell
                RecommendationCardShell(
                    presentationMode: .primary,
                    contentType: .path,
                    accentColor: .textTurquoise,
                    onTap: {}
                ) {
                    Text("Primary Path Card")
                        .foregroundColor(.white)
                        .padding()
                        .frame(height: 174)
                }
                
                // Secondary card shell
                RecommendationCardShell(
                    presentationMode: .secondary,
                    contentType: .path,
                    accentColor: .textTurquoise,
                    onTap: {}
                ) {
                    Text("Secondary Card")
                        .foregroundColor(.white)
                        .padding()
                        .frame(height: 107)
                }
                
                // Primary Custom card shell
                RecommendationCardShell(
                    presentationMode: .primary,
                    contentType: .custom,
                    accentColor: .textTurquoise,
                    onTap: {}
                ) {
                    Text("Primary Custom Card")
                        .foregroundColor(.white)
                        .padding()
                        .frame(height: 174)
                }
            }
            .padding()
        }
    }
}
#endif
