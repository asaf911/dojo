//
//  HurdleScreenContent.swift
//  imagine
//
//  Created by Cursor on 1/16/26.
//
//  Dynamic content configuration for HurdleScreen based on selected goal.
//  All copy is centralized here for easy editing and optimization.
//

import Foundation

// MARK: - Hurdle Screen Content

/// Dynamic content for HurdleScreen based on selected goal
struct HurdleScreenContent {
    let title: String
    let subtitle: String
    let question: String
    let options: [HurdleOption]
    let ctaText: String

    /// A selectable hurdle option (goal-specific)
    struct HurdleOption: Identifiable, Hashable, Codable {
        let id: String           // For analytics & storage (e.g., "mind_wont_slow_down")
        let displayName: String  // UI text (e.g., "My mind keeps racing")
    }
}

// MARK: - Goal to Hurdle Content Mapping

extension OnboardingGoal {

    /// Returns the hurdle screen content for this goal
    var hurdleScreenContent: HurdleScreenContent {
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

extension HurdleScreenContent {

    // ═══════════════════════════════════════════════════════════════════
    // RELAXATION
    // ═══════════════════════════════════════════════════════════════════

    static let relaxation = HurdleScreenContent(
        title: "What blocks your relaxation?",
        subtitle: "We start here.",
        question: "Choose one:",
        options: [
            HurdleOption(id: "mind_wont_slow_down", displayName: "My mind won’t slow down"),
            HurdleOption(id: "body_stays_tense", displayName: "My body stays tense"),
            HurdleOption(id: "emotions_stay_active", displayName: "My emotions stay active"),
            HurdleOption(id: "dont_know_start", displayName: "I don’t know where to start")
        ],
        ctaText: "Start training"
    )

    // ═══════════════════════════════════════════════════════════════════
    // SPIRITUAL GROWTH
    // ═══════════════════════════════════════════════════════════════════

    static let spiritualGrowth = HurdleScreenContent(
        title: "What limits your inner growth?",
        subtitle: "We start here.",
        question: "Choose one:",
        options: [
            HurdleOption(id: "feel_disconnected", displayName: "I feel disconnected"),
            HurdleOption(id: "overthink_everything", displayName: "I overthink everything"),
            HurdleOption(id: "lack_clarity", displayName: "I lack clarity"),
            HurdleOption(id: "dont_know_start", displayName: "I don’t know where to begin")
        ],
        ctaText: "Start training"
    )

    // ═══════════════════════════════════════════════════════════════════
    // BETTER SLEEP
    // ═══════════════════════════════════════════════════════════════════

    static let betterSleep = HurdleScreenContent(
        title: "What disrupts your sleep?",
        subtitle: "We start here.",
        question: "Choose one:",
        options: [
            HurdleOption(id: "cant_fall_asleep", displayName: "I can’t fall asleep"),
            HurdleOption(id: "wake_up_at_night", displayName: "I wake up at night"),
            HurdleOption(id: "mind_keeps_racing", displayName: "My mind keeps racing"),
            HurdleOption(id: "dont_know_start", displayName: "I don’t know how to improve it")
        ],
        ctaText: "Start training"
    )

    // ═══════════════════════════════════════════════════════════════════
    // SHARPEN FOCUS
    // ═══════════════════════════════════════════════════════════════════

    static let focus = HurdleScreenContent(
        title: "What breaks your focus?",
        subtitle: "We start here.",
        question: "Choose one:",
        options: [
            HurdleOption(id: "mind_jumps_constantly", displayName: "My mind jumps constantly"),
            HurdleOption(id: "cant_focus_deeply", displayName: "I can’t focus deeply"),
            HurdleOption(id: "mind_too_noisy", displayName: "My mind is too noisy"),
            HurdleOption(id: "dont_know_start", displayName: "I don’t know how to train it")
        ],
        ctaText: "Start training"
    )

    // ═══════════════════════════════════════════════════════════════════
    // VISUALIZATION
    // ═══════════════════════════════════════════════════════════════════

    static let visualization = HurdleScreenContent(
        title: "What weakens your imagery?",
        subtitle: "We start here.",
        question: "Choose one:",
        options: [
            HurdleOption(id: "cant_see_internal_images", displayName: "I can’t see internal images"),
            HurdleOption(id: "images_not_stable", displayName: "Images won’t stay stable"),
            HurdleOption(id: "dont_know_use_imagery", displayName: "I don’t know how to use imagery"),
            HurdleOption(id: "dont_know_start", displayName: "I don’t know where to start")
        ],
        ctaText: "Start training"
    )

    // ═══════════════════════════════════════════════════════════════════
    // BOOST ENERGY
    // ═══════════════════════════════════════════════════════════════════

    static let energy = HurdleScreenContent(
        title: "What drains your energy?",
        subtitle: "We start here.",
        question: "Choose one:",
        options: [
            HurdleOption(id: "mental_fatigue", displayName: "Mental fatigue"),
            HurdleOption(id: "body_feels_tired", displayName: "My body feels tired"),
            HurdleOption(id: "no_drive", displayName: "I have no drive"),
            HurdleOption(id: "dont_know_start", displayName: "I don’t know how to manage it")
        ],
        ctaText: "Start training"
    )
}
