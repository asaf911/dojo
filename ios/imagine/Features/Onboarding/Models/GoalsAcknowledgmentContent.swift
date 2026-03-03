//
//  GoalsAcknowledgmentContent.swift
//  imagine
//
//  Created by Cursor on 2/5/26.
//
//  Dynamic content configuration for GoalsAcknowledgmentScreen based on selected goal.
//  All copy is centralized here for easy editing and optimization.
//

import Foundation

// MARK: - Goals Acknowledgment Content

/// Dynamic content for GoalsAcknowledgmentScreen based on selected goal
struct GoalsAcknowledgmentContent {
    let title: String              // Header title (e.g., "Great choice")
    let acknowledgmentText: String // Main body text with statistic/benefit
    let ctaText: String            // Button text
}

// MARK: - Goal to Acknowledgment Content Mapping

extension OnboardingGoal {
    
    /// Returns the acknowledgment screen content for this goal
    var acknowledgmentContent: GoalsAcknowledgmentContent {
        switch self {
        case .relaxation:
            return .relaxation
        case .spiritualGrowth:
            return .spiritualGrowth
        case .betterSleep:
            return .betterSleep
        case .focus:
            return .focus
        case .visualization:
            return .visualization
        case .energy:
            return .energy
        }
    }
}

// MARK: - Content Definitions (Easy to Edit)

extension GoalsAcknowledgmentContent {
    
    // ═══════════════════════════════════════════════════════════════════
    // RELAXATION
    // ═══════════════════════════════════════════════════════════════════
    
    static let relaxation = GoalsAcknowledgmentContent(
        title: "Relaxation is trainable",
        acknowledgmentText: "You will relax your body, mind, and emotions faster.",
        ctaText: "Continue"
    )
    
    // ═══════════════════════════════════════════════════════════════════
    // SPIRITUAL GROWTH
    // ═══════════════════════════════════════════════════════════════════
    
    static let spiritualGrowth = GoalsAcknowledgmentContent(
        title: "Training deeper awareness",
        acknowledgmentText: "You will see more clearly and remove inner blockages.",
        ctaText: "Continue"
    )
    
    // ═══════════════════════════════════════════════════════════════════
    // BETTER SLEEP
    // ═══════════════════════════════════════════════════════════════════
    
    static let betterSleep = GoalsAcknowledgmentContent(
        title: "Training better sleep",
        acknowledgmentText: "You will learn to fall asleep faster and sleep more deeply.",
        ctaText: "Continue"
    )
    
    // ═══════════════════════════════════════════════════════════════════
    // SHARPEN FOCUS
    // ═══════════════════════════════════════════════════════════════════
    
    static let focus = GoalsAcknowledgmentContent(
        title: "Attention strengthens",
        acknowledgmentText: "You will strengthen attention and hold focus longer.",
        ctaText: "Continue"
    )
    
    // ═══════════════════════════════════════════════════════════════════
    // VISUALIZATION
    // ═══════════════════════════════════════════════════════════════════
    
    static let visualization = GoalsAcknowledgmentContent(
        title: "Stabilizing imagery",
        acknowledgmentText: "You will develop clearer, more stable internal imagery.",
        ctaText: "Continue"
    )
    
    // ═══════════════════════════════════════════════════════════════════
    // BOOST ENERGY
    // ═══════════════════════════════════════════════════════════════════
    
    static let energy = GoalsAcknowledgmentContent(
        title: "Managing your energy",
        acknowledgmentText: "You will harness and manage your energy with control.",
        ctaText: "Continue"
    )
}
