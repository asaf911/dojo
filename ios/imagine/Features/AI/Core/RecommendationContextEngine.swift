//
//  RecommendationContextEngine.swift
//  imagine
//
//  Session selection service for Sensei recommendations (custom meditations; Path is separate).
//  Responsible for one thing: given a role and context, return the most
//  appropriate session. Whether that session is Explore or Custom is an
//  implementation detail — the caller only cares about the result.
//
//  Three selection roles (Sensei suggestions are **custom meditations only**; Path
//  recommendations come from PathProgressManager, not this engine. Pre-recorded Explore
//  sessions are discovered in Library — not suggested here.)
//
//  selectContextual    — Personal Mode primary: always Custom.
//
//  selectContrast      — Personal Mode secondary (legacy dual): Custom variants only.
//
//  selectComplementary — Learn Mode secondary (legacy dual): Custom only.
//

import Foundation

// MARK: - Recommendation Context

/// All signals available at recommendation time, packaged once at the
/// orchestrator level and threaded through the selection functions.
struct RecommendationContext {
    let timeOfDay: ExploreRecommendationManager.TimeOfDay
    let hurdleContext: HurdleRecommendationContext?
    let excludedContentIds: Set<String>

    /// Greeting resolved once by the orchestrator, attached to the item
    /// built by the first selection call (primary).
    let welcomeGreeting: String?
    let contextMessage: String?
    let isFirstWelcome: Bool

    /// Onboarding goal raw value (e.g. "relaxation", "better_sleep") for first custom meditation.
    let goal: String?

    /// When true, the next Custom meditation is the user's first — use goal + hurdle in prompt.
    let isFirstCustomMeditation: Bool

    /// When true: first-ever recommendation on Personal track.
    /// Primary = 5 min (faster time-to-value), Secondary = 10 min.
    /// Only affects Custom-generated sessions; Explore keeps catalog duration.
    let isFirstPersonalRecommendation: Bool

    init(
        timeOfDay: ExploreRecommendationManager.TimeOfDay = .current(),
        hurdleContext: HurdleRecommendationContext? = nil,
        excludedContentIds: Set<String> = [],
        welcomeGreeting: String? = nil,
        contextMessage: String? = nil,
        isFirstWelcome: Bool = false,
        goal: String? = nil,
        isFirstCustomMeditation: Bool = false,
        isFirstPersonalRecommendation: Bool = false
    ) {
        self.timeOfDay = timeOfDay
        self.hurdleContext = hurdleContext
        self.excludedContentIds = excludedContentIds
        self.welcomeGreeting = welcomeGreeting
        self.contextMessage = contextMessage
        self.isFirstWelcome = isFirstWelcome
        self.goal = goal
        self.isFirstCustomMeditation = isFirstCustomMeditation
        self.isFirstPersonalRecommendation = isFirstPersonalRecommendation
    }
}

// MARK: - Recommendation Context Engine

/// Session selection service. Struct of closures — swap `.live` for `.preview`
/// in tests or previews without changing any call sites.
struct RecommendationContextEngine {

    /// Personal Mode primary: best contextual session for the user right now.
    var selectContextual: @MainActor (_ context: RecommendationContext) async -> RecommendationItem?

    /// Personal Mode secondary: contrasting session relative to the primary.
    var selectContrast: @MainActor (_ context: RecommendationContext, _ primaryType: RecommendationType) async -> RecommendationItem?

    /// Learn Mode secondary: session that complements a Path primary.
    var selectComplementary: @MainActor (_ context: RecommendationContext) async -> RecommendationItem?
}

// MARK: - Live Implementation

extension RecommendationContextEngine {

