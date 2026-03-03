//
//  LegacyCardWrappers.swift
//  imagine
//
//  Wrapper views that adapt the legacy card interfaces to the new unified card system.
//  These maintain backward compatibility with existing code that uses the old card view names.
//

import SwiftUI

// MARK: - AI Path Recommendation Card View

/// Wrapper for path recommendations using the unified card system
struct AIPathRecommendationCardView: View {
    let pathStep: PathStep
    let onPlay: (PathStep) -> Void
    var isSecondary: Bool = false
    var isDeselected: Bool = false  // For cards in dual recommendations
    var onSelect: (() -> Void)? = nil  // For cards to notify parent of selection
    
    /// Check completion using PracticeManager directly (not @MainActor isolated)
    private var isCompleted: Bool {
        PracticeManager.shared.isPracticeCompleted(practiceID: pathStep.id)
    }
    
    var body: some View {
        let adapter = PathContentAdapter.create(from: pathStep, isCompleted: isCompleted)
        
        if isSecondary {
            SecondaryRecommendationCard(
                content: adapter,
                onPlay: { onPlay(pathStep) },
                isCompleted: isCompleted,
                onSelect: onSelect,
                isDeselected: isDeselected
            )
        } else {
            PrimaryRecommendationCard(
                content: adapter,
                onPlay: { onPlay(pathStep) },
                isCompleted: isCompleted,
                isDeselected: isDeselected,
                onSelect: onSelect
            )
        }
    }
}

// MARK: - AI Explore Recommendation Card View

/// Wrapper for explore/pre-recorded recommendations using the unified card system
struct AIExploreRecommendationCardView: View {
    let audioFile: AudioFile
    let onPlay: (AudioFile) -> Void
    var isCompleted: Bool = false  // Instance-scoped completion from parent
    var isSecondary: Bool = false
    var isDeselected: Bool = false  // For cards in dual recommendations
    var onSelect: (() -> Void)? = nil  // For cards to notify parent of selection
    
    var body: some View {
        let adapter = PreRecordedContentAdapter(audioFile: audioFile)
        
        if isSecondary {
            SecondaryRecommendationCard(
                content: adapter,
                onPlay: { onPlay(audioFile) },
                isCompleted: isCompleted,
                onSelect: onSelect,
                isDeselected: isDeselected
            )
        } else {
            PrimaryRecommendationCard(
                content: adapter,
                onPlay: { onPlay(audioFile) },
                isCompleted: isCompleted,
                isDeselected: isDeselected,
                onSelect: onSelect
            )
        }
    }
}

// MARK: - AI Custom Meditation Card View

/// Wrapper for custom AI-generated meditation recommendations using the unified card system
struct AICustomMeditationCardView: View {
    let meditation: AITimerResponse
    let onPlay: (AITimerResponse) -> Void
    var isCompleted: Bool = false  // Instance-scoped completion from parent
    var isSecondary: Bool = false
    var isDeselected: Bool = false  // For cards in dual recommendations
    var onSelect: (() -> Void)? = nil  // For cards to notify parent of selection
    
    var body: some View {
        let adapter = CustomContentAdapter(aiResponse: meditation)
        
        if isSecondary {
            SecondaryRecommendationCard(
                content: adapter,
                onPlay: { onPlay(meditation) },
                isCompleted: isCompleted,
                onSelect: onSelect,
                isDeselected: isDeselected
            )
        } else {
            PrimaryRecommendationCard(
                content: adapter,
                onPlay: { onPlay(meditation) },
                isCompleted: isCompleted,
                isDeselected: isDeselected,
                onSelect: onSelect
            )
        }
    }
}
