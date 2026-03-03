//
//  RecommendationCardPreviews.swift
//  imagine
//
//  Preview catalog for all RecommendationCard permutations and combinations.
//  Shows all content types (Path, PreRecorded, Custom) in all states
//  (Default, Selected, Deselected, Completed) for Primary and Secondary cards.
//

import SwiftUI

#if DEBUG

// MARK: - Complete State Catalog

/// Master preview showing ALL card states organized by content type
struct RecommendationCardCatalog_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 40) {
                // Path cards
                pathCardsSection
                
                sectionDivider
                
                // Pre-recorded cards
                preRecordedCardsSection
                
                sectionDivider
                
                // Custom cards
                customCardsSection
            }
            .padding()
        }
        .background(Color.backgroundNavy.ignoresSafeArea())
        .previewDisplayName("All States Catalog")
    }
    
    // MARK: - Path Cards Section
    
    @ViewBuilder
    static var pathCardsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("PATH")
            
            // Primary cards
            cardTypeHeader("Primary")
            
            stateLabel("Default")
            PrimaryRecommendationCard(
                content: PreviewMeditationContent.pathIncomplete,
                onPlay: {},
                isCompleted: false
            )
            
            stateLabel("Deselected (secondary was tapped)")
            PrimaryRecommendationCard(
                content: PreviewMeditationContent.pathIncomplete,
                onPlay: {},
                isCompleted: false,
                isDeselected: true
            )
            
            stateLabel("Completed")
            PrimaryRecommendationCard(
                content: PreviewMeditationContent.pathCompleted,
                onPlay: {},
                isCompleted: true
            )
            
            // Secondary cards
            cardTypeHeader("Secondary")
            
            stateLabel("Default")
            SecondaryRecommendationCard(
                content: PreviewMeditationContent.pathIncomplete,
                onPlay: {},
                isCompleted: false
            )
            
            stateLabel("Deselected (primary was tapped)")
            SecondaryRecommendationCard(
                content: PreviewMeditationContent.pathIncomplete,
                onPlay: {},
                isCompleted: false,
                isDeselected: true
            )
            
            stateLabel("Completed")
            SecondaryRecommendationCard(
                content: PreviewMeditationContent.pathCompleted,
                onPlay: {},
                isCompleted: true
            )
        }
    }
    
    // MARK: - Pre-recorded Cards Section
    
    @ViewBuilder
    static var preRecordedCardsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("PRE-RECORDED")
            
            // Primary cards
            cardTypeHeader("Primary")
            
            stateLabel("Default")
            PrimaryRecommendationCard(
                content: PreviewMeditationContent.preRecorded,
                onPlay: {},
                isCompleted: false
            )
            
            stateLabel("Deselected (secondary was tapped)")
            PrimaryRecommendationCard(
                content: PreviewMeditationContent.preRecorded,
                onPlay: {},
                isCompleted: false,
                isDeselected: true
            )
            
            stateLabel("Completed")
            PrimaryRecommendationCard(
                content: PreviewMeditationContent.preRecorded,
                onPlay: {},
                isCompleted: true
            )
            
            // Secondary cards
            cardTypeHeader("Secondary")
            
            stateLabel("Default")
            SecondaryRecommendationCard(
                content: PreviewMeditationContent.preRecorded,
                onPlay: {},
                isCompleted: false
            )
            
            stateLabel("Deselected (primary was tapped)")
            SecondaryRecommendationCard(
                content: PreviewMeditationContent.preRecorded,
                onPlay: {},
                isCompleted: false,
                isDeselected: true
            )
            
            stateLabel("Completed")
            SecondaryRecommendationCard(
                content: PreviewMeditationContent.preRecorded,
                onPlay: {},
                isCompleted: true
            )
        }
    }
    
    // MARK: - Custom Cards Section
    
    @ViewBuilder
    static var customCardsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("CUSTOM")
            
            // Primary cards
            cardTypeHeader("Primary")
            
            stateLabel("Default")
            PrimaryRecommendationCard(
                content: PreviewMeditationContent.custom,
                onPlay: {},
                isCompleted: false
            )
            
            stateLabel("Deselected (secondary was tapped)")
            PrimaryRecommendationCard(
                content: PreviewMeditationContent.custom,
                onPlay: {},
                isCompleted: false,
                isDeselected: true
            )
            
            stateLabel("Completed")
            PrimaryRecommendationCard(
                content: PreviewMeditationContent.custom,
                onPlay: {},
                isCompleted: true
            )
            
            // Secondary cards
            cardTypeHeader("Secondary")
            
            stateLabel("Default")
            SecondaryRecommendationCard(
                content: PreviewMeditationContent.custom,
                onPlay: {},
                isCompleted: false
            )
            
            stateLabel("Deselected (primary was tapped)")
            SecondaryRecommendationCard(
                content: PreviewMeditationContent.custom,
                onPlay: {},
                isCompleted: false,
                isDeselected: true
            )
            
            stateLabel("Completed")
            SecondaryRecommendationCard(
                content: PreviewMeditationContent.custom,
                onPlay: {},
                isCompleted: true
            )
        }
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    static func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.textPurple)
            .tracking(2)
    }
    
    @ViewBuilder
    static func cardTypeHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white.opacity(0.7))
            .padding(.top, 8)
    }
    
    @ViewBuilder
    static func stateLabel(_ text: String) -> some View {
        Text(text)
            .font(Font.custom("Nunito", size: 11).weight(.medium))
            .foregroundColor(.textTurquoise.opacity(0.8))
            .padding(.top, 4)
    }
    
    @ViewBuilder
    static var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
            .padding(.horizontal)
    }
}

