//
//  DualRecommendationOrchestrator.swift
//  imagine
//
//  Central coordinator for Sensei recommendations in AI chat.
//  Implements a four-step decision framework; Step 4 (secondary) is legacy-only.
//
//  Step 1 — Determine UserMode (learn | personal)
//  Step 2 — Build RecommendationContext (time, hurdle, greeting, excluded IDs)
//  Step 3 — Select Primary  (mode-specific role)
//  Step 4 — Select Secondary (deprecated: learn = complementary, personal = contrast)
//
//  Personal-mode primary is custom via RecommendationContextEngine, with Explore-backed
//  fallback in this class when generation yields no session.
//  Path selection uses PathProgressManager directly in this class.
//

import Foundation
import Combine

// MARK: - Dual Recommendation Orchestrator

/// Coordinates Sensei recommendation selection for AI chat (Path + custom meditations;
/// pre-recorded Daily Routines are used only as a fallback when custom generation fails).
///
/// The product path is a **single** recommendation; the legacy dual-card API remains
/// for compatibility but is deprecated.
@MainActor
class DualRecommendationOrchestrator: ObservableObject {

    // MARK: - Singleton

    static let shared = DualRecommendationOrchestrator()

    // MARK: - Dependencies

    private let journeyManager  = ProductJourneyManager.shared
    private let pathManager     = PathProgressManager.shared
    private let messageService  = RecommendationMessageService.shared
    private let contextEngine   = RecommendationContextEngine.live

    // MARK: - Published State

    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var lastRecommendation: SingleRecommendation?

    // MARK: - Deduplication

    /// Content IDs recently recommended. Excludes Path steps (sequential by design).
    /// Not persisted — resets on app launch, which is intentional.
    private var recentlyRecommendedIds: Set<String> = []

    // MARK: - Initialization

    private init() {
        logger.aiChat("🎯 DUAL_REC: DualRecommendationOrchestrator initialized")
    }

    // MARK: - Main Entry Point

    /// Returns one Sensei recommendation for the current journey state.
    ///
    /// - Parameter includeGreeting: When true, prepends a timely greeting
    ///   (e.g. "Good evening, Asaf."). Pass false for post-session and
    ///   transition-triggered calls.
    func getSingleRecommendation(includeGreeting: Bool = false) async -> SingleRecommendation? {
        isGenerating = true
        defer { isGenerating = false }

        guard let built = await buildRecommendationCore(includeSecondary: false, includeGreeting: includeGreeting) else {
            return nil
        }

        let result = SingleRecommendation(
            item: built.primary,
            userMode: built.userMode,
            currentPhase: built.currentPhase,
            routineProgress: built.routineProgress
        )

        if !built.primary.isPath {
            recentlyRecommendedIds.insert(built.primary.contentId)
        }

        lastRecommendation = result
        let primaryGoal = inferGoalFromPrimary(built.primary)
        ContextStateManager.shared.recordPrimaryShown(goalContext: primaryGoal)

        if built.primary.isCustom {
            SharedUserStorage.save(value: true, forKey: .hasReceivedFirstCustomMeditation)
        }

        logger.aiChat("🎯 DUAL_REC: Done (single) — recentlyRecommended=\(recentlyRecommendedIds.count) primaryGoal=\(primaryGoal.rawValue)")
        return result
    }

    /// Legacy API that also selects an optional second card.
    @available(*, deprecated, message: "Use getSingleRecommendation(); dual secondary cards are deprecated.")
    func getDualRecommendation(includeGreeting: Bool = false) async -> DualRecommendation? {
        isGenerating = true
        defer { isGenerating = false }

        guard let built = await buildRecommendationCore(includeSecondary: true, includeGreeting: includeGreeting) else {
            return nil
        }

        let result = DualRecommendation(
            primary: built.primary,
            secondary: built.secondary,
            userMode: built.userMode,
            currentPhase: built.currentPhase,
            routineProgress: built.routineProgress
        )

        if !result.primary.isPath {
            recentlyRecommendedIds.insert(result.primary.contentId)
        }
        if let sec = result.secondary, !sec.isPath {
            recentlyRecommendedIds.insert(sec.contentId)
        }

        lastRecommendation = SingleRecommendation(
            item: result.primary,
            userMode: result.userMode,
            currentPhase: result.currentPhase,
            routineProgress: result.routineProgress
        )
        let primaryGoal = inferGoalFromPrimary(result.primary)
        ContextStateManager.shared.recordPrimaryShown(goalContext: primaryGoal)

        if result.primary.isCustom || result.secondary?.isCustom == true {
            SharedUserStorage.save(value: true, forKey: .hasReceivedFirstCustomMeditation)
        }

        logger.aiChat("🎯 DUAL_REC: Done (dual legacy) — recentlyRecommended=\(recentlyRecommendedIds.count) primaryGoal=\(primaryGoal.rawValue)")
        return result
    }

