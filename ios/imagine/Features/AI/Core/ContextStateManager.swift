//
//  ContextStateManager.swift
//  imagine
//
//  Adaptive Context Evolution Layer.
//  Maintains rolling ranked goal contexts from behavior; feeds
//  selectContextual() with dynamic context instead of static onboarding.
//

import Foundation

// MARK: - Context State Manager

@MainActor
final class ContextStateManager {

    static let shared = ContextStateManager()

    /// Goal last used by effectiveContext (for recordPrimaryShown when primary is custom).
    private(set) var lastEffectiveGoal: GoalContext?

    private init() {
        logger.aiChat("🎯 CTX_STATE: ContextStateManager initialized")
    }

    // MARK: - API

    /// Record a completed session. Call from UnifiedPostSessionManager after report built.
    func recordSessionComplete(sessionType: PostSessionType, completedAt: TimeInterval) {
        let goal = deriveGoal(from: sessionType)
        var snapshot = loadSnapshot()
        snapshot.recentSessions.insert(
            SessionEntry(goalRawValue: goal.rawValue, completedAt: completedAt),
            at: 0
        )
        if snapshot.recentSessions.count > ContextStateSnapshot.maxRecentSessions {
            snapshot.recentSessions = Array(snapshot.recentSessions.prefix(ContextStateSnapshot.maxRecentSessions))
        }
        snapshot.totalSessionsCompleted += 1
        saveSnapshot(snapshot)
        logger.aiChat("🎯 CTX_STATE: recordSessionComplete goal=\(goal.rawValue) total=\(snapshot.totalSessionsCompleted)")
#if DEBUG
        print("[ContextState] recordSessionComplete type=\(sessionTypeLabel(sessionType)) goal=\(goal.rawValue) recentCount=\(snapshot.recentSessions.count)")
#endif
    }

    /// Returns the effective HurdleRecommendationContext for recommendation selection.
    /// Personal mode: uses ranked behavior; cold start falls back to onboarding.
    /// Learn mode: always uses onboarding (context evolution applies to Personal only).
    func effectiveContext(mode: UserMode) -> HurdleRecommendationContext? {
        switch mode {
        case .learn:
            let hurdle = HurdleRecommendationContext.context(for: UserPreferencesManager.shared.hurdle)
            lastEffectiveGoal = GoalContext.from(hurdleId: UserPreferencesManager.shared.hurdle)
            logger.aiChat("🎯 CTX_STATE: effectiveContext mode=learn → onboarding hurdle=\(hurdle?.hurdleId ?? "nil")")
            return hurdle
        case .personal:
            let snapshot = loadSnapshot()
            if snapshot.totalSessionsCompleted < 3 {
                let fallback = HurdleRecommendationContext.context(for: UserPreferencesManager.shared.hurdle)
                lastEffectiveGoal = GoalContext.from(hurdleId: UserPreferencesManager.shared.hurdle)
                logger.aiChat("🎯 CTX_STATE: effectiveContext mode=personal cold start (sessions=\(snapshot.totalSessionsCompleted)) → onboarding")
                return fallback
            }
            let ranked = rankedGoalContexts()
            guard let top = ranked.first else {
                let fallback = HurdleRecommendationContext.context(for: UserPreferencesManager.shared.hurdle)
                lastEffectiveGoal = GoalContext.from(hurdleId: UserPreferencesManager.shared.hurdle)
                logger.aiChat("🎯 CTX_STATE: effectiveContext mode=personal ranked=empty → fallback onboarding")
                return fallback
            }
            lastEffectiveGoal = top
            let result = top.asHurdleContext
            logger.aiChat("🎯 CTX_STATE: effectiveContext selected=\(top.rawValue) source=behavior")
#if DEBUG
            print("[ContextState] effectiveContext top=\(top.rawValue) ranked=\(ranked.prefix(3).map(\.rawValue))")
#endif
            return result
        }
    }

    /// Record that a primary was shown (for diversity guardrail).
    func recordPrimaryShown(goalContext: GoalContext) {
        var snapshot = loadSnapshot()
        snapshot.recentPrimaries.insert(goalContext.rawValue, at: 0)
        if snapshot.recentPrimaries.count > ContextStateSnapshot.maxRecentPrimaries {
            snapshot.recentPrimaries = Array(snapshot.recentPrimaries.prefix(ContextStateSnapshot.maxRecentPrimaries))
        }
        snapshot.primariesSinceExploration += 1
        saveSnapshot(snapshot)
        logger.aiChat("🎯 CTX_STATE: recordPrimaryShown goal=\(goalContext.rawValue) recentCount=\(snapshot.recentPrimaries.count)")
#if DEBUG
        print("[ContextState] recordPrimaryShown goal=\(goalContext.rawValue)")
#endif
    }

    /// Set explicit override (e.g. user selected a tag). Dominant for next N sessions.
    func setExplicitOverride(goalContext: GoalContext, forSessions sessions: Int) {
        var snapshot = loadSnapshot()
        snapshot.explicitOverride = ExplicitOverride(goalRawValue: goalContext.rawValue, sessionsRemaining: sessions)
        saveSnapshot(snapshot)
        logger.aiChat("🎯 CTX_STATE: setExplicitOverride goal=\(goalContext.rawValue) sessions=\(sessions)")
#if DEBUG
        print("[ContextState] setExplicitOverride goal=\(goalContext.rawValue) forSessions=\(sessions)")
#endif
    }

    /// Clear all context state (for dev reset).
    func clear() {
        saveSnapshot(ContextStateSnapshot())
        logger.aiChat("🎯 CTX_STATE: clear — snapshot reset")
#if DEBUG
        print("[ContextState] clear — snapshot reset")
#endif
    }

