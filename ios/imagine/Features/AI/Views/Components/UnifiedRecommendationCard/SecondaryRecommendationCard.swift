//
//  SecondaryRecommendationCard.swift
//  imagine
//
//  Created for Clean Recommendation Card Architecture
//
//  Compact secondary recommendation card with dark overlay.
//  Provides an alternative option that visually recedes behind the primary.
//  Height: 107pt with minimal controls (more button only).
//

import SwiftUI

// MARK: - Secondary Recommendation Card

/// Compact card for secondary recommendations
/// Dark overlay makes it visually recede, emphasizing the primary option
struct SecondaryRecommendationCard: View {
    let content: MeditationContent
    let onPlay: () -> Void
    
    // For path cards - completion state
    var isCompleted: Bool = false
    
    // Callback when card is selected (for deselecting primary card)
    var onSelect: (() -> Void)? = nil
    
    // External deselection (when primary is tapped after secondary was selected)
    var isDeselected: Bool = false
    
    // MARK: - State
    
    /// Selected state - triggered on tap before navigation
    @State private var isSelected: Bool = false
    
    // MARK: - Constants
    
    private let cardHeight: CGFloat = 107
    
    // MARK: - Computed Properties
    
    private var accentColor: Color {
        // All content types use purple accent when completed
        if isCompleted {
            return content.contentType.completedAccentColor
        }
        return content.contentType.accentColor
    }
    
    /// Effective selected state - internal selection but can be overridden by external deselection
    private var effectivelySelected: Bool {
        isSelected && !isDeselected
    }
    
    /// Text color for headers - turquoise when selected, gray otherwise
    private var headerTextColor: Color {
        effectivelySelected ? accentColor : Color("ColorTextSecondary")
    }
    
    // MARK: - Body
    
    var body: some View {
        RecommendationCardShell(
            presentationMode: .secondary,
            contentType: content.contentType,
            accentColor: accentColor,
            onTap: { handleCardTap() },
            isCompleted: isCompleted,
            isSelected: effectivelySelected,
            backgroundImageURL: content.backgroundImageURL
        ) {
            if content.contentType == .path {
                // Path cards: same structure as primary path cards
                pathCardContent
            } else {
                // Session cards (PreRecorded & Custom)
                sessionCardContent
            }
        }
    }
    
    // MARK: - Tap Handlers
    
    /// Called when card body is tapped (via shell) - provides haptic
    private func handleCardTap() {
        HapticManager.shared.impact(.medium)
        triggerSelection()
    }
    
    /// Called when play button is tapped (button provides its own haptic)
    private func handleButtonTap() {
        triggerSelection()
    }
    
    /// Shared selection logic - animates and delays navigation
    private func triggerSelection() {
        // Notify parent that secondary was selected (to deselect primary)
        onSelect?()
        
        withAnimation(.easeOut(duration: 0.25)) {
            isSelected = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onPlay()
        }
    }
    
    // MARK: - Path Card Content
    
    @ViewBuilder
    private var pathCardContent: some View {
        ZStack {
            // Text content - vertically centered
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Step X • The Path
                    HStack(spacing: 0) {
                        Text(content.primaryLabel)
                            .font(Font.custom("Nunito", size: 16).weight(.semibold))
                        
                        if let secondary = content.secondaryLabel {
                            Text(" • \(secondary)")
                                .font(Font.custom("Nunito", size: 16).weight(.heavy))
                        }
                    }
                    .foregroundColor(headerTextColor)
                    .animation(.easeOut(duration: 0.25), value: effectivelySelected)
                    
                    // Title
                    Text(content.contentTitle)
                        .font(Font.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundColor(isCompleted ? accentColor : headerTextColor)
                        .lineLimit(1)
                        .animation(.easeOut(duration: 0.25), value: effectivelySelected)
                    
                    // Lesson/Practice • X min
                    Text(content.metadataText)
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(Color("ColorTextTertiary"))
                }
                
                Spacer()
            }
            
            // Play button / Completed indicator - bottom right corner
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if isCompleted {
                        completedIndicator
                    } else {
                        CardPlayButton(style: .filled, onPlay: handleButtonTap)
                    }
                }
            }
        }
        .padding(20)
        .frame(height: cardHeight)
    }
    
    // MARK: - Completed Indicator
    
    /// Completed indicator - purple checkmark button
    @ViewBuilder
    private var completedIndicator: some View {
        ZStack {
            Circle()
                .frame(width: 32, height: 32)
                .foregroundColor(.textPurple)
                .shadow(color: .black.opacity(0.32), radius: 3, x: 0, y: 4)
            
            Image("pathCheckmark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        }
    }
    
    // MARK: - Session Card Content (PreRecorded & Custom)
    
    @ViewBuilder
    private var sessionCardContent: some View {
        ZStack {
            // Text content - vertically centered
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Title row
                    Text(content.contentTitle)
                        .font(Font.custom("Nunito", size: 16).weight(.heavy))
                        .foregroundColor(headerTextColor)
                        .lineLimit(1)
                        .animation(.easeOut(duration: 0.25), value: effectivelySelected)
                    
                    // Description row (single line, truncated)
                    Text(content.contentDescription)
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(Color("ColorTextTertiary"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    // Duration
                    Text(content.durationText)
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(Color("ColorTextTertiary"))
                }
                // Reserve space for play button (32pt) + 8pt gap
                .padding(.trailing, 40)
                
                Spacer(minLength: 0)
            }
            
            // Play button or completed indicator - bottom right corner
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if isCompleted {
                        completedIndicator
                    } else {
                        CardPlayButton(style: .filled, onPlay: handleButtonTap)
                    }
                }
            }
        }
        .padding(20)
        .frame(height: cardHeight)
    }
}

// MARK: - Preview

#if DEBUG
struct SecondaryRecommendationCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundNavy.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    Text("Secondary Cards (107pt)")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Tap any card to see selected state")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    
                    // Path card (incomplete)
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.pathIncomplete,
                        onPlay: {},
                        isCompleted: false
                    )
                    
                    // Path card (completed)
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.pathCompleted,
                        onPlay: {},
                        isCompleted: true
                    )
                    
                    // Session card (PreRecorded)
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.preRecorded,
                        onPlay: {}
                    )
                    
                    // Session card (Custom)
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.custom,
                        onPlay: {}
                    )
                }
                .padding()
            }
        }
    }
}

/// Preview wrapper to demonstrate the selected state comparison
struct SecondaryCardSelectedState_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundNavy.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Text("Selected State Comparison")
                    .font(.headline)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Normal (tap to select)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.preRecorded,
                        onPlay: {}
                    )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Primary (reference)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.preRecorded,
                        onPlay: {}
                    )
                }
            }
            .padding()
        }
        .previewDisplayName("Selected State")
    }
}
#endif
