//
//  OnboardingAnswers.swift
//  imagine
//
//  Legacy onboarding answers model for backward compatibility.
//  TODO: Migrate PracticeManager to use OnboardingResponses instead and remove this file.
//

import Foundation

/// Legacy onboarding answers model.
/// Used by PracticeManager for practice recommendations.
/// Consider migrating to OnboardingResponses for the new onboarding system.
struct OnboardingAnswers: Codable {
    var experience: OnboardingExperience
    var goal: OnboardingLegacyGoal
    var length: OnboardingLength
    var timeOfDay: OnboardingTimeOfDay
}

/// Legacy experience level
enum OnboardingExperience: String, Codable, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
}

/// Legacy goal enum (different from new OnboardingGoal)
enum OnboardingLegacyGoal: String, Codable, CaseIterable {
    case sleepBetter = "sleep_better"
    case reduceStress = "reduce_stress"
    case increaseEnergy = "increase_energy"
    case improveConcentration = "improve_concentration"
    case spiritual = "spiritual"
    case other = "other"
}

/// Legacy length preference
enum OnboardingLength: String, Codable, CaseIterable {
    case twoMin = "two_min"
    case fiveMin = "five_min"
    case tenPlus = "ten_plus"
}

/// Legacy time of day preference
enum OnboardingTimeOfDay: String, Codable, CaseIterable {
    case morning = "morning"
    case afternoon = "afternoon"
    case evening = "evening"
    case anytime = "anytime"
}