    @MainActor static let live: RecommendationContextEngine = {
        let messageService = RecommendationMessageService.shared

        // Technique lenses diversify custom meditation prompts so consecutive
        // calls with the same hurdle produce distinctly named sessions.
        let lenses: [String] = [
            "using breath awareness",
            "using a body scan",
            "using visualisation and imagery",
            "using gentle affirmations",
            "using open awareness",
            "using mindful stillness",
            "using grounding techniques",
            "using loving-kindness"
        ]

        // MARK: Shared helpers

        func timeTheme(for timeOfDay: ExploreRecommendationManager.TimeOfDay) -> String {
            switch timeOfDay {
            case .morning: return "energizing morning"
            case .noon:    return "focus reset"
            case .evening: return "evening wind-down"
            case .night:   return "calming sleep"
            }
        }

        func buildCustomPrompt(duration: Int, context: RecommendationContext) -> String {
            if context.timeOfDay == .morning {
                return MorningTimelyMeditationPrompt.buildCreatePrompt(
                    duration: duration,
                    context: context
                )
            }

            let lens = lenses.randomElement() ?? lenses[0]

            if context.isFirstCustomMeditation {
                // First custom meditation: use goal + hurdle for personalization
                let seed = context.hurdleContext?.aiPromptSeed
                let goalDisplay = context.goal.flatMap { OnboardingGoal(rawValue: $0)?.displayName.lowercased() }

                var parts: [String] = []
                if let seed = seed, !seed.isEmpty {
                    parts.append("to help \(seed)")
                }
                if let goalDisplay = goalDisplay, !goalDisplay.isEmpty {
                    parts.append("focused on \(goalDisplay)")
                }

                if !parts.isEmpty {
                    return "Create a \(duration)-minute meditation \(lens) \(parts.joined(separator: ", "))"
                }
            }

            // Subsequent custom meditations: existing logic (hurdle or time theme)
            if let seed = context.hurdleContext?.aiPromptSeed, !seed.isEmpty {
                return "Create a \(duration)-minute meditation \(lens) to help \(seed)"
            }
            return "Create a \(duration)-minute \(timeTheme(for: context.timeOfDay)) meditation"
        }

        func generateCustom(duration: Int, context: RecommendationContext) async -> AITimerResponse? {
            let prompt = buildCustomPrompt(duration: duration, context: context)
            logger.aiChat("🎯 CTX_ENGINE: generating custom prompt='\(prompt)'")
            let aiContext = AIServerRequestContext(
                pathInfo: nil,
                exploreInfo: nil,
                lastMeditationDuration: nil,
                recentBackgroundSounds: nil,
                meditationThemes: context.timeOfDay.senseiMeditationThemeTags,
                blueprintId: context.timeOfDay.senseiMeditationBlueprintId.rawValue
            )
            do {
                let response = try await AIRequestService.shared.processAIRequest(
                    prompt: prompt,
                    conversationHistory: [],
                    context: aiContext,
                    triggerContext: "RecommendationContextEngine|generateCustom"
                )
                if case .meditation(let package) = response.content {
                    let timerResponse = package.toAITimerResponse()
                    logger.aiChat("🎯 CTX_ENGINE: ✅ custom generated duration=\(timerResponse.meditationConfiguration.duration)min")
                    return timerResponse
                }
                logger.aiChat("🎯 CTX_ENGINE: conversational response instead of meditation — skipping")
            } catch {
                logger.errorMessage("🎯 CTX_ENGINE: custom generation failed — \(error.localizedDescription)")
            }
            return nil
        }

        // MARK: selectContextual

        let selectContextual: @MainActor (_ context: RecommendationContext) async -> RecommendationItem? = { context in
            let timeOfDayName = context.timeOfDay.displayName

            // Personal track: Sensei suggests custom meditations only (Explore lives in Library).
            logger.aiChat("🎯 CTX_ENGINE [CONTEXTUAL]: Custom primary (Explore not offered in Sensei)")
            let primaryDuration = context.isFirstPersonalRecommendation ? 5 : 10
            guard let custom = await generateCustom(duration: primaryDuration, context: context) else {
                logger.aiChat("🎯 CTX_ENGINE [CONTEXTUAL]: Custom generation failed")
                return nil
            }
            let message: String
            if context.contextMessage != nil {
                message = ""  // Context replaces intro on first welcome — skip API call
            } else {
                message = await messageService.generateCustomOnlyPrimary(
                    timeOfDay: timeOfDayName,
                    meditationDurationMinutes: primaryDuration
                )
            }
            return RecommendationItem(
                type: .custom(custom),
                introMessage: message,
                welcomeGreeting: context.welcomeGreeting,
                isFirstWelcome: context.isFirstWelcome,
                contextMessage: context.contextMessage
            )
        }

        // MARK: selectContrast

        let selectContrast: @MainActor (_ context: RecommendationContext, _ primaryType: RecommendationType) async -> RecommendationItem? = { context, primaryType in
            let timeOfDayName = context.timeOfDay.displayName

            switch primaryType {

            case .explore:
                // Primary was structured → secondary should lean generated.
                logger.aiChat("🎯 CTX_ENGINE [CONTRAST]: Primary=Explore → generating Custom secondary")
                guard let custom = await generateCustom(duration: 10, context: context) else { return nil }
                let message = await messageService.generateCustomSecondaryAlt(timeOfDay: timeOfDayName)
                return RecommendationItem(type: .custom(custom), introMessage: message)

            case .custom, .path:
                // Primary was Custom or Path → secondary is Custom only (no Explore in Sensei).
                let secondaryDuration = context.isFirstPersonalRecommendation ? 10 : 5
                logger.aiChat("🎯 CTX_ENGINE [CONTRAST]: Primary=Custom|Path → \(secondaryDuration)-min Custom secondary")
                guard let shortCustom = await generateCustom(duration: secondaryDuration, context: context) else { return nil }
                let shortMessage = await messageService.generateCustomSecondary(duration: secondaryDuration, timeOfDay: timeOfDayName)
                return RecommendationItem(type: .custom(shortCustom), introMessage: shortMessage)
            }
        }

        // MARK: selectComplementary

        let selectComplementary: @MainActor (_ context: RecommendationContext) async -> RecommendationItem? = { context in
            let timeOfDayName = context.timeOfDay.displayName

            // Learn track secondary: Custom only (Path primary is separate; Explore in Library).
            logger.aiChat("🎯 CTX_ENGINE [COMPLEMENTARY]: Custom secondary (Explore not offered in Sensei)")
            guard let custom = await generateCustom(duration: 10, context: context) else { return nil }
            let message = await messageService.generateCustomSecondaryAlt(timeOfDay: timeOfDayName)
            return RecommendationItem(type: .custom(custom), introMessage: message)
        }

        return RecommendationContextEngine(
            selectContextual:    selectContextual,
            selectContrast:      selectContrast,
            selectComplementary: selectComplementary
        )
    }()
}

// MARK: - Preview Implementation

extension RecommendationContextEngine {

    /// Deterministic, offline-safe implementation for SwiftUI previews.
    /// Returns nil for all roles — callers should render their empty state.
    static let preview = RecommendationContextEngine(
        selectContextual:    { _ in nil },
        selectContrast:      { _, _ in nil },
        selectComplementary: { _ in nil }
    )
}
