//
//  GoalContext.swift
//  imagine
//
//  Canonical goal contexts for the Adaptive Context Evolution Layer.
//  Maps to HurdleRecommendationContext for compatibility with the
//  existing RecommendationContextEngine.
//

import Foundation

// MARK: - Goal Context

/// Canonical goal types used by the Context State ranking system.
/// Aligned with HurdleRecommendationContext audio tags and prompt seeds.
enum GoalContext: String, Codable, CaseIterable {

    case sleep      // Better sleep goal
    case calm       // Mind racing, restless, overthinking, overwhelm
    case focus     // Attention, distraction, presence
    case relax     // Body tension, letting go
    case energy    // Exhaustion, motivation, overwhelm
    case grounding // Disconnection, doubt, imagery
    case general   // Fallback; Path, introduction
}

// MARK: - Mapping to HurdleRecommendationContext

extension GoalContext {

    /// Returns a synthetic HurdleRecommendationContext for engine compatibility.
    var asHurdleContext: HurdleRecommendationContext {
        let (tags, seed) = Self.tagAndSeedMapping[self] ?? ([], "a gentle meditation")
        return HurdleRecommendationContext(
            hurdleId: "goal_\(rawValue)",
            audioTags: tags,
            aiPromptSeed: seed
        )
    }

    private static let tagAndSeedMapping: [GoalContext: (audioTags: [String], aiPromptSeed: String)] = [
        .sleep:    (["sleep"], "ease the mind and body into sleep"),
        .calm:     (["calm"], "settle a racing mind"),
        .focus:    (["focus"], "gather scattered thoughts into one clear focus"),
        .relax:    (["relax"], "release physical tension from the body"),
        .energy:   (["calm"], "restore depleted mental energy"),
        .grounding: (["grounding"], "reconnect with yourself on a deeper level"),
        .general:  ([], "a gentle introduction to meditation")
    ]
}

// MARK: - Derivation from Onboarding

extension GoalContext {

    /// Maps onboarding hurdle ID to GoalContext.
    static func from(hurdleId: String?) -> GoalContext {
        guard let id = hurdleId else { return .general }
        return hurdleToGoalMapping[id] ?? .general
    }

    private static let hurdleToGoalMapping: [String: GoalContext] = [
        "mind_wont_slow_down": .calm,
        "body_stays_tense": .relax,
        "emotions_stay_active": .calm,
        "feel_disconnected": .grounding,
        "overthink_everything": .calm,
        "lack_clarity": .grounding,
        "dont_know_start": .general,
        "cant_fall_asleep": .sleep,
        "wake_up_at_night": .sleep,
        "mind_keeps_racing": .sleep,
        "mind_jumps_constantly": .focus,
        "cant_focus_deeply": .focus,
        "mind_too_noisy": .focus,
        "cant_see_internal_images": .general,
        "images_not_stable": .general,
        "dont_know_use_imagery": .general,
        "mental_fatigue": .energy,
        "body_feels_tired": .relax,
        "no_drive": .energy
    ]
}

// MARK: - Derivation from Session Tags

extension GoalContext {

    /// Infers GoalContext from Explore session tags.
    /// Uses first matching tag; empty or unknown tags return .general.
    static func from(sessionTags: [String]) -> GoalContext {
        let tagsLower = sessionTags.map { $0.lowercased() }
        if tagsLower.contains("sleep") { return .sleep }
        if tagsLower.contains("calm") { return .calm }
        if tagsLower.contains("focus") { return .focus }
        if tagsLower.contains("relax") { return .relax }
        if tagsLower.contains("grounding") { return .grounding }
        return .general
    }
}