    // MARK: - Ranking

    /// Computes ranked goal contexts. No side effects.
    func rankedGoalContexts() -> [GoalContext] {
        let snapshot = loadSnapshot()
        let timeOfDay = ExploreRecommendationManager.TimeOfDay.current()

        // 1. Explicit override takes priority
        if var override = snapshot.explicitOverride, override.sessionsRemaining > 0 {
            override.sessionsRemaining -= 1
            var updated = snapshot
            updated.explicitOverride = override.sessionsRemaining > 0 ? override : nil
            saveSnapshot(updated)
            if let goal = GoalContext(rawValue: override.goalRawValue) {
                logger.aiChat("🎯 CTX_STATE: ranked top=[\(goal.rawValue)] explicitOverride remaining=\(override.sessionsRemaining)")
                return [goal]
            }
        }

        // 2. Compute weights
        var weights: [GoalContext: Double] = [:]
        let recencyWeights = [5.0, 4.0, 3.0, 2.0, 1.0]
        for (idx, entry) in snapshot.recentSessions.prefix(5).enumerated() {
            guard let goal = GoalContext(rawValue: entry.goalRawValue) else { continue }
            let w = idx < recencyWeights.count ? recencyWeights[idx] : 0.1
            weights[goal, default: 0] += w
        }

        // Time-of-day bias
        let timeBias: (GoalContext, Double) = timeBiasFor(timeOfDay)
        weights[timeBias.0, default: 0] += timeBias.1

        // Onboarding decay
        let onboardingGoal = GoalContext.from(hurdleId: UserPreferencesManager.shared.hurdle)
        let onboardingW = onboardingWeight(sessionCount: snapshot.totalSessionsCompleted)
        weights[onboardingGoal, default: 0] += onboardingW

        // 3. Sort by weight
        let sorted = GoalContext.allCases
            .map { (goal: $0, weight: weights[$0] ?? 0) }
            .sorted { $0.weight > $1.weight }
            .filter { $0.weight > 0 }
        let ranked = sorted.map(\.goal)

        // 4. Diversity filter: top cannot have count >= 2 in recentPrimaries
        var diversityApplied = false
        var filtered = ranked
        if let first = filtered.first {
            let count = snapshot.recentPrimaries.filter { $0 == first.rawValue }.count
            if count >= 2 {
                filtered = Array(filtered.dropFirst())
                diversityApplied = true
                logger.aiChat("🎯 CTX_STATE: diversity filter — dropped \(first.rawValue) count=\(count) in recentPrimaries")
            }
        }

        // 5. Exploration: 1 in 3 must be adjacent/contrasting
        var explorationApplied = false
        if snapshot.primariesSinceExploration >= 2, filtered.count >= 2,
           let contrasting = contrastingGoal(for: filtered.first) {
            var inserted = filtered
            inserted.insert(contrasting, at: 0)
            filtered = Array(inserted.prefix(5))
            explorationApplied = true
            var updated = loadSnapshot()
            updated.primariesSinceExploration = 0
            saveSnapshot(updated)
            logger.aiChat("🎯 CTX_STATE: exploration — injected contrasting \(contrasting.rawValue) (was \(snapshot.primariesSinceExploration) since last)")
        }

        let top3 = filtered.prefix(3).map(\.rawValue).joined(separator: ",")
        logger.aiChat("🎯 CTX_STATE: ranked top=[\(top3)] diversityApplied=\(diversityApplied) explorationApplied=\(explorationApplied)")
#if DEBUG
        print("[ContextState] ranked top=\(top3) diversityApplied=\(diversityApplied) explorationApplied=\(explorationApplied)")
#endif
        return Array(filtered.prefix(5))
    }

    // MARK: - Private Helpers

    private func loadSnapshot() -> ContextStateSnapshot {
        SharedUserStorage.retrieve(forKey: .contextStateSnapshot, as: ContextStateSnapshot.self)
            ?? ContextStateSnapshot()
    }

    private func saveSnapshot(_ snapshot: ContextStateSnapshot) {
        SharedUserStorage.save(value: snapshot, forKey: .contextStateSnapshot)
    }

    private func deriveGoal(from sessionType: PostSessionType) -> GoalContext {
        switch sessionType {
        case .explore(let file):
            return GoalContext.from(sessionTags: file.tags)
        case .path:
            return .general
        case .custom:
            return GoalContext.from(hurdleId: UserPreferencesManager.shared.hurdle)
        }
    }

    private func sessionTypeLabel(_ type: PostSessionType) -> String {
        switch type {
        case .explore(let f): return "explore(\(f.id))"
        case .path(let id, _, _, _): return "path(\(id))"
        case .custom(let t, _): return "custom(\(t ?? "nil"))"
        }
    }

    private func onboardingWeight(sessionCount: Int) -> Double {
        switch sessionCount {
        case 0..<3: return 4.0
        case 3..<5: return 1.0
        default: return 0.2
        }
    }

    private func timeBiasFor(_ timeOfDay: ExploreRecommendationManager.TimeOfDay) -> (GoalContext, Double) {
        switch timeOfDay {
        case .night: return (.sleep, 2.0)
        case .morning: return (.energy, 1.0)
        case .noon: return (.focus, 1.0)
        case .evening: return (.calm, 1.0)
        }
    }

    private func contrastingGoal(for goal: GoalContext?) -> GoalContext? {
        guard let goal else { return nil }
        let adjacent: [GoalContext: GoalContext] = [
            .calm: .relax,
            .relax: .calm,
            .sleep: .calm,
            .focus: .calm,
            .energy: .calm,
            .grounding: .focus,
            .general: .calm
        ]
        return adjacent[goal] ?? .calm
    }
}
