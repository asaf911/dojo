import Foundation

// ⚠️ DEPRECATED: AIOnboarding feature disabled as of January 2026
// This file is preserved for potential future reuse.
// The flow is disabled via hasPendingSteps() always returning false.
// Do not add new functionality - this code path is no longer active.

final class SenseiOnboardingState {
    static let shared = SenseiOnboardingState()

    private let defaults = UserDefaults.standard

    private enum Key {
        static func startedAt(_ userId: String) -> String { "sensei_onboarding_started_at:" + userId }
        static func completedAt(_ userId: String) -> String { "sensei_onboarding_completed_at:" + userId }
        static func currentStepIndex(_ userId: String) -> String { "sensei_onboarding_current_step_index:" + userId }
        static func legacyNextStepIndex(_ userId: String) -> String { "sensei_onboarding_next_step_index:" + userId }
        static func stepsCompletedBeforeExit(_ userId: String) -> String { "sensei_onboarding_steps_completed:" + userId }
        static func didSkipEarly(_ userId: String) -> String { "sensei_onboarding_did_skip_early:" + userId }
        static func completedMeditation(_ userId: String) -> String { "sensei_onboarding_completed_meditation:" + userId }
        static func arrivedAtFinalViaSkip(_ userId: String) -> String { "sensei_onboarding_arrived_final_via_skip:" + userId }
    }

    private var userId: String {
        UserIdentityManager.shared.currentUserId
    }

    var isComplete: Bool {
        // DEPRECATED: AIOnboarding disabled - always return true
        // Original logic: defaults.string(forKey: Key.completedAt(userId)) != nil
        return true
    }
    
    /// Number of steps completed before exit (skip or complete)
    var stepsCompletedBeforeExit: Int {
        get { defaults.integer(forKey: Key.stepsCompletedBeforeExit(userId)) }
        set { defaults.set(newValue, forKey: Key.stepsCompletedBeforeExit(userId)) }
    }
    
    /// True if user skipped to meditation before reaching final step
    var didSkipEarly: Bool {
        get { defaults.bool(forKey: Key.didSkipEarly(userId)) }
        set { defaults.set(newValue, forKey: Key.didSkipEarly(userId)) }
    }
    
    /// True if user completed AI-generated meditation from onboarding
    var completedMeditation: Bool {
        get { defaults.bool(forKey: Key.completedMeditation(userId)) }
        set { defaults.set(newValue, forKey: Key.completedMeditation(userId)) }
    }
    
    /// True if user arrived at final step by skipping (for contextual messaging)
    var arrivedAtFinalViaSkip: Bool {
        get { defaults.bool(forKey: Key.arrivedAtFinalViaSkip(userId)) }
        set { defaults.set(newValue, forKey: Key.arrivedAtFinalViaSkip(userId)) }
    }

    func currentStepIndex(totalSteps: Int) -> Int {
        guard !isComplete else { return totalSteps }
        let currentKey = Key.currentStepIndex(userId)
        if let legacy = storedIndex(forKey: Key.legacyNextStepIndex(userId)) {
            defaults.removeObject(forKey: Key.legacyNextStepIndex(userId))
            defaults.set(legacy, forKey: currentKey)
        }
        if let stored = storedIndex(forKey: currentKey) {
            return min(max(0, stored), totalSteps)
        }
        return 0
    }

    func setCurrentStepIndex(_ index: Int, totalSteps: Int) {
        let clamped = min(max(0, index), totalSteps)
        defaults.set(clamped, forKey: Key.currentStepIndex(userId))
    }

    func hasPendingSteps(totalSteps: Int) -> Bool {
        // DEPRECATED: AIOnboarding disabled - always return false to skip flow
        // Original logic preserved for reference:
        // guard totalSteps > 0 else { return false }
        // return currentStepIndex(totalSteps: totalSteps) < totalSteps && !isComplete
        return false
    }

