//
//  OnboardingResponseCollector.swift
//  Dojo
//
//  Collects and persists user responses during the Sensei onboarding flow
//  to generate a personalized first meditation.
//

// ⚠️ DEPRECATED: AIOnboarding feature disabled as of January 2026
// This file is preserved for potential future reuse.
// The flow is disabled via hasPendingSteps() always returning false in SenseiOnboardingState.
// Do not add new functionality - this code path is no longer active.

import Foundation

final class OnboardingResponseCollector {
    static let shared = OnboardingResponseCollector()
    
    // MARK: - Response Model
    
    struct CollectedResponses: Codable {
        var goals: [String] = []           // Step 2: "Reduce stress", "Sleep better", etc.
        var currentFeeling: [String] = []  // Step 3: "Stressed", "Tired", etc.
        var experience: [String] = []      // Step 5: "Calm or Headspace", etc.
        var guidanceStyle: String?         // Step 6: "Calm & soft", etc.
        var firstName: String?
        
        var isEmpty: Bool {
            goals.isEmpty && currentFeeling.isEmpty && experience.isEmpty && guidanceStyle == nil
        }
    }
    
    // MARK: - Properties
    
    private(set) var responses: CollectedResponses {
        didSet {
            persist()
        }
    }
    
    private let storageKey: UserStorageKey = .onboardingResponses
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted responses on init
        if let saved: CollectedResponses = SharedUserStorage.retrieve(forKey: storageKey, as: CollectedResponses.self) {
            self.responses = saved
            logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR loaded responses goals=\(saved.goals.count) feeling=\(saved.currentFeeling.count) exp=\(saved.experience.count) style=\(saved.guidanceStyle ?? "nil")")
        } else {
            self.responses = CollectedResponses()
        }
    }
    
    // MARK: - Recording Responses
    
    /// Records a user selection for a given onboarding step
    /// - Parameters:
    ///   - stepId: The ID of the onboarding step (e.g., "new_goal_question")
    ///   - selection: The user's selected option(s), comma-separated for multi-select
    func record(stepId: String, selection: String?) {
        guard let selection = selection, !selection.isEmpty else {
            logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR record skipped stepId=\(stepId) selection=nil")
            return
        }
        
        // Parse comma-separated selections for multi-select questions
        let selections = selection.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        switch stepId {
        case "new_goal_question":
            responses.goals = selections
            logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR recorded goals=\(selections.joined(separator: ", "))")
            
        case "new_baseline_question":
            responses.currentFeeling = selections
            logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR recorded feeling=\(selections.joined(separator: ", "))")
            
        case "new_experience_question":
            responses.experience = selections
            logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR recorded experience=\(selections.joined(separator: ", "))")
            
        case "new_guidance_question":
            responses.guidanceStyle = selection
            logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR recorded guidanceStyle=\(selection)")
            
        default:
            logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR unknown stepId=\(stepId)")
        }
    }
    
    /// Records the user's first name for personalization
    func recordFirstName(_ firstName: String?) {
        responses.firstName = firstName
    }
    
    // MARK: - Prompt Building
    
    /// Builds a comprehensive prompt for meditation generation based on all collected responses
    /// - Returns: A prompt string suitable for the AI meditation generator
    func buildPrompt() -> String {
        // Fallback for users who skipped all questions
        if responses.isEmpty {
            logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR buildPrompt using fallback (all skipped)")
            return "Create a 5-minute beginner-friendly relaxation meditation with a short body scan"
        }
        
        // Build the user context section
        let context = buildUserContext()
        
        // Build the request
        let duration = determineDuration()
        var request = "Create a \(duration)-minute meditation"
        
        // Add goals if present
        if !responses.goals.isEmpty {
            let goalText = responses.goals.map { $0.lowercased() }.joined(separator: " and ")
            request += " focused on helping me \(goalText)"
        }
        
        // Add guidance style preference
        if let style = responses.guidanceStyle?.lowercased() {
            request += " with a \(style) guidance tone"
        }
        
        request += "."
        
        // Combine context and request
        let prompt = context.isEmpty ? request : "\(context)\n\n\(request)"
        logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR buildPrompt result=\(prompt)")
        return prompt
    }
    
    /// Builds a user context block from all collected onboarding responses
    /// - Returns: A formatted context string for the AI
    private func buildUserContext() -> String {
        var contextLines: [String] = []
        
        // Current emotional state - include ALL feelings
        if !responses.currentFeeling.isEmpty {
            let feelingText = responses.currentFeeling.joined(separator: ", ")
            contextLines.append("Current state: \(feelingText)")
        }
        
        // Experience level - important for complexity
        if !responses.experience.isEmpty {
            let expText = responses.experience.joined(separator: ", ")
            contextLines.append("Experience: \(expText)")
            
            // Add experience-based guidance
            let expGuidance = inferExperienceGuidance()
            if !expGuidance.isEmpty {
                contextLines.append("Note: \(expGuidance)")
            }
        }
        
        // Name for personalization
        if let name = responses.firstName, !name.isEmpty {
            contextLines.append("Name: \(name)")
        }
        
        guard !contextLines.isEmpty else { return "" }
        
        return "About me:\n" + contextLines.map { "- \($0)" }.joined(separator: "\n")
    }
    
    /// Infers guidance based on user's meditation experience
    private func inferExperienceGuidance() -> String {
        guard !responses.experience.isEmpty else { return "" }
        
        let exp = responses.experience.map { $0.lowercased() }
        
        if exp.contains("i'm completely new") {
            return "New to meditation - use simple language and more guidance"
        }
        
        if exp.contains("workshops and retreats") {
            return "Experienced practitioner - comfortable with longer silences"
        }
        
        return ""
    }
    
    /// Determines appropriate meditation duration based on user experience
    /// First meditation is always 5 minutes by default
    private func determineDuration() -> Int {
        // First meditation is always 5 minutes for a gentle introduction
        return 5
    }
    
    // MARK: - State Management
    
    /// Resets all collected responses (call after meditation is generated)
    func reset() {
        responses = CollectedResponses()
        SharedUserStorage.delete(forKey: storageKey)
        logger.aiChat("🧠 AI_DEBUG ONBOARDING_COLLECTOR reset")
    }
    
    // MARK: - Persistence
    
    private func persist() {
        SharedUserStorage.save(value: responses, forKey: storageKey)
    }
}

