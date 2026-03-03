//
//  DualRecommendationOrchestrator.swift
//  imagine
//
//  Central coordinator for dual recommendations.
//  Implements a clean four-step decision framework:
//
//  Step 1 — Determine UserMode (learn | personal)
//  Step 2 — Build RecommendationContext (time, hurdle, greeting, excluded IDs)
//  Step 3 — Select Primary  (mode-specific role)
//  Step 4 — Select Secondary (mode-specific role, contrast or complement)
//
//  Session selection (Explore vs Custom) is delegated entirely to
//  RecommendationContextEngine — the orchestrator never branches on content type.
//

import Foundation
import Combine

// MARK: - Dual Recommendation Orchestrator

/// Coordinates the four-step dual recommendation framework.
/// Single entry point for AI chat to get both primary and secondary options.
@MainActor
class DualRecommendationOrchestrator: ObservableObject {

    // MARK: - Singleton

    static let shared = DualRecommendationOrchestrator()

    // MARK: - Dependencies

    private let journeyManager  = ProductJourneyManager.shared
    private let pathManager     = PathProgressManager.shared
    private let exploreManager  = ExploreRecommendationManager.shared
    private let messageService  = RecommendationMessageService.shared
    private let contextEngine   = RecommendationContextEngine.live

    // MARK: - Published State

    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var lastRecommendation: DualRecommendation?

    // MARK: - Deduplication

    /// Content IDs recently recommended. Excludes Path steps (sequential by design).
    /// Not persisted — resets on app launch, which is intentional.
    private var recentlyRecommendedIds: Set<String> = []

    // MARK: - Initialization

    private init() {
        logger.aiChat("🎯 DUAL_REC: DualRecommendationOrchestrator initialized")
    }

    // MARK: - Main Entry Point

    /// Get dual recommendations.
    ///
    /// - Parameter includeGreeting: When true, prepends a timely greeting
    ///   (e.g. "Good evening, Asaf."). Pass false for post-session and
    ///   transition-triggered calls.
    func getDualRecommendation(includeGreeting: Bool = false) async -> DualRecommendation? {
        isGenerating = true
        defer { isGenerating = false }

        // Onboarding must be complete before showing any recommendations.
        guard SenseiOnboardingState.shared.isComplete else {
            logger.aiChat("🎯 DUAL_REC: Skipped — onboarding not complete")
            return nil
        }

        // ── Step 1: Determine mode ────────────────────────────────────────────
        let phase = journeyManager.currentPhase
        guard let mode = UserMode.from(phase: phase) else {
            logger.aiChat("🎯 DUAL_REC: Pre-app phase (\(phase.displayName)) — no recommendations")
            return nil
        }

        let routineCount    = journeyManager.getRoutineCompletionCount()
        let routineProgress = RoutineProgress(
            completed: routineCount,
            required: ProductJourneyManager.routinesRequiredForCustomization
        )

        logger.aiChat("🎯 DUAL_REC: mode=\(mode.displayName) phase=\(phase.displayName) routines=\(routineCount) hurdle=\(UserPreferencesManager.shared.hurdle ?? "nil")")

        // ── Step 2: Build context ─────────────────────────────────────────────
        let context = await buildRecommendationContext(
            mode: mode,
            includeGreeting: includeGreeting
        )

        // ── Step 3: Select primary ────────────────────────────────────────────
        let primary: RecommendationItem?

        switch mode {
        case .learn:
            primary = await selectLearnPrimary(context: context)
        case .personal:
            primary = await contextEngine.selectContextual(context)
        }

        guard let primary else {
            logger.aiChat("🎯 DUAL_REC: No primary available — aborting")
            return nil
        }

        logger.aiChat("🎯 DUAL_REC: primary=\(primary.type.analyticsType) '\(primary.contentTitle)'")

        // ── Step 4: Select secondary ──────────────────────────────────────────
        // Build a secondary context that excludes the primary to avoid duplicates.
        // If primary was Custom, secondary is not the first custom — only one gets the enhanced prompt.
        let secondaryIsFirstCustom = context.isFirstCustomMeditation && !primary.isCustom
        let secondaryContext = RecommendationContext(
            timeOfDay: context.timeOfDay,
            hurdleContext: context.hurdleContext,
            excludedContentIds: context.excludedContentIds.union([primary.contentId]),
            welcomeGreeting: context.welcomeGreeting,
            contextMessage: context.contextMessage,
            isFirstWelcome: context.isFirstWelcome,
            goal: context.goal,
            isFirstCustomMeditation: secondaryIsFirstCustom
        )

        let secondary: RecommendationItem?

        switch mode {
        case .learn:
            secondary = await contextEngine.selectComplementary(secondaryContext)
        case .personal:
            secondary = await contextEngine.selectContrast(secondaryContext, primary.type)
        }

        logger.aiChat("🎯 DUAL_REC: secondary=\(secondary?.type.analyticsType ?? "none")")

        // ── Output ────────────────────────────────────────────────────────────
        let result = DualRecommendation(
            primary: primary,
            secondary: secondary,
            userMode: mode,
            currentPhase: phase,
            routineProgress: routineProgress
        )

        // Track non-path IDs to avoid consecutive repeats on the next call.
        if !result.primary.isPath {
            recentlyRecommendedIds.insert(result.primary.contentId)
        }
        if let sec = result.secondary, !sec.isPath {
            recentlyRecommendedIds.insert(sec.contentId)
        }

        lastRecommendation = result
        let primaryGoal = inferGoalFromPrimary(result.primary)
        ContextStateManager.shared.recordPrimaryShown(goalContext: primaryGoal)

        // Mark first custom meditation as received when we deliver any Custom (primary or secondary)
        if result.primary.isCustom || result.secondary?.isCustom == true {
            SharedUserStorage.save(value: true, forKey: .hasReceivedFirstCustomMeditation)
        }

        logger.aiChat("🎯 DUAL_REC: Done — recentlyRecommended=\(recentlyRecommendedIds.count) primaryGoal=\(primaryGoal.rawValue)")
        return result
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
            isFirstCustomMeditation: !hasReceivedFirst
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

    func canRecommendExplore() -> Bool {
        pathManager.allStepsCompleted &&
        exploreManager.isLoaded &&
        exploreManager.getTimeAppropriateSession() != nil
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
        guard let lastRec = conversation.last(where: { $0.dualRecommendation != nil }),
              let dualRec = lastRec.dualRecommendation else {
            logger.aiChat("🎯 DUAL_REC: Seed skipped — no dual recommendation in conversation history")
            return
        }

        if !dualRec.primary.isPath {
            recentlyRecommendedIds.insert(dualRec.primary.contentId)
        }
        if let secondary = dualRec.secondary, !secondary.isPath {
            recentlyRecommendedIds.insert(secondary.contentId)
        }

        logger.aiChat("🎯 DUAL_REC: Seeded \(recentlyRecommendedIds.count) ids from conversation history")
    }
}
