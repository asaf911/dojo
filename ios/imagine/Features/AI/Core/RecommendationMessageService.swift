//
//  RecommendationMessageService.swift
//  imagine
//
//  Created for AI-polished recommendation intro messages.
//
//  Generates short, varied intro messages for all recommendation types.
//  Uses AI to create human-feeling text while maintaining brevity.
//  Falls back to static messages if AI fails or times out.
//

import Foundation

// MARK: - Message Essence

/// Defines the core intent of each recommendation intro message
enum MessageEssence: String, CaseIterable {
    // Path messages
    case pathWelcome
    case pathIntroFirst
    case pathIntroContinue
    
    // Explore primary messages
    case explorePrimaryMorning
    case explorePrimaryNoon
    case explorePrimaryEvening
    case explorePrimarySleep
    case explorePrimaryDefault
    
    // Explore secondary messages
    case exploreSecondaryMorning
    case exploreSecondaryNoon
    case exploreSecondaryEvening
    case exploreSecondarySleep
    case exploreSecondaryDefault
    
    // Custom messages
    case customPrimary
    case customSecondary
    case customOnlyPrimary
    case customSecondaryAlt
    
    // Special
    case teaseCustomization
    
    /// First-welcome context body text — explains why the recommendation was chosen
    case firstWelcomeContext
    
    /// Human-readable description for AI prompt
    var description: String {
        switch self {
        case .pathWelcome:
            return "Ultra-short greeting only — just 'Hey [name],' or 'Hi [name],' with a comma. Nothing else."
        case .pathIntroFirst:
            return "Introduce the very first meditation step - make it feel exciting but not over the top. End with colon."
        case .pathIntroContinue:
            return "Encourage continuing to next step - acknowledge progress. End with colon."
        case .explorePrimaryMorning:
            return "Recommend morning session - reference the fresh start of the day. End with colon."
        case .explorePrimaryNoon:
            return "Recommend midday reset - reference taking a break. End with colon."
        case .explorePrimaryEvening:
            return "Recommend evening session - reference winding down. End with colon."
        case .explorePrimarySleep:
            return "Recommend sleep session - reference preparing for rest. End with colon."
        case .explorePrimaryDefault:
            return "Recommend a pre-recorded session. End with colon."
        case .exploreSecondaryMorning:
            return "Offer alternative morning option - start with 'Or'. End with colon."
        case .exploreSecondaryNoon:
            return "Offer alternative midday option - start with 'Or'. End with colon."
        case .exploreSecondaryEvening:
            return "Offer alternative evening option - start with 'Or'. End with colon."
        case .exploreSecondarySleep:
            return "Offer alternative sleep option - start with 'Or'. End with colon."
        case .exploreSecondaryDefault:
            return "Offer alternative session - start with 'Or'. End with colon."
        case .customPrimary:
            return "Present a personalized AI-created meditation. End with colon."
        case .customSecondary:
            return "Offer shorter custom option - start with 'Or', mention it's quicker. End with colon."
        case .customOnlyPrimary:
            return "Present time-appropriate custom meditation. End with colon."
        case .customSecondaryAlt:
            return "Offer custom meditation as alternative - start with 'Or'. End with colon."
        case .teaseCustomization:
            return "Tease that custom meditations unlock soon - mention how many routines left"
        case .firstWelcomeContext:
            return "1-2 short sentences that acknowledge what the user wants to work on and explain why this meditation was chosen. Use natural language — no internal IDs or jargon. Warm but brief. Do NOT start with the user's name, 'Hey', 'Hi', or any greeting — a greeting is already shown directly above this text."
        }
    }
    
