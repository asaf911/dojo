//
//  UserProfileManager.swift
//  Dojo
//
//  Manages user profile storage and updates.
//  The profile persists locally and will sync to Firebase in the future.
//

// ⚠️ DEPRECATED: AIOnboarding feature disabled as of January 2026
// This file is preserved for potential future reuse.
// The flow is disabled via hasPendingSteps() always returning false in SenseiOnboardingState.
// Do not add new functionality - this code path is no longer active.

import Foundation

final class UserProfileManager {
    static let shared = UserProfileManager()
    
    private let storageKey: UserStorageKey = .userProfile
    
    private(set) var profile: UserProfile {
        didSet {
            profile.updatedAt = Date()
            persist()
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        if let saved: UserProfile = SharedUserStorage.retrieve(forKey: storageKey, as: UserProfile.self) {
            self.profile = saved
            logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER loaded existing profile")
            profile.logProfile(prefix: "LOADED ")
        } else {
            self.profile = UserProfile()
            logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER created new profile")
        }
    }
    
    // MARK: - Update Methods (called during onboarding)
    
    func updateGoals(_ goals: [String]) {
        let mapped = goals.compactMap { ProfileGoal(rawValue: $0) }
        profile.goals = mapped
        logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER updated goals=[\(mapped.map { $0.rawValue }.joined(separator: ", "))]")
    }
    
    func updateCurrentState(_ states: [String]) {
        let mapped = states.compactMap { ProfileEmotionalState(rawValue: $0) }
        profile.currentState = mapped
        logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER updated state=[\(mapped.map { $0.rawValue }.joined(separator: ", "))]")
    }
    
    func updateExperience(_ experiences: [String]) {
        let mapped = experiences.compactMap { ProfileExperienceType(rawValue: $0) }
        profile.experienceBackground = mapped
        profile.experienceLevel = inferExperienceLevel(from: mapped)
        logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER updated experience=[\(mapped.map { $0.rawValue }.joined(separator: ", "))] level=\(profile.experienceLevel.rawValue)")
    }
    
    func updateGuidanceStyle(_ style: String) {
        profile.guidanceStyle = ProfileGuidanceStyle(rawValue: style)
        logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER updated guidanceStyle=\(style)")
    }
    
    func updateFirstName(_ name: String?) {
        profile.firstName = name
        logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER updated firstName=\(name ?? "nil")")
    }
    
    func markOnboardingComplete(stepsCompleted: Int, totalSteps: Int) {
        profile.onboardingCompletedAt = Date()
        profile.onboardingCompletionPercentage = Int((Double(stepsCompleted) / Double(totalSteps)) * 100)
        logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER onboarding_complete steps=\(stepsCompleted)/\(totalSteps) (\(profile.onboardingCompletionPercentage)%)")
        profile.logProfile(prefix: "ONBOARDING_COMPLETE ")
    }
    
    // MARK: - First Meditation
    
    /// Builds the final prompt for the first meditation (profile context + user prompt)
    func buildFirstMeditationPrompt(userPrompt: String) -> String {
        let context = profile.buildContextForAI(userPrompt: userPrompt)
        
        let finalPrompt: String
        if context.isEmpty {
            finalPrompt = userPrompt
            logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER first_meditation (no profile data) userPrompt=\(userPrompt)")
        } else {
            finalPrompt = "\(context)\n\nUser request: \(userPrompt)"
            logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER first_meditation context_len=\(context.count) userPrompt=\(userPrompt)")
            logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER first_meditation FULL_API_PROMPT:\n\(finalPrompt)")
        }
        
        return finalPrompt
    }
    
    /// Call after first meditation is generated
    func markFirstMeditationGenerated() {
        profile.firstMeditationGeneratedAt = Date()
        logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER first_meditation_generated - profile retained for future use")
        profile.logProfile(prefix: "FIRST_MEDITATION_DONE ")
    }
    
    // MARK: - Duration Constraints
    
    /// Removed: Previously forced 5-min duration for first meditation.
    /// Now returns nil always - user's explicit duration request in prompt is respected.
    var recommendedDuration: Int? {
        // No duration constraint - AI will parse duration from user prompt
        return nil
    }
    
    // MARK: - Private
    
    private func inferExperienceLevel(from experiences: [ProfileExperienceType]) -> ProfileExperienceLevel {
        if experiences.contains(.completelyNew) {
            return .beginner
        }
        if experiences.contains(.workshopsAndRetreats) {
            return .experienced
        }
        if experiences.contains(.calmOrHeadspace) || experiences.contains(.otherApps) {
            return .intermediate
        }
        if experiences.contains(.onMyOwn) || experiences.contains(.youtubeOrSpotify) {
            return .casual
        }
        return .unknown
    }
    
    private func persist() {
        SharedUserStorage.save(value: profile, forKey: storageKey)
    }
    
    /// Reset profile (for testing/debugging)
    func reset() {
        profile = UserProfile()
        SharedUserStorage.delete(forKey: storageKey)
        logger.aiChat("🧠 AI_DEBUG USER_PROFILE_MANAGER reset")
    }
}
