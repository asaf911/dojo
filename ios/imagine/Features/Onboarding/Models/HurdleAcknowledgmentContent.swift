//
//  HurdleAcknowledgmentContent.swift
//  imagine
//
//  Created by Cursor on 2/5/26.
//
//  Dynamic content configuration for HurdleAcknowledgmentScreen based on selected hurdle.
//  All copy is centralized here for easy editing and optimization.
//

import Foundation

// MARK: - Hurdle Acknowledgment Content

/// Dynamic content for HurdleAcknowledgmentScreen based on selected hurdle
struct HurdleAcknowledgmentContent {
    let title: String              // Header title
    let acknowledgmentText: String // Main body text
    let ctaText: String            // Button text
}

// MARK: - Hurdle Option to Acknowledgment Content Mapping

extension HurdleScreenContent.HurdleOption {

    /// Returns the acknowledgment screen content for this hurdle option
    var acknowledgmentContent: HurdleAcknowledgmentContent {
        switch id {

        // ═══════════════════════════════════════════════════════════════════
        // RELAXATION HURDLES
        // ═══════════════════════════════════════════════════════════════════
        case "mind_wont_slow_down":
            return .mindWontSlowDown
        case "body_stays_tense":
            return .bodyStaysTense
        case "emotions_stay_active":
            return .emotionsStayActive

        // ═══════════════════════════════════════════════════════════════════
        // SPIRITUAL GROWTH HURDLES
        // ═══════════════════════════════════════════════════════════════════
        case "feel_disconnected":
            return .feelDisconnected
        case "overthink_everything":
            return .overthinkEverything
        case "lack_clarity":
            return .lackClarity

        // ═══════════════════════════════════════════════════════════════════
        // BETTER SLEEP HURDLES
        // ═══════════════════════════════════════════════════════════════════
        case "cant_fall_asleep":
            return .cantFallAsleep
        case "wake_up_at_night":
            return .wakeUpAtNight
        case "mind_keeps_racing":
            return .mindKeepsRacing

        // ═══════════════════════════════════════════════════════════════════
        // FOCUS HURDLES
        // ═══════════════════════════════════════════════════════════════════
        case "mind_jumps_constantly":
            return .mindJumpsConstantly
        case "cant_focus_deeply":
            return .cantFocusDeeply
        case "mind_too_noisy":
            return .mindTooNoisy

        // ═══════════════════════════════════════════════════════════════════
        // VISUALIZATION HURDLES
        // ═══════════════════════════════════════════════════════════════════
        case "cant_see_internal_images":
            return .cantSeeInternalImages
        case "images_not_stable":
            return .imagesNotStable
        case "dont_know_use_imagery":
            return .dontKnowUseImagery

        // ═══════════════════════════════════════════════════════════════════
        // ENERGY HURDLES
        // ═══════════════════════════════════════════════════════════════════
        case "mental_fatigue":
            return .mentalFatigue
        case "body_feels_tired":
            return .bodyFeelsTired
        case "no_drive":
            return .noDrive

        // ═══════════════════════════════════════════════════════════════════
        // SHARED / STRUCTURED PATH
        // ═══════════════════════════════════════════════════════════════════
        case "dont_know_start":
            return .dontKnowStart

        default:
            return .default
        }
    }
}

// MARK: - Content Definitions (Easy to Edit)

extension HurdleAcknowledgmentContent {

    // ═══════════════════════════════════════════════════════════════════
    // DEFAULT (fallback)
    // ═══════════════════════════════════════════════════════════════════

    static let `default` = HurdleAcknowledgmentContent(
        title: "You will move forward",
        acknowledgmentText: "This is where progress begins.",
        ctaText: "Continue"
    )

    // ═══════════════════════════════════════════════════════════════════
    // RELAXATION HURDLES
    // ═══════════════════════════════════════════════════════════════════

    static let mindWontSlowDown = HurdleAcknowledgmentContent(
        title: "You will slow your mind",
        acknowledgmentText: "You will learn how to reduce mental speed. This is your first focus.",
        ctaText: "Continue"
    )

    static let bodyStaysTense = HurdleAcknowledgmentContent(
        title: "You will release tension",
        acknowledgmentText: "You will learn how to relax your body on command. We begin here.",
        ctaText: "Continue"
    )

    static let emotionsStayActive = HurdleAcknowledgmentContent(
        title: "You will steady your emotions",
        acknowledgmentText: "You will learn how to regulate emotional intensity. This comes first.",
        ctaText: "Continue"
    )

