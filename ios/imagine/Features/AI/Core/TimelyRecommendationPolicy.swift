//
//  TimelyRecommendationPolicy.swift
//  imagine
//
//  Centralizes preflight gates for Sensei “timely launch” recommendations (slot-based
//  daily windows) vs learn-mode refresh (no slot consumption). Call sites stay thin.
//

import Foundation

// MARK: - Input

/// Snapshot of synchronous state before starting a timely-style recommendation fetch.
struct TimelyPrecheckInput: Equatable {
    /// `SenseiOnboardingState.shared.isComplete`
    var senseiOnboardingComplete: Bool
    /// `TimelyRecommendationGate.shared.isInFlight`
    var timelyFetchInFlight: Bool
    /// Post-session prompt flow should block and optionally defer a later retry.
    var postSessionFlowActive: Bool
    /// When true, the per-day time-slot cap (`shouldAutoSuggestTimelyNow`) applies.
    /// Personal track (daily routines / customization) only — not Path/learn refresh.
    var timelySlotRuleApplies: Bool
    /// `ExploreRecommendationManager.shared.shouldAutoSuggestTimelyNow()`; meaningful only if `timelySlotRuleApplies`.
    var timelySlotAvailable: Bool
    /// `ExploreRecommendationManager.shared.isDevTimeOverrideActive()`
    var devTimeOverrideActive: Bool
}

// MARK: - Result

/// Outcome of the synchronous timely preflight.
enum TimelyLaunchEvaluation: Equatable {
    /// Show thinking and run `getSingleRecommendation`.
    case proceed(consumeTimelySlotOnSuccess: Bool, devTimeOverrideActive: Bool)
    /// Do not fetch; caller logs `timely_suggest_skipped_reason` with `skipReason`.
    case skip(skipReason: String, clearDevTimeOverride: Bool, deferTimelyCheckForLater: Bool)
}

// MARK: - Policy (struct of closures)

struct TimelyRecommendationPolicy {
    var evaluatePrecheck: @MainActor (TimelyPrecheckInput) -> TimelyLaunchEvaluation

    @MainActor
    static let live = TimelyRecommendationPolicy(
        evaluatePrecheck: { input in
            guard input.senseiOnboardingComplete else {
                return .skip(
                    skipReason: "onboarding_incomplete",
                    clearDevTimeOverride: false,
                    deferTimelyCheckForLater: false
                )
            }
            guard !input.timelyFetchInFlight else {
                return .skip(
                    skipReason: "timely_fetch_in_flight",
                    clearDevTimeOverride: false,
                    deferTimelyCheckForLater: false
                )
            }
            if input.postSessionFlowActive {
                return .skip(
                    skipReason: "prompt_active",
                    clearDevTimeOverride: false,
                    deferTimelyCheckForLater: true
                )
            }
            if input.timelySlotRuleApplies {
                guard input.timelySlotAvailable else {
                    return .skip(
                        skipReason: "slot_used",
                        clearDevTimeOverride: input.devTimeOverrideActive,
                        deferTimelyCheckForLater: false
                    )
                }
                return .proceed(
                    consumeTimelySlotOnSuccess: true,
                    devTimeOverrideActive: input.devTimeOverrideActive
                )
            }
            return .proceed(
                consumeTimelySlotOnSuccess: false,
                devTimeOverrideActive: input.devTimeOverrideActive
            )
        }
    )

    /// Deterministic “never offer” for previews/tests.
    @MainActor
    static let preview = TimelyRecommendationPolicy(
        evaluatePrecheck: { _ in
            .skip(skipReason: "preview", clearDevTimeOverride: false, deferTimelyCheckForLater: false)
        }
    )
}