    /// Static fallback message (used if AI fails)
    func fallback(with context: MessageContext) -> String {
        switch self {
        case .pathWelcome:
            if let name = context.firstName {
                return "Hey \(name),"
            }
            return "Hey there,"
        case .pathIntroFirst:
            return "Here's your first step on the Path:"
        case .pathIntroContinue:
            let step = context.stepNumber ?? 2
            return "Ready for step \(step):"
        case .explorePrimaryMorning:
            return "Start your morning right:"
        case .explorePrimaryNoon:
            return "Take a midday reset:"
        case .explorePrimaryEvening:
            return "Time to wind down:"
        case .explorePrimarySleep:
            return "Prepare for restful sleep:"
        case .explorePrimaryDefault:
            return "Here's one for you:"
        case .exploreSecondaryMorning:
            return "Or try this morning session:"
        case .exploreSecondaryNoon:
            return "Or this midday reset:"
        case .exploreSecondaryEvening:
            return "Or wind down with this:"
        case .exploreSecondarySleep:
            return "Or try this for sleep:"
        case .exploreSecondaryDefault:
            return "Or try this one:"
        case .customPrimary:
            return "Created just for you:"
        case .customSecondary:
            let mins = context.duration ?? 5
            return "Or a quick \(mins)-minute one:"
        case .customOnlyPrimary:
            let time = context.timeOfDay ?? "today"
            return "Here's one for your \(time):"
        case .customSecondaryAlt:
            return "Or I can create one for you:"
        case .teaseCustomization:
            let remaining = context.routinesRemaining ?? 1
            return "\(remaining) more routine\(remaining == 1 ? "" : "s") to unlock custom meditations:"
        case .firstWelcomeContext:
            if let seed = context.hurdlePromptSeed {
                return "I've chosen something to help you \(seed)."
            }
            return "I've picked something perfectly suited for where you are right now."
        }
    }
    
    /// Maximum character count for this message type
    var maxCharacters: Int {
        switch self {
        case .pathWelcome: return 20
        case .pathIntroFirst: return 45
        case .pathIntroContinue: return 40
        case .explorePrimaryMorning: return 40
        case .explorePrimaryNoon: return 40
        case .explorePrimaryEvening: return 40
        case .explorePrimarySleep: return 40
        case .explorePrimaryDefault: return 35
        case .exploreSecondaryMorning: return 40
        case .exploreSecondaryNoon: return 35
        case .exploreSecondaryEvening: return 35
        case .exploreSecondarySleep: return 35
        case .exploreSecondaryDefault: return 30
        case .customPrimary: return 35
        case .customSecondary: return 40
        case .customOnlyPrimary: return 40
        case .customSecondaryAlt: return 40
        case .teaseCustomization: return 55
        case .firstWelcomeContext: return 130
        }
    }
}

// MARK: - Message Context

/// Context variables for generating personalized messages
struct MessageContext {
    var firstName: String?
    var stepNumber: Int?
    var stepTitle: String?
    var completedSteps: Int?
    var timeOfDay: String?
    var sessionTitle: String?
    var routinesCompleted: Int?
    var routinesRequired: Int?
    var duration: Int?

    /// Onboarding hurdle ID (e.g. "mind_racing") for hurdle-targeted intro messages
    var hurdleId: String?

    /// Onboarding goal ID (e.g. "relaxation") for goal-aware intro messages
    var goalId: String?
    
    /// Natural-language description of the user's hurdle (from HurdleRecommendationContext.aiPromptSeed).
    /// Used by firstWelcomeContext to explain the recommendation without internal jargon.
    var hurdlePromptSeed: String?

    /// Routines remaining to unlock custom
    var routinesRemaining: Int? {
        guard let completed = routinesCompleted, let required = routinesRequired else { return nil }
        return max(0, required - completed)
    }
    
    /// Empty context
    static let empty = MessageContext()
    
    /// Create context from user storage (name only — hurdle/goal added at call site when needed)
    static func fromUserStorage() -> MessageContext {
        let storedName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)
        let firstName = storedName?.split(separator: " ").first.map(String.init)
        return MessageContext(firstName: firstName)
    }
}

// MARK: - Recommendation Message Service

/// Service for generating AI-polished recommendation intro messages
@MainActor
final class RecommendationMessageService {
    
    // MARK: - Singleton
    
    static let shared = RecommendationMessageService()
    
    // MARK: - Dependencies
    
    private let aiService = SimplifiedAIService()
    
    // MARK: - Configuration
    
    /// Timeout for AI generation (seconds)
    private let timeoutSeconds: TimeInterval = 2.0
    
    // MARK: - Initialization
    
    private init() {
        logger.aiChat("🎯 REC_MSG: RecommendationMessageService initialized")
    }
    
    // MARK: - Public API
    