    // ═══════════════════════════════════════════════════════════════════
    // SPIRITUAL GROWTH HURDLES
    // ═══════════════════════════════════════════════════════════════════

    static let feelDisconnected = HurdleAcknowledgmentContent(
        title: "You will reconnect inward",
        acknowledgmentText: "You will learn how to rebuild inner clarity. This is the starting point.",
        ctaText: "Continue"
    )

    static let overthinkEverything = HurdleAcknowledgmentContent(
        title: "You will break overthinking",
        acknowledgmentText: "You will learn how to step out of mental loops. We address this first.",
        ctaText: "Continue"
    )

    static let lackClarity = HurdleAcknowledgmentContent(
        title: "You will gain clarity",
        acknowledgmentText: "You will learn how to think with precision. This is where we begin.",
        ctaText: "Continue"
    )

    // ═══════════════════════════════════════════════════════════════════
    // BETTER SLEEP HURDLES
    // ═══════════════════════════════════════════════════════════════════

    static let cantFallAsleep = HurdleAcknowledgmentContent(
        title: "You will fall asleep easier",
        acknowledgmentText: "You will learn how to transition into rest. This is step one.",
        ctaText: "Continue"
    )

    static let wakeUpAtNight = HurdleAcknowledgmentContent(
        title: "You will sleep more deeply",
        acknowledgmentText: "You will learn how to stabilize your sleep. We start here.",
        ctaText: "Continue"
    )

    static let mindKeepsRacing = HurdleAcknowledgmentContent(
        title: "You will quiet your mind",
        acknowledgmentText: "You will learn how to slow racing thoughts. This is your foundation.",
        ctaText: "Continue"
    )

    // ═══════════════════════════════════════════════════════════════════
    // FOCUS HURDLES
    // ═══════════════════════════════════════════════════════════════════

    static let mindJumpsConstantly = HurdleAcknowledgmentContent(
        title: "You will strengthen focus",
        acknowledgmentText: "You will learn how to hold attention longer. This is the first shift.",
        ctaText: "Continue"
    )

    static let cantFocusDeeply = HurdleAcknowledgmentContent(
        title: "You will build depth",
        acknowledgmentText: "You will learn how to sustain deep focus. This comes first.",
        ctaText: "Continue"
    )

    static let mindTooNoisy = HurdleAcknowledgmentContent(
        title: "You will reduce mental noise",
        acknowledgmentText: "You will learn how to clear distraction. We begin with this.",
        ctaText: "Continue"
    )

    // ═══════════════════════════════════════════════════════════════════
    // VISUALIZATION HURDLES
    // ═══════════════════════════════════════════════════════════════════

    static let cantSeeInternalImages = HurdleAcknowledgmentContent(
        title: "You will develop imagery",
        acknowledgmentText: "You will learn how to see internally with clarity. This is the base.",
        ctaText: "Continue"
    )

    static let imagesNotStable = HurdleAcknowledgmentContent(
        title: "You will stabilize imagery",
        acknowledgmentText: "You will learn how to hold images steady. We build from here.",
        ctaText: "Continue"
    )

    static let dontKnowUseImagery = HurdleAcknowledgmentContent(
        title: "You will learn the method",
        acknowledgmentText: "You will learn how to use imagery correctly. This is where it begins.",
        ctaText: "Continue"
    )

    // ═══════════════════════════════════════════════════════════════════
    // ENERGY HURDLES
    // ═══════════════════════════════════════════════════════════════════

    static let mentalFatigue = HurdleAcknowledgmentContent(
        title: "You will restore energy",
        acknowledgmentText: "You will learn how to reduce mental drain. This is the first change.",
        ctaText: "Continue"
    )

    static let bodyFeelsTired = HurdleAcknowledgmentContent(
        title: "You will rebuild vitality",
        acknowledgmentText: "You will learn how to restore balance. We begin here.",
        ctaText: "Continue"
    )

    static let noDrive = HurdleAcknowledgmentContent(
        title: "You will regain momentum",
        acknowledgmentText: "You will learn how to reconnect with motivation. This is step one.",
        ctaText: "Continue"
    )

    // ═══════════════════════════════════════════════════════════════════
    // STRUCTURED PATH (shared)
    // ═══════════════════════════════════════════════════════════════════

    static let dontKnowStart = HurdleAcknowledgmentContent(
        title: "You will have direction",
        acknowledgmentText: "You will follow a structured path built for you.",
        ctaText: "Continue"
    )
}