    private struct BuiltRecommendationCore {
        let primary: RecommendationItem
        let secondary: RecommendationItem?
        let userMode: UserMode
        let currentPhase: JourneyPhase
        let routineProgress: RoutineProgress?
    }

    /// Shared selection pipeline: Steps 1–3 always; Step 4 (secondary) when `includeSecondary` is true.
    private func buildRecommendationCore(includeSecondary: Bool, includeGreeting: Bool) async -> BuiltRecommendationCore? {
        guard SenseiOnboardingState.shared.isComplete else {
            logger.aiChat("🎯 DUAL_REC: Skipped — onboarding not complete")
            return nil
        }

        let phase = journeyManager.currentPhase
        guard let mode = UserMode.from(phase: phase) else {
            logger.aiChat("🎯 DUAL_REC: Pre-app phase (\(phase.displayName)) — no recommendations")
            return nil
        }

        let routineCount = journeyManager.getRoutineCompletionCount()
        let routineProgress = RoutineProgress(
            completed: routineCount,
            required: ProductJourneyManager.routinesRequiredForCustomization
        )

        logger.aiChat("🎯 DUAL_REC: mode=\(mode.displayName) phase=\(phase.displayName) routines=\(routineCount) hurdle=\(UserPreferencesManager.shared.hurdle ?? "nil")")

        let context = await buildRecommendationContext(
            mode: mode,
            includeGreeting: includeGreeting
        )

        let primary: RecommendationItem?
        switch mode {
        case .learn:
            primary = await selectLearnPrimary(context: context)
        case .personal:
            if let customPrimary = await contextEngine.selectContextual(context) {
                primary = customPrimary
            } else {
                primary = await selectPersonalExploreFallbackAfterCustomFailure(context: context)
            }
        }

        guard let primary else {
            logger.aiChat("🎯 DUAL_REC: No primary available — aborting")
            return nil
        }

        logger.aiChat("🎯 DUAL_REC: primary=\(primary.type.analyticsType) '\(primary.contentTitle)'")

        let secondary: RecommendationItem?
        if includeSecondary {
            let secondaryIsFirstCustom = context.isFirstCustomMeditation && !primary.isCustom
            let secondaryContext = RecommendationContext(
                timeOfDay: context.timeOfDay,
                hurdleContext: context.hurdleContext,
                excludedContentIds: context.excludedContentIds.union([primary.contentId]),
                welcomeGreeting: context.welcomeGreeting,
                contextMessage: context.contextMessage,
                isFirstWelcome: context.isFirstWelcome,
                goal: context.goal,
                isFirstCustomMeditation: secondaryIsFirstCustom,
                isFirstPersonalRecommendation: context.isFirstPersonalRecommendation
            )
            switch mode {
            case .learn:
                secondary = await contextEngine.selectComplementary(secondaryContext)
            case .personal:
                secondary = await contextEngine.selectContrast(secondaryContext, primary.type)
            }
            logger.aiChat("🎯 DUAL_REC: secondary=\(secondary?.type.analyticsType ?? "none")")
        } else {
            secondary = nil
            logger.aiChat("🎯 DUAL_REC: secondary=skipped (single recommendation path)")
        }

        return BuiltRecommendationCore(
            primary: primary,
            secondary: secondary,
            userMode: mode,
            currentPhase: phase,
            routineProgress: routineProgress
        )
    }

    /// Infer GoalContext from a recommended primary for Context State diversity tracking.
    private func inferGoalFromPrimary(_ primary: RecommendationItem) -> GoalContext {
        switch primary.type {
        case .path:
            return .general
        case .explore(let file):
            return GoalContext.from(sessionTags: file.tags)
        case .custom:
            return ContextStateManager.shared.lastEffectiveGoal ?? GoalContext.from(hurdleId: UserPreferencesManager.shared.hurdle)
        }
    }

