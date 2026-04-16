//
//  HurdleRecommendationContext.swift
//  imagine
//
//  Maps each onboarding hurdle ID to a set of audio tags (for biasing
//  Explore session selection) and an AI prompt seed (injected into the
//  custom meditation prompt for hurdle-targeted content).
//
//  Usage:
//  - Read when ``DualRecommendationOrchestrator`` builds ``RecommendationContext``
//  - Threaded into custom-meditation prompts (Explore catalog is Library-only for suggestions).
//  - Pass to MessageContext for personalized intro messages
//
//  Hurdle IDs mirror HurdleScreenContent.HurdleOption.id from onboarding.
//  Logging is intentionally absent here — this is a pure data type.
//  Log at the call site (orchestrator) where context is consumed.
//

import Foundation

// MARK: - Hurdle Recommendation Context

/// Maps an onboarding hurdle to content-selection signals for the recommendation system.
struct HurdleRecommendationContext {

    /// The hurdle ID as stored in UserPreferences (e.g. "mind_wont_slow_down")
    let hurdleId: String

    /// Audio file tags to prefer when selecting Explore sessions.
    /// Matched case-insensitively against AudioFile.tags.
    /// Empty means no tag-based preference — fall back to time-only selection.
    let audioTags: [String]

    /// Short phrase injected into the custom meditation AI prompt.
    /// Gives the AI a clear anchor for the user's pain point.
    let aiPromptSeed: String

    // MARK: - Lookup

    /// Returns the context for a given hurdle ID, or nil if not found or ID is nil.
    static func context(for hurdleId: String?) -> HurdleRecommendationContext? {
        guard let id = hurdleId else { return nil }
        return all[id]
    }

    // MARK: - Mapping Table

    // audioTags must match tags already present on AudioFile objects in Firebase.
    // Current known time tags: "morning", "noon", "evening", "sleep"
    // Known content tags (add more as the library grows): "calm", "relax", "focus", "grounding"
    private static let all: [String: HurdleRecommendationContext] = [

        // ── Relaxation goal ──────────────────────────────────────────────────
        "mind_wont_slow_down": HurdleRecommendationContext(
            hurdleId: "mind_wont_slow_down",
            audioTags: ["calm"],
            aiPromptSeed: "settle a racing mind and reduce mental speed"
        ),
        "body_stays_tense": HurdleRecommendationContext(
            hurdleId: "body_stays_tense",
            audioTags: ["relax"],
            aiPromptSeed: "release physical tension from the body"
        ),
        "emotions_stay_active": HurdleRecommendationContext(
            hurdleId: "emotions_stay_active",
            audioTags: ["calm"],
            aiPromptSeed: "regulate emotional intensity and find steadiness"
        ),

        // ── Spiritual growth goal ────────────────────────────────────────────
        "feel_disconnected": HurdleRecommendationContext(
            hurdleId: "feel_disconnected",
            audioTags: ["grounding"],
            aiPromptSeed: "reconnect with yourself on a deeper level"
        ),
        "overthink_everything": HurdleRecommendationContext(
            hurdleId: "overthink_everything",
            audioTags: ["calm"],
            aiPromptSeed: "step out of mental loops and overthinking"
        ),
        "lack_clarity": HurdleRecommendationContext(
            hurdleId: "lack_clarity",
            audioTags: ["grounding"],
            aiPromptSeed: "think with precision and gain clarity"
        ),
        "dont_know_start": HurdleRecommendationContext(
            hurdleId: "dont_know_start",
            audioTags: [],
            aiPromptSeed: "a gentle introduction to meditation"
        ),

        // ── Better sleep goal ─────────────────────────────────────────────────
        "cant_fall_asleep": HurdleRecommendationContext(
            hurdleId: "cant_fall_asleep",
            audioTags: ["sleep"],
            aiPromptSeed: "ease the mind and body into sleep"
        ),
        "wake_up_at_night": HurdleRecommendationContext(
            hurdleId: "wake_up_at_night",
            audioTags: ["sleep"],
            aiPromptSeed: "return to deep, uninterrupted sleep"
        ),
        "mind_keeps_racing": HurdleRecommendationContext(
            hurdleId: "mind_keeps_racing",
            audioTags: ["sleep", "calm"],
            aiPromptSeed: "quiet a busy mind before sleep"
        ),

        // ── Focus goal ────────────────────────────────────────────────────────
        "mind_jumps_constantly": HurdleRecommendationContext(
            hurdleId: "mind_jumps_constantly",
            audioTags: ["focus"],
            aiPromptSeed: "gather scattered thoughts into one clear focus"
        ),
        "cant_focus_deeply": HurdleRecommendationContext(
            hurdleId: "cant_focus_deeply",
            audioTags: ["focus"],
            aiPromptSeed: "sustain deep focus and hold attention longer"
        ),
        "mind_too_noisy": HurdleRecommendationContext(
            hurdleId: "mind_too_noisy",
            audioTags: ["focus"],
            aiPromptSeed: "clear distraction and reduce mental noise"
        ),

        // ── Visualization goal ────────────────────────────────────────────────
        "cant_see_internal_images": HurdleRecommendationContext(
            hurdleId: "cant_see_internal_images",
            audioTags: [],
            aiPromptSeed: "build vivid, detailed mental imagery"
        ),
        "images_not_stable": HurdleRecommendationContext(
            hurdleId: "images_not_stable",
            audioTags: ["focus"],
            aiPromptSeed: "hold mental images steady and stable"
        ),
        "dont_know_use_imagery": HurdleRecommendationContext(
            hurdleId: "dont_know_use_imagery",
            audioTags: [],
            aiPromptSeed: "learn how to use imagery correctly"
        ),

        // ── Energy goal ───────────────────────────────────────────────────────
        "mental_fatigue": HurdleRecommendationContext(
            hurdleId: "mental_fatigue",
            audioTags: ["calm"],
            aiPromptSeed: "restore depleted mental energy"
        ),
        "body_feels_tired": HurdleRecommendationContext(
            hurdleId: "body_feels_tired",
            audioTags: ["relax"],
            aiPromptSeed: "restore balance and rebuild vitality"
        ),
        "no_drive": HurdleRecommendationContext(
            hurdleId: "no_drive",
            audioTags: [],
            aiPromptSeed: "reconnect with motivation and inner drive"
        ),
    ]
}