// MARK: - Primary Cards All States

struct PrimaryCardsAllStates_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("PRIMARY CARDS - ALL STATES")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1.5)
                
                Group {
                    stateGroup("Path") {
                        stateLabel("Default")
                        PrimaryRecommendationCard(
                            content: PreviewMeditationContent.pathIncomplete,
                            onPlay: {}
                        )
                        stateLabel("Deselected")
                        PrimaryRecommendationCard(
                            content: PreviewMeditationContent.pathIncomplete,
                            onPlay: {},
                            isDeselected: true
                        )
                        stateLabel("Completed")
                        PrimaryRecommendationCard(
                            content: PreviewMeditationContent.pathCompleted,
                            onPlay: {},
                            isCompleted: true
                        )
                    }
                    
                    stateGroup("Pre-recorded") {
                        stateLabel("Default")
                        PrimaryRecommendationCard(
                            content: PreviewMeditationContent.preRecorded,
                            onPlay: {}
                        )
                        stateLabel("Deselected")
                        PrimaryRecommendationCard(
                            content: PreviewMeditationContent.preRecorded,
                            onPlay: {},
                            isDeselected: true
                        )
                        stateLabel("Completed")
                        PrimaryRecommendationCard(
                            content: PreviewMeditationContent.preRecorded,
                            onPlay: {},
                            isCompleted: true
                        )
                    }
                    
                    stateGroup("Custom") {
                        stateLabel("Default")
                        PrimaryRecommendationCard(
                            content: PreviewMeditationContent.custom,
                            onPlay: {}
                        )
                        stateLabel("Deselected")
                        PrimaryRecommendationCard(
                            content: PreviewMeditationContent.custom,
                            onPlay: {},
                            isDeselected: true
                        )
                        stateLabel("Completed")
                        PrimaryRecommendationCard(
                            content: PreviewMeditationContent.custom,
                            onPlay: {},
                            isCompleted: true
                        )
                    }
                }
            }
            .padding()
        }
        .background(Color.backgroundNavy.ignoresSafeArea())
        .previewDisplayName("Primary Cards - All States")
    }
    
    @ViewBuilder
    static func stateGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPurple)
                .padding(.top, 12)
            content()
        }
    }
    
    @ViewBuilder
    static func stateLabel(_ text: String) -> some View {
        Text(text)
            .font(Font.custom("Nunito", size: 11).weight(.medium))
            .foregroundColor(.textTurquoise.opacity(0.8))
            .padding(.top, 4)
    }
}

// MARK: - Secondary Cards All States