    // MARK: - Step 2 Helper: Build Context

    private func buildRecommendationContext(
        mode: UserMode,
        includeGreeting: Bool
    ) async -> RecommendationContext {
        let hurdleContext = ContextStateManager.shared.effectiveContext(mode: mode)
            ?? HurdleRecommendationContext.context(for: UserPreferencesManager.shared.hurdle)
        let (greeting, contextMessage, isFirstWelcome) = await resolveGreeting(
            mode: mode,
            includeGreeting: includeGreeting,
            hurdleContext: hurdleContext
        )
        let hasReceivedFirst = SharedUserStorage.retrieve(forKey: .hasReceivedFirstCustomMeditation, as: Bool.self) ?? false
        let goal = UserPreferencesManager.shared.preferences.goal
        return RecommendationContext(
            timeOfDay: .current(),
            hurdleContext: hurdleContext,
            excludedContentIds: recentlyRecommendedIds,
            welcomeGreeting: greeting,
            contextMessage: contextMessage,
            isFirstWelcome: isFirstWelcome,
            goal: goal,
            isFirstCustomMeditation: !hasReceivedFirst,
            isFirstPersonalRecommendation: mode == .personal && isFirstWelcome
        )
    }

    // MARK: - Step 3 Helper: Learn Mode Primary

    /// Learn Mode primary is always the next Path step. Returns nil when the
    /// Path is not ready (e.g. all steps completed, or data not yet loaded).
    private func selectLearnPrimary(context: RecommendationContext) async -> RecommendationItem? {
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] selectLearnPrimary — shouldRecommend=\(pathManager.shouldRecommendPath()) nextStep=\(pathManager.nextStep?.id ?? "nil")")
        #endif

        guard pathManager.shouldRecommendPath(), let pathStep = pathManager.nextStep else {
            logger.aiChat("🎯 DUAL_REC [LEARN]: No path step available")
            return nil
        }

        let primaryMessage = await messageService.generatePathIntro(
            stepNumber: pathStep.order,
            stepTitle: pathStep.title,
            completedSteps: pathManager.completedStepCount,
            omitName: context.welcomeGreeting != nil
        )

        logger.aiChat("🎯 DUAL_REC [LEARN]: Path step \(pathStep.order) — '\(pathStep.title)'")

