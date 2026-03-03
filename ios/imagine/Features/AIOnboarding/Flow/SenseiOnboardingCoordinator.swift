import Foundation

// ⚠️ DEPRECATED: AIOnboarding feature disabled as of January 2026
// This file is preserved for potential future reuse.
// The flow is disabled via hasPendingSteps() always returning false in SenseiOnboardingState.
// Do not add new functionality - this code path is no longer active.

final class SenseiOnboardingCoordinator {
    static let shared = SenseiOnboardingCoordinator()

    private let state: SenseiOnboardingState

    init(state: SenseiOnboardingState = .shared) {
        self.state = state
    }

    func launchIfNeeded(origin: String, launchAIChat: @escaping () -> Void) {
        let firstName = SenseiOnboardingScript.currentFirstName()
        let steps = SenseiOnboardingScript.steps(firstName: firstName)
        guard state.hasPendingSteps(totalSteps: steps.count) else { return }

        // Note: ai_onboarding_started event is logged in AIChatContainerView.queueOnboardingIfNeeded
        // to ensure single event firing when the flow actually begins
        DispatchQueue.main.async {
            launchAIChat()
        }
    }
}