    /// Generate an AI-polished intro message
    /// - Parameters:
    ///   - essence: The core intent of the message
    ///   - context: Variables for personalization
    /// - Returns: A short, human-feeling intro message
    func generate(essence: MessageEssence, context: MessageContext = .empty) async -> String {
        logger.aiChat("🎯 REC_MSG: Generating message for \(essence.rawValue) hurdle=\(context.hurdleId ?? "nil") goal=\(context.goalId ?? "nil") timeOfDay=\(context.timeOfDay ?? "nil")")
        
        do {
            // Use timeout to ensure we never block UI too long
            let message = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await self.aiService.generateIntroMessage(essence: essence, context: context)
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.timeoutSeconds * 1_000_000_000))
                    throw TimeoutError()
                }
                
                // Return first successful result
                guard let result = try await group.next() else {
                    throw TimeoutError()
                }
                group.cancelAll()
                return result
            }
            
            // Validate length
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= essence.maxCharacters && trimmed.count >= 3 {
                logger.aiChat("🎯 REC_MSG: AI success - '\(trimmed)'")
                return trimmed
            }
            
            // AI message too long, use fallback
            logger.aiChat("🎯 REC_MSG: AI message too long (\(trimmed.count) chars), using fallback")
            return essence.fallback(with: context)
            
        } catch {
            // Timeout or API error - use fallback
            logger.aiChat("🎯 REC_MSG: AI failed (\(error.localizedDescription)), using fallback")
            return essence.fallback(with: context)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Generate path welcome greeting (e.g. "Hey Asaf,")
    func generatePathWelcome(firstName: String?) async -> String {
        let context = MessageContext(firstName: firstName)
        return await generate(essence: .pathWelcome, context: context)
    }
    
    /// Generate the first-welcome contextual body text.
    ///
    /// Shown once, directly after the greeting, before the recommendation intro.
    /// References the user's hurdle in natural language to make the first recommendation
    /// feel personally chosen — not generic.
    ///
    /// Example output: "I noticed you're dealing with a racing mind — I picked something that goes right to the heart of that."
    ///
    /// - Parameters:
    ///   - hurdleContext: The hurdle context mapping the user's onboarding choice to natural language.
    ///                    Pass `nil` for path-track users (no hurdle-based context needed there).
    func generateFirstWelcomeContext(hurdleContext: HurdleRecommendationContext?) async -> String? {
        guard let hurdleContext else {
            logger.aiChat("🎯 REC_MSG: No hurdle context — skipping firstWelcomeContext")
            return nil
        }
        let storedName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)
        let firstName = storedName?.split(separator: " ").first.map(String.init)
        let context = MessageContext(
            firstName: firstName,
            hurdleId: hurdleContext.hurdleId,
            goalId: UserPreferencesManager.shared.preferences.goal,
            hurdlePromptSeed: hurdleContext.aiPromptSeed
        )
        var message = await generate(essence: .firstWelcomeContext, context: context)
        
        // Safety net: strip any leading greeting the AI may have added despite instructions.
        // Patterns like "Hey Asaf!", "Hi Asaf,", "Hey!", "Hi there," should never appear here
        // because the welcomeGreeting is already displayed directly above.
        if let name = firstName {
            let greetingPrefixes = ["Hey \(name)!", "Hey \(name),", "Hi \(name)!", "Hi \(name),",
                                    "Hello \(name)!", "Hello \(name),"]
            for prefix in greetingPrefixes {
                if message.hasPrefix(prefix) {
                    message = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                    logger.aiChat("🎯 REC_MSG: Stripped duplicate greeting prefix '\(prefix)' from firstWelcomeContext")
                    break
                }
            }
        }
        // Also strip generic greeting-only openers that include no name
        let genericPrefixes = ["Hey! ", "Hi! ", "Hello! ", "Hey, ", "Hi, "]
        for prefix in genericPrefixes where message.hasPrefix(prefix) {
            message = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            logger.aiChat("🎯 REC_MSG: Stripped generic greeting prefix from firstWelcomeContext")
            break
        }
        
        // Capitalise the first letter after stripping in case we removed a sentence opener
        if let first = message.first, first.isLowercase {
            message = first.uppercased() + message.dropFirst()
        }
        
        logger.aiChat("🎯 REC_MSG: firstWelcomeContext generated: '\(message)'")
        return message
    }
    
    /// Generate path intro message
    /// - Parameter omitName: When true, excludes the user's name from context to avoid
    ///   repeating it when a greeting (welcome or timely) already used the name.
    func generatePathIntro(stepNumber: Int, stepTitle: String, completedSteps: Int, omitName: Bool = false) async -> String {
        let context = MessageContext(
            firstName: omitName ? nil : MessageContext.fromUserStorage().firstName,
            stepNumber: stepNumber,
            stepTitle: stepTitle,
            completedSteps: completedSteps
        )
        let essence: MessageEssence = stepNumber == 1 ? .pathIntroFirst : .pathIntroContinue
        return await generate(essence: essence, context: context)
    }
    
    /// Generate explore recommendation message (primary)
    /// - Parameters:
    ///   - sessionTags: Tags from the selected audio session (drives time-of-day essence)
    ///   - timeOfDay: Current time of day display name
    ///   - hurdleContext: Optional hurdle context for targeted personalization
    func generateExplorePrimary(
        sessionTags: [String],
        timeOfDay: String,
        hurdleContext: HurdleRecommendationContext? = nil
    ) async -> String {
        let tagsLower = sessionTags.map { $0.lowercased() }
        let context = MessageContext(
            timeOfDay: timeOfDay,
            hurdleId: hurdleContext?.hurdleId,
            goalId: UserPreferencesManager.shared.preferences.goal
        )
        
        let essence: MessageEssence
        if tagsLower.contains("morning") {
            essence = .explorePrimaryMorning
        } else if tagsLower.contains("noon") {
            essence = .explorePrimaryNoon
        } else if tagsLower.contains("evening") {
            essence = .explorePrimaryEvening
        } else if tagsLower.contains("sleep") {
            essence = .explorePrimarySleep
        } else {
            essence = .explorePrimaryDefault
        }
        
        return await generate(essence: essence, context: context)
    }
    
    /// Generate explore recommendation message (secondary)
    /// - Parameters:
    ///   - sessionTags: Tags from the selected audio session
    ///   - timeOfDay: Current time of day display name
    ///   - hurdleContext: Optional hurdle context for targeted personalization
    func generateExploreSecondary(
        sessionTags: [String],
        timeOfDay: String,
        hurdleContext: HurdleRecommendationContext? = nil
    ) async -> String {
        let tagsLower = sessionTags.map { $0.lowercased() }
        let context = MessageContext(
            timeOfDay: timeOfDay,
            hurdleId: hurdleContext?.hurdleId,
            goalId: UserPreferencesManager.shared.preferences.goal
        )
        
        let essence: MessageEssence
        if tagsLower.contains("morning") {
            essence = .exploreSecondaryMorning
        } else if tagsLower.contains("noon") {
            essence = .exploreSecondaryNoon
        } else if tagsLower.contains("evening") {
            essence = .exploreSecondaryEvening
        } else if tagsLower.contains("sleep") {
            essence = .exploreSecondarySleep
        } else {
            essence = .exploreSecondaryDefault
        }
        
        return await generate(essence: essence, context: context)
    }
    
    /// Generate custom meditation message (primary)
    func generateCustomPrimary(timeOfDay: String? = nil) async -> String {
        let context = MessageContext(timeOfDay: timeOfDay)
        return await generate(essence: .customPrimary, context: context)
    }
    
    /// Generate custom meditation message (secondary)
    func generateCustomSecondary(duration: Int? = nil, timeOfDay: String? = nil) async -> String {
        let context = MessageContext(timeOfDay: timeOfDay, duration: duration)
        return await generate(essence: .customSecondary, context: context)
    }
    
    /// Generate custom-only primary message
    func generateCustomOnlyPrimary(timeOfDay: String) async -> String {
        let context = MessageContext(timeOfDay: timeOfDay)
        return await generate(essence: .customOnlyPrimary, context: context)
    }
    
    /// Generate custom secondary alternative message
    func generateCustomSecondaryAlt(timeOfDay: String) async -> String {
        let context = MessageContext(timeOfDay: timeOfDay)
        return await generate(essence: .customSecondaryAlt, context: context)
    }
    
    /// Generate tease customization message
    func generateTeaseCustomization(routinesCompleted: Int, routinesRequired: Int) async -> String {
        let context = MessageContext(
            routinesCompleted: routinesCompleted,
            routinesRequired: routinesRequired
        )
        return await generate(essence: .teaseCustomization, context: context)
    }
}

// MARK: - Timeout Error

private struct TimeoutError: Error {
    var localizedDescription: String { "Timeout" }
}
