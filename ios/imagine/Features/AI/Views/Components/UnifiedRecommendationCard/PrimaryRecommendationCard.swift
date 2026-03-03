//
//  PrimaryRecommendationCard.swift
//  imagine
//
//  Created for Clean Recommendation Card Architecture
//
//  Full-featured primary recommendation card with all details and controls.
//  Supports Path, PreRecorded, and Custom meditation types.
//

import SwiftUI

// MARK: - Title Width Preference Key

/// Preference key for measuring title text width
private struct TitleWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Primary Recommendation Card

/// Full-featured card for primary recommendations
/// Shows complete header, description, and full controls
struct PrimaryRecommendationCard: View {
    let content: MeditationContent
    let onPlay: () -> Void
    
    // For path cards - completion state
    var isCompleted: Bool = false
    
    // For dual recommendations - deselected when secondary is tapped
    var isDeselected: Bool = false
    
    // Callback when card is selected (for deselecting secondary card)
    var onSelect: (() -> Void)? = nil
    
    // MARK: - Computed Properties
    
    private var accentColor: Color {
        // All content types use purple accent when completed
        if isCompleted {
            return content.contentType.completedAccentColor
        }
        return content.contentType.accentColor
    }
    
    /// Title color - gray when deselected, accent color otherwise
    private var titleColor: Color {
        isDeselected ? Color("ColorTextSecondary") : accentColor
    }
    
    // Fixed height for all primary cards
    private let primaryCardHeight: CGFloat = 174
    
    // MARK: - Body
    
    var body: some View {
        RecommendationCardShell(
            presentationMode: .primary,
            contentType: content.contentType,
            accentColor: accentColor,
            onTap: { handleTap() },
            isCompleted: isCompleted,
            isDeselected: isDeselected,
            backgroundImageURL: content.backgroundImageURL
        ) {
            if content.contentType.isSessionType {
                // Session cards (Custom & PreRecorded): unified image background layout
                sessionCardContent
            } else {
                // Path cards: standard layout
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    
                    Spacer(minLength: 0)
                    
                    controlsSection
                }
                .padding(20)
                .frame(height: primaryCardHeight)
            }
        }
    }
    
    // MARK: - Session Card Content (Custom & PreRecorded)
    
    // State to track measured title width
    @State private var measuredTitleWidth: CGFloat = 0
    
    @ViewBuilder
    private var sessionCardContent: some View {
        GeometryReader { geometry in
            let minWidth = geometry.size.width * 0.50
            let maxWidth = geometry.size.width * 0.75
            // Content width is determined by title, clamped between min and max
            let contentWidth = max(minWidth, min(measuredTitleWidth, maxWidth))
            
            ZStack {
                // Hidden title to measure full intrinsic width
                Text(content.contentTitle)
                    .font(Font.custom("Nunito", size: 16).weight(.heavy))
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)
                    .background(
                        GeometryReader { titleGeometry in
                            Color.clear
                                .preference(key: TitleWidthPreferenceKey.self, value: titleGeometry.size.width)
                        }
                    )
                    .hidden()
                
                // Main content aligned top-leading
                VStack(alignment: .leading, spacing: 0) {
                    // Title - always single line
                    Text(content.contentTitle)
                        .font(Font.custom("Nunito", size: 16).weight(.heavy))
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .animation(.easeOut(duration: 0.25), value: isDeselected)
                    
                    // Description (truncated to 3 lines, constrained to title-determined width)
                    Text(content.contentDescription)
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(.foregroundLightGray)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(.top, 4)
                    
                    Spacer(minLength: 8)
                    
                    // Duration badge
                    CardDurationBadge(minutes: content.durationMinutes, style: .capsule)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
                
                // Play button or completed indicator at bottom-right corner
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if isCompleted {
                            completedIndicator
                        } else {
                            CardPlayButton(style: .filled, onPlay: handleTap)
                        }
                    }
                }
                .padding(20)
            }
            .onPreferenceChange(TitleWidthPreferenceKey.self) { width in
                measuredTitleWidth = width
            }
        }
        .frame(height: primaryCardHeight)
    }
    
    // MARK: - Header Section (Path cards only)
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Primary • Secondary label row
            HStack(spacing: 0) {
                Text(content.primaryLabel)
                    .font(Font.custom("Nunito", size: 16).weight(.semibold))
                
                if let secondary = content.secondaryLabel {
                    Text(" • \(secondary)")
                        .font(Font.custom("Nunito", size: 16).weight(.heavy))
                }
                
                Spacer()
            }
            .foregroundColor(.foregroundLightGray)
            
            // Title
            Text(content.contentTitle)
                .font(Font.custom("Nunito", size: 16).weight(.semibold))
                .foregroundColor(titleColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: 0.25), value: isDeselected)
            
            // Type • Duration (for path cards)
            Text(content.metadataText)
                .font(Font.custom("Nunito", size: 14).italic())
                .foregroundColor(.foregroundLightGray)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Controls Section (Path cards only)
    
    @ViewBuilder
    private var controlsSection: some View {
        HStack(spacing: 12) {
            Spacer()
            
            if isCompleted {
                // Completed indicator replaces play button
                completedIndicator
            } else {
                // Play button at right bottom corner
                CardPlayButton(style: .filled, onPlay: handleTap)
            }
        }
    }
    
    // MARK: - Tap Handler
    
    private func handleTap() {
        // Notify parent that primary was selected (to deselect secondary)
        onSelect?()
        
        // Delay onPlay until animation completes (matches secondary card behavior)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onPlay()
        }
    }
    
    // MARK: - Subviews
    
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
}

// MARK: - Preview

#if DEBUG
struct PrimaryRecommendationCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundNavy.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    Text("Primary Cards")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    // Path card (incomplete)
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.pathIncomplete,
                        onPlay: {},
                        isCompleted: false
                    )
                    
                    // Path card (completed)
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.pathCompleted,
                        onPlay: {},
                        isCompleted: true
                    )
                    
                    // Session card (PreRecorded)
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.preRecorded,
                        onPlay: {}
                    )
                    
                    // Session card (Custom)
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.custom,
                        onPlay: {}
                    )
                }
                .padding()
            }
        }
    }
}
#endif