struct SecondaryCardsAllStates_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("SECONDARY CARDS - ALL STATES")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1.5)
                
                Group {
                    stateGroup("Path") {
                        stateLabel("Default")
                        SecondaryRecommendationCard(
                            content: PreviewMeditationContent.pathIncomplete,
                            onPlay: {}
                        )
                        stateLabel("Deselected")
                        SecondaryRecommendationCard(
                            content: PreviewMeditationContent.pathIncomplete,
                            onPlay: {},
                            isDeselected: true
                        )
                        stateLabel("Completed")
                        SecondaryRecommendationCard(
                            content: PreviewMeditationContent.pathCompleted,
                            onPlay: {},
                            isCompleted: true
                        )
                    }
                    
                    stateGroup("Pre-recorded") {
                        stateLabel("Default")
                        SecondaryRecommendationCard(
                            content: PreviewMeditationContent.preRecorded,
                            onPlay: {}
                        )
                        stateLabel("Deselected")
                        SecondaryRecommendationCard(
                            content: PreviewMeditationContent.preRecorded,
                            onPlay: {},
                            isDeselected: true
                        )
                        stateLabel("Completed")
                        SecondaryRecommendationCard(
                            content: PreviewMeditationContent.preRecorded,
                            onPlay: {},
                            isCompleted: true
                        )
                    }
                    
                    stateGroup("Custom") {
                        stateLabel("Default")
                        SecondaryRecommendationCard(
                            content: PreviewMeditationContent.custom,
                            onPlay: {}
                        )
                        stateLabel("Deselected")
                        SecondaryRecommendationCard(
                            content: PreviewMeditationContent.custom,
                            onPlay: {},
                            isDeselected: true
                        )
                        stateLabel("Completed")
                        SecondaryRecommendationCard(
                            content: PreviewMeditationContent.custom,
                            onPlay: {},
                            isCompleted: true
                        )
                    }
                }
            }
            .padding()
        }
        .background(Color.backgroundNavy.ignoresSafeArea())
        .previewDisplayName("Secondary Cards - All States")
    }
    
    @ViewBuilder
    static func stateGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPurple)
                .padding(.top, 12)
            content()
        }
    }
    
    @ViewBuilder
    static func stateLabel(_ text: String) -> some View {
        Text(text)
            .font(Font.custom("Nunito", size: 11).weight(.medium))
            .foregroundColor(.textTurquoise.opacity(0.8))
            .padding(.top, 4)
    }
}

// MARK: - Interactive Selection Demo

/// Interactive demo showing selection behavior between primary and secondary cards
struct InteractiveSelectionDemo_Previews: PreviewProvider {
    static var previews: some View {
        InteractiveSelectionDemoView()
            .previewDisplayName("Interactive Selection Demo")
    }
}

struct InteractiveSelectionDemoView: View {
    @State private var secondarySelected: Bool? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("TAP CARDS TO SEE SELECTION")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1.5)
                
                Text("Selected: \(selectedDescription)")
                    .font(Font.custom("Nunito", size: 12))
                    .foregroundColor(.textTurquoise)
                
                VStack(spacing: 12) {
                    Text("Path")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPurple)
                    
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.pathIncomplete,
                        onPlay: {},
                        isDeselected: secondarySelected == true,
                        onSelect: { secondarySelected = false }
                    )
                    
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.preRecorded,
                        onPlay: {},
                        onSelect: { secondarySelected = true },
                        isDeselected: secondarySelected == false
                    )
                }
                
                Button("Reset") {
                    secondarySelected = nil
                }
                .font(Font.custom("Nunito", size: 14).weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.textPurple.opacity(0.5))
                .cornerRadius(8)
            }
            .padding()
        }
        .background(Color.backgroundNavy.ignoresSafeArea())
    }
    
    private var selectedDescription: String {
        switch secondarySelected {
        case nil: return "None"
        case true: return "Secondary"
        case false: return "Primary"
        }
    }
}

// MARK: - Side by Side Comparison

struct CardComparison_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("PRIMARY vs SECONDARY")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(1.5)
                
                // Path
                comparisonGroup(title: "Path - Default") {
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.pathIncomplete,
                        onPlay: {}
                    )
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.pathIncomplete,
                        onPlay: {}
                    )
                }
                
                comparisonGroup(title: "Path - Completed") {
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.pathCompleted,
                        onPlay: {},
                        isCompleted: true
                    )
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.pathCompleted,
                        onPlay: {},
                        isCompleted: true
                    )
                }
                
                // Pre-recorded
                comparisonGroup(title: "Pre-recorded - Default") {
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.preRecorded,
                        onPlay: {}
                    )
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.preRecorded,
                        onPlay: {}
                    )
                }
                
                comparisonGroup(title: "Pre-recorded - Completed") {
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.preRecorded,
                        onPlay: {},
                        isCompleted: true
                    )
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.preRecorded,
                        onPlay: {},
                        isCompleted: true
                    )
                }
                
                // Custom
                comparisonGroup(title: "Custom - Default") {
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.custom,
                        onPlay: {}
                    )
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.custom,
                        onPlay: {}
                    )
                }
                
                comparisonGroup(title: "Custom - Completed") {
                    PrimaryRecommendationCard(
                        content: PreviewMeditationContent.custom,
                        onPlay: {},
                        isCompleted: true
                    )
                    SecondaryRecommendationCard(
                        content: PreviewMeditationContent.custom,
                        onPlay: {},
                        isCompleted: true
                    )
                }
            }
            .padding()
        }
        .background(Color.backgroundNavy.ignoresSafeArea())
        .previewDisplayName("Side by Side")
    }
    
    @ViewBuilder
    static func comparisonGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Font.custom("Nunito", size: 12).weight(.semibold))
                .foregroundColor(.textTurquoise)
            content()
        }
    }
}

#endif
