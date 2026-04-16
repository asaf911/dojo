//
//  MorningTimelyMeditationPrompt.swift
//  imagine
//
//  Canonical instructions for Sensei-generated **morning** custom meditations
//  (timely / contextual). Other times of day stay in RecommendationContextEngine.
//

import Foundation

// MARK: - Morning custom “Create a … meditation” prompt

/// Builds the user-facing generation prompt for morning custom meditations so the
/// model follows a consistent arc: intro → breathwork → body scan → visualization.
///
/// **Server pairing:** the timely morning slot sends `SenseiMeditationBlueprintID.timelyMorning`
/// (`"timely.morning"`) on `AIServerRequestContext.blueprintId` so structure, cues, and
/// `audioHints` stay aligned with `functions/src/meditationBlueprints.ts`.
enum MorningTimelyMeditationPrompt {

    // MARK: - Theme permutations

    /// Rotating “Morning …” tones so repeat sessions feel varied but stay on-brief.
    private static let themeVariants: [String] = [
        "Overall tone: Morning clarity—bright, steady attention for starting the day.",
        "Overall tone: Sunrise awakening—gentle build of energy and openness.",
        "Overall tone: Fresh start—clear mind, grounded body, optimistic pacing.",
        "Overall tone: Morning ground—steady breath first, then light expansion into the day.",
        "Overall tone: Dawn focus—quiet intention, then alert, kind awareness.",
        "Overall tone: Morning horizon—spacious imagery and unhurried breath."
    ]

    /// Product default for timely / Sensei morning customs unless the user explicitly asks
    /// for a different structure in their own chat message (not applicable to this auto prompt).
    private static let titleAndScriptNamingRules = """
    Title and wording: Pick a short session title that fits morning energy (light, clarity, dawn, fresh start). Do not use sleep, goodnight, “last thoughts,” fading into dreams, or heavy night imagery in the title or script.
    """
    .trimmingCharacters(in: .whitespacesAndNewlines)

    /// Mandatory blueprint — do not open with a competing modality (e.g. “using visualization…”)
    /// or models collapse the arc into one technique.
    private static func blueprintInstructions(for duration: Int) -> String {
        switch duration {
        case 10:
            return """
            MANDATORY BLUEPRINT — follow in this exact order; do not skip, reorder, or merge segments:
            (1) Intro — brief spoken welcome to the day and intention only (~1 minute).
            (2) Breathwork — guided breath practice only (~3 minutes); keep it breath-centered, not visualization yet.
            (3) Body scan — light, awakening body scan only (~3 minutes); do not replace this block with visualization.
            (4) Morning visualization — energizing imagery only (~4 minutes): sunrise, open sky, warm light expanding, horizon—never sleep hypnosis, heavy tiredness, or “drift to sleep” cues.
            Do not add a separate mantra, chanting, or repeated-syllable focus block; keep attention on breath, body, then guided imagery.
            Total ~10 minutes. Use clear verbal handoffs between segments; concise language so timing fits.
            """
            .trimmingCharacters(in: .whitespacesAndNewlines)
        case 5:
            return """
            MANDATORY BLUEPRINT — same four-part order as the 10-minute morning product, condensed to ~5 minutes total:
            (1) Intro — very short welcome + intention only.
            (2) Breathwork — guided breath only (~1–1.5 minutes).
            (3) Body scan — awakening scan only (~1–1.5 minutes); not visualization.
            (4) Morning visualization — short energizing imagery (~2 minutes); no sleep hypnosis.
            Keep clear transitions; energizing morning feel throughout.
            """
            .trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return """
            MANDATORY BLUEPRINT — same four-part order: Intro → Breathwork → Body scan → Morning visualization, split evenly across ~\(duration) minutes. Breathwork and body scan must each be their own spoken blocks (not folded into visualization). Morning visualization stays energizing (sunrise, sky, warm light)—never sleep hypnosis.
            """
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func variantIndex(for context: RecommendationContext) -> Int {
        let cal = Calendar.current
        let now = Date()
        let day = cal.component(.day, from: now)
        let month = cal.component(.month, from: now)
        let hurdle = context.hurdleContext?.hurdleId ?? ""
        let first = context.isFirstCustomMeditation ? "1" : "0"
        let seed = "\(month)-\(day)-\(hurdle)-\(first)-\(context.isFirstPersonalRecommendation)"
        let h = abs(seed.hashValue)
        guard !themeVariants.isEmpty else { return 0 }
        return h % themeVariants.count
    }

    private static func themeLine(for context: RecommendationContext) -> String {
        themeVariants[variantIndex(for: context)]
    }

    /// Full “Create a …” prompt for `processAIRequest` when `timeOfDay` is morning.
    static func buildCreatePrompt(
        duration: Int,
        context: RecommendationContext
    ) -> String {
        let blueprint = blueprintInstructions(for: duration)
        let theme = themeLine(for: context)
        let tail = "\(blueprint) \(titleAndScriptNamingRules) \(theme)"

        if context.isFirstCustomMeditation {
            let seed = context.hurdleContext?.aiPromptSeed
            let goalDisplay = context.goal.flatMap { OnboardingGoal(rawValue: $0)?.displayName.lowercased() }

            var parts: [String] = []
            if let seed, !seed.isEmpty {
                parts.append("to help \(seed)")
            }
            if let goalDisplay, !goalDisplay.isEmpty {
                parts.append("focused on \(goalDisplay)")
            }

            if !parts.isEmpty {
                return "Create a \(duration)-minute personalized morning meditation \(parts.joined(separator: ", ")). \(tail)"
            }
        }

        if let seed = context.hurdleContext?.aiPromptSeed, !seed.isEmpty {
            return "Create a \(duration)-minute morning meditation to help \(seed). \(tail)"
        }

        return "Create a \(duration)-minute morning meditation. \(tail)"
    }
}