        return RecommendationItem(
            type: .path(pathStep),
            introMessage: primaryMessage,
            welcomeGreeting: context.welcomeGreeting,
            isFirstWelcome: context.isFirstWelcome,
            contextMessage: context.contextMessage
        )
    }

    /// When custom meditation generation fails (API error, non-meditation response, etc.),
    /// offer a time-appropriate Daily Routine from Explore data so timely and post-session
    /// flows still surface a concrete practice (same eligibility as Library explore).
    private func selectPersonalExploreFallbackAfterCustomFailure(context: RecommendationContext) async -> RecommendationItem? {
        let explore = ExploreRecommendationManager.shared
        guard explore.shouldRecommendExplore() else {
            logger.aiChat("🎯 DUAL_REC: Custom failed — explore fallback skipped (not eligible)")
            return nil
        }
        guard let session = explore.getTimeAppropriateSession(
            excluding: context.excludedContentIds,
            hurdleContext: context.hurdleContext,
            requireHurdleMatch: false
        ) else {
            logger.aiChat("🎯 DUAL_REC: Custom failed — explore fallback skipped (no session)")
            return nil
        }

        logger.aiChat("🎯 DUAL_REC: Custom failed — using explore fallback id=\(session.id) title=\(session.title)")
        AnalyticsManager.shared.logEvent("sensei_custom_failed_explore_fallback", parameters: [
            "session_id": session.id,
            "slot": explore.getCurrentSlotKey(),
            "phase": journeyManager.currentPhase.analyticsName
        ])

        let timeOfDayName = context.timeOfDay.displayName
        let intro = await messageService.generateExplorePrimary(
            sessionTags: session.tags,
            timeOfDay: timeOfDayName,
            hurdleContext: context.hurdleContext
        )
        return RecommendationItem(
            type: .explore(session),
            introMessage: intro,
            welcomeGreeting: context.welcomeGreeting,
            isFirstWelcome: context.isFirstWelcome,
            contextMessage: context.contextMessage
        )
    }

    // MARK: - Greeting Resolution

    /// Resolves the optional greeting shown above the recommendation.
    ///
    /// - First ever recommendation: AI-generated short greeting (bold purple) +
    ///   hurdle context body (Personal Mode only).
    /// - Auto-triggered timely recommendation: time-based greeting (regular white).
    /// - Post-session / transition: no greeting.
    ///
    /// Returns (greeting, contextMessage, isFirstWelcome).
    private func resolveGreeting(
        mode: UserMode,
        includeGreeting: Bool,
        hurdleContext: HurdleRecommendationContext?
    ) async -> (String?, String?, Bool) {
        let hasShown = SharedUserStorage.retrieve(forKey: .hasShownFirstWelcome, as: Bool.self) ?? false

        if !hasShown {
            let firstName = MessageContext.fromUserStorage().firstName
            let welcome = await messageService.generatePathWelcome(firstName: firstName)
            // Context message only for Personal Mode (hurdle-targeted explanation).
            let contextMessage: String?
            if mode == .personal {
                contextMessage = await messageService.generateFirstWelcomeContext(hurdleContext: hurdleContext)
            } else {
                contextMessage = nil
            }
            SharedUserStorage.save(value: true, forKey: .hasShownFirstWelcome)
            logger.aiChat("🎯 DUAL_REC: First-ever welcome shown, contextMessage=\(contextMessage != nil ? "yes" : "nil")")
            return (welcome, contextMessage, true)
        }

        if includeGreeting {
            return (timeBasedGreeting(), nil, false)
        }

        return (nil, nil, false)
    }

    // MARK: - Greeting Builder

    private func timeBasedGreeting() -> String {
        let firstName = MessageContext.fromUserStorage().firstName
        let timeOfDay = ExploreRecommendationManager.TimeOfDay.current()
        let salutation: String
        switch timeOfDay {
        case .morning:        salutation = "Good morning"
        case .noon:           salutation = "Good afternoon"
        case .evening, .night: salutation = "Good evening"
        }
        if let name = firstName {
            return "\(salutation), \(name)."
        }
        return "\(salutation)."
    }

    // MARK: - Eligibility Checks (for UI)

    func canRecommendPath() -> Bool {
        pathManager.shouldRecommendPath() && pathManager.nextStep != nil
    }

    /// Pre-recorded Explore sessions are not offered as Sensei suggestions (Library only).
    func canRecommendExplore() -> Bool {
        false
    }

    func isInTeaseCustomState() -> Bool {
        let routineCount = journeyManager.getRoutineCompletionCount()
        return journeyManager.currentPhase == .dailyRoutines &&
               routineCount >= 2 &&
               routineCount < ProductJourneyManager.routinesRequiredForCustomization
    }

    func getRoutineProgress() -> RoutineProgress {
        RoutineProgress(
            completed: journeyManager.getRoutineCompletionCount(),
            required: ProductJourneyManager.routinesRequiredForCustomization
        )
    }

    // MARK: - Deduplication API

    func markAsRecentlyRecommended(_ contentIds: [String]) {
        for id in contentIds {
            recentlyRecommendedIds.insert(id)
        }
        logger.aiChat("🎯 DUAL_REC: Marked \(contentIds.count) ids as recently recommended, total=\(recentlyRecommendedIds.count)")
    }

    func clearRecentlyRecommended() {
        recentlyRecommendedIds.removeAll()
        logger.aiChat("🎯 DUAL_REC: Cleared recentlyRecommendedIds (dev reset)")
    }

    func seedRecentlyRecommended(from conversation: [ChatMessage]) {
        guard let lastRec = conversation.last(where: { $0.singleRecommendation != nil || $0.dualRecommendation != nil }) else {
            logger.aiChat("🎯 DUAL_REC: Seed skipped — no recommendation in conversation history")
            return
        }

        if let single = lastRec.singleRecommendation {
            if !single.item.isPath {
                recentlyRecommendedIds.insert(single.item.contentId)
            }
        } else if let dualRec = lastRec.dualRecommendation {
            if !dualRec.primary.isPath {
                recentlyRecommendedIds.insert(dualRec.primary.contentId)
            }
            if let secondary = dualRec.secondary, !secondary.isPath {
                recentlyRecommendedIds.insert(secondary.contentId)
            }
        }

        logger.aiChat("🎯 DUAL_REC: Seeded \(recentlyRecommendedIds.count) ids from conversation history")
    }
}
