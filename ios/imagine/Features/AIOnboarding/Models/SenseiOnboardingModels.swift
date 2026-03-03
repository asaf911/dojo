import Foundation

// ⚠️ DEPRECATED: AIOnboarding feature disabled as of January 2026
// This file is preserved for potential future reuse.
// The flow is disabled via hasPendingSteps() always returning false in SenseiOnboardingState.
// Do not add new functionality - this code path is no longer active.

enum SenseiOnboardingStepType: String, Codable {
    case message
    case question
    case promptEducation
}

protocol SenseiOnboardingStep: Identifiable {
    var stepType: SenseiOnboardingStepType { get }
    var id: String { get }
}

typealias SenseiOnboardingSequence = [any SenseiOnboardingStep]

// MARK: - Onboarding Action (defines what happens when CTA is tapped)

enum OnboardingAction: Codable, Equatable {
    case advance(by: Int)           // Move forward by N steps
    case jumpToStep(id: String)     // Jump to a specific step by ID
    case completeAndGenerate        // End onboarding and generate meditation
}

// MARK: - CTA Model (Independent Component)

struct SenseiOnboardingCTA: Codable {
    let primaryTitle: String
    let skipTitle: String?
    let analyticsActionId: String
    let analyticsSkipId: String?
    let primaryAction: OnboardingAction
    let skipAction: OnboardingAction?
    
    init(
        primaryTitle: String,
        skipTitle: String? = nil,
        analyticsActionId: String,
        analyticsSkipId: String? = nil,
        primaryAction: OnboardingAction = .advance(by: 1),
        skipAction: OnboardingAction? = nil
    ) {
        self.primaryTitle = primaryTitle
        self.skipTitle = skipTitle
        self.analyticsActionId = analyticsActionId
        self.analyticsSkipId = analyticsSkipId
        self.primaryAction = primaryAction
        self.skipAction = skipAction
    }
    
    /// Convenience initializer for single-button CTA (no skip option)
    static func singleButton(
        title: String = "Continue",
        analyticsActionId: String,
        primaryAction: OnboardingAction = .advance(by: 1)
    ) -> SenseiOnboardingCTA {
        SenseiOnboardingCTA(
            primaryTitle: title,
            skipTitle: nil,
            analyticsActionId: analyticsActionId,
            analyticsSkipId: nil,
            primaryAction: primaryAction,
            skipAction: nil
        )
    }
    
    /// Convenience initializer for the "skip to meditation" pattern
    /// Now routes to the prompt education step instead of directly generating
    static func withSkipToMeditation(
        continueTitle: String = "Continue",
        skipTitle: String = "Let's meditate",
        analyticsActionId: String,
        analyticsSkipId: String
    ) -> SenseiOnboardingCTA {
        SenseiOnboardingCTA(
            primaryTitle: continueTitle,
            skipTitle: skipTitle,
            analyticsActionId: analyticsActionId,
            analyticsSkipId: analyticsSkipId,
            primaryAction: .advance(by: 1),
            skipAction: .jumpToStep(id: "new_prompt_education")
        )
    }
}

// MARK: - Prompt Education Step (keyboard education final step)

struct SenseiOnboardingPromptEducation: SenseiOnboardingStep, Codable {
    let id: String
    let introText: String?         // Optional regular text shown first (e.g., "Thank you. I now have...")
    let preamble: String           // Bold question text (e.g., "Any specific requests?")
    let instruction: String        // "Try one of these:"
    let examplePrompts: [String]   // Tappable prompt suggestions
    let cta: SenseiOnboardingCTA?  // "Just begin" button
    
    var stepType: SenseiOnboardingStepType { .promptEducation }
    
    init(
        id: String = UUID().uuidString,
        introText: String? = nil,
        preamble: String,
        instruction: String,
        examplePrompts: [String],
        cta: SenseiOnboardingCTA? = nil
    ) {
        self.id = id
        self.introText = introText
        self.preamble = preamble
        self.instruction = instruction
        self.examplePrompts = examplePrompts
        self.cta = cta
    }
}

// MARK: - Message Step (with optional CTA)

struct SenseiOnboardingMessage: SenseiOnboardingStep, Codable {
    let id: String
    let title: String
    let body: String
    let caption: String?
    let cta: SenseiOnboardingCTA?

    var stepType: SenseiOnboardingStepType { .message }

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        caption: String? = nil,
        cta: SenseiOnboardingCTA? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.caption = caption
        self.cta = cta
    }
}

// MARK: - Question Step (with CTA)

struct SenseiOnboardingQuestion: SenseiOnboardingStep, Codable {
    let id: String
    let preamble: String?  // Regular text shown above the question
    let question: String   // Bold 22pt question text
    let options: [String]
    let allowsMultipleSelection: Bool
    let cta: SenseiOnboardingCTA?

    var stepType: SenseiOnboardingStepType { .question }
    
    // Convenience computed properties for backward compatibility
    var continueTitle: String { cta?.primaryTitle ?? "Continue" }
    var skipTitle: String? { cta?.skipTitle }
    var analyticsActionId: String { cta?.analyticsActionId ?? "" }
    var analyticsSkipId: String? { cta?.analyticsSkipId }
    var primaryAction: OnboardingAction { cta?.primaryAction ?? .advance(by: 1) }
    var skipAction: OnboardingAction? { cta?.skipAction }

    init(
        id: String = UUID().uuidString,
        preamble: String? = nil,
        question: String,
        options: [String],
        allowsMultipleSelection: Bool = false,
        cta: SenseiOnboardingCTA? = nil
    ) {
        self.id = id
        self.preamble = preamble
        self.question = question
        self.options = options
        self.allowsMultipleSelection = allowsMultipleSelection
        self.cta = cta
    }
    
    // Convenience initializer for backward compatibility
    init(
        id: String = UUID().uuidString,
        preamble: String? = nil,
        question: String,
        options: [String],
        continueTitle: String = "Yes!",
        skipTitle: String? = nil,
        allowsMultipleSelection: Bool = false,
        analyticsActionId: String,
        analyticsSkipId: String? = nil,
        primaryAction: OnboardingAction = .advance(by: 1),
        skipAction: OnboardingAction? = nil
    ) {
        self.id = id
        self.preamble = preamble
        self.question = question
        self.options = options
        self.allowsMultipleSelection = allowsMultipleSelection
        self.cta = SenseiOnboardingCTA(
            primaryTitle: continueTitle,
            skipTitle: skipTitle,
            analyticsActionId: analyticsActionId,
            analyticsSkipId: analyticsSkipId,
            primaryAction: primaryAction,
            skipAction: skipAction
        )
    }
}