    func markFlowPresented(origin: String, totalSteps: Int) {
        guard hasPendingSteps(totalSteps: totalSteps) else { return }
        
        // Track start timestamp for internal state
        let key = Key.startedAt(userId)
        if defaults.string(forKey: key) == nil {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            defaults.set(timestamp, forKey: key)
        }
        
        // Always log when flow is presented (hasPendingSteps prevents post-completion)
            AnalyticsManager.shared.logEvent("ai_onboarding_started", parameters: [
            "placement": origin,
            "total_steps": totalSteps
            ])
            logger.aiChat("🧠 AI_DEBUG onboarding_started origin=\(origin) total_steps=\(totalSteps)")
    }

    func markStepViewed(step: any SenseiOnboardingStep, index: Int, totalSteps: Int) {
        guard !isComplete else { return }
        AnalyticsManager.shared.logEvent("ai_onboarding_step_viewed", parameters: [
            "step_id": step.id,
            "step_type": step.stepType.rawValue,
            "step_index": index,
            "step_number": index + 1,
            "total_steps": totalSteps
        ])
        logger.aiChat("🧠 AI_DEBUG onboarding_step_viewed id=\(step.id) type=\(step.stepType.rawValue) step=\(index + 1)/\(totalSteps)")
    }

    func markStepAction(step: any SenseiOnboardingStep, actionId: String?, index: Int, totalSteps: Int, isSkip: Bool = false, selectedOptions: String? = nil) {
        guard let actionId = actionId else { return }
        var params: [String: Any] = [
            "step_id": step.id,
            "step_type": step.stepType.rawValue,
            "action_id": actionId,
            "is_skip": isSkip,
            "step_number": index + 1,
            "total_steps": totalSteps
        ]
        if let options = selectedOptions, !options.isEmpty {
            params["selected_options"] = options
        }
        AnalyticsManager.shared.logEvent("ai_onboarding_step_action", parameters: params)
        logger.aiChat("🧠 AI_DEBUG onboarding_step_action id=\(step.id) action=\(actionId) skip=\(isSkip) step=\(index + 1)/\(totalSteps) options=\(selectedOptions ?? "nil")")
    }

    @discardableResult
    func advance(by offset: Int, totalSteps: Int) -> Int {
        guard !isComplete else { return totalSteps }
        let current = currentStepIndex(totalSteps: totalSteps)
        let target = min(max(0, current + offset), totalSteps)
        defaults.set(target, forKey: Key.currentStepIndex(userId))
        return target
    }

    func markCompleted(source: String, requestId: String?, userPrompt: String?) {
        guard !isComplete else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        defaults.set(timestamp, forKey: Key.completedAt(userId))
        AnalyticsManager.shared.logEvent("ai_onboarding_completed", parameters: [
            "source": source,
            "request_id": requestId ?? "",
            "user_prompt": userPrompt ?? "",
            "steps_completed": stepsCompletedBeforeExit,
            "skipped_early": didSkipEarly
        ])
        logger.aiChat("🧠 AI_DEBUG onboarding_completed source=\(source) req=\(requestId ?? "") skipped=\(didSkipEarly) steps=\(stepsCompletedBeforeExit) ts=\(timestamp)")
    }

    func resetForCurrentUser() {
        let userKey = userId
        defaults.removeObject(forKey: Key.startedAt(userKey))
        defaults.removeObject(forKey: Key.completedAt(userKey))
        defaults.removeObject(forKey: Key.currentStepIndex(userKey))
        defaults.removeObject(forKey: Key.legacyNextStepIndex(userKey))
        defaults.removeObject(forKey: Key.stepsCompletedBeforeExit(userKey))
        defaults.removeObject(forKey: Key.didSkipEarly(userKey))
        defaults.removeObject(forKey: Key.completedMeditation(userKey))
        defaults.removeObject(forKey: Key.arrivedAtFinalViaSkip(userKey))
        logger.aiChat("🧠 AI_DEBUG onboarding_reset user=\(userKey)")
    }
    
    /// Reset step index to 0 for a new chat, but keep onboarding state (don't mark as complete)
    func resetStepIndexForNewChat() {
        guard !isComplete else { return }
        let userKey = userId
        defaults.set(0, forKey: Key.currentStepIndex(userKey))
        logger.aiChat("🧠 AI_DEBUG onboarding_step_index_reset_for_new_chat user=\(userKey)")
    }

    private func storedIndex(forKey key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }
}

