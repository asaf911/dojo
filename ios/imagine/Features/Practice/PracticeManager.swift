//
//  PracticeManager.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-23
//

import Foundation
import SwiftUI
import FirebaseAuth
import HealthKit
import Combine

// New structure to store completed practice details.
struct CompletedPractice: Codable, Hashable {
    let practiceID: String
    let completionDate: Date
}

class PracticeManager: ObservableObject {

    // MARK: - Singleton
    static let shared = PracticeManager()

    private let healthKitManager = HealthKitManager.shared
    private var audioFiles: [AudioFile] = []
    
    // Recommendation expiration interval: if more than 3 hours have passed since a recommendation was stored (and not played), expire it.
    private let recommendationExpirationInterval: TimeInterval = 3 * 3600  // 3 hours

    // MARK: - Published
    // Updated to store an array of CompletedPractice instead of just practice IDs.
    @Published private(set) var completedPractices: [CompletedPractice] = []

    private init() {
        // Retrieve completed practices from storage or default to an empty array.
        completedPractices = SharedUserStorage.retrieve(forKey: .completedPractices, as: [CompletedPractice].self) ?? []
    }

    // MARK: - Audio Files
    private var storedAudioFiles: [AudioFile] {
        get { audioFiles }
        set { audioFiles = newValue }
    }

    func loadAudioFiles(from files: [AudioFile]) {
        storedAudioFiles = files
        logger.debugMessage("Loaded \(files.count) audio files.", function: #function)
    }

    // MARK: - Mark Completed
    func markPracticeAsCompleted(practiceID: String) {
        // Check if this practice is already marked as completed.
        if !completedPractices.contains(where: { $0.practiceID == practiceID }) {
            let completedEntry = CompletedPractice(practiceID: practiceID, completionDate: Date())
            completedPractices.append(completedEntry)
            SharedUserStorage.save(value: completedPractices, forKey: .completedPractices)
            logger.infoMessage("Marked practice \(practiceID) as completed on \(completedEntry.completionDate).")
        }
        SharedUserStorage.delete(forKey: .lastRecommendation)

        guard let practice = audioFiles.first(where: { $0.id == practiceID }) else {
            logger.errorMessage("Practice \(practiceID) not found.")
            return
        }

        FirestoreManager.shared.updatePracticeCompletion(practiceID) { success in
            success
                ? logger.infoMessage("Practice completion updated in Firestore for \(practiceID).")
                : logger.errorMessage("Failed to update completion in Firestore for \(practiceID).")
        }

        if practice.category == .learn {
            updateLearningSequenceInFirestore()
        }
    }

    // Helper function to determine if a practice was completed within the last week.
    func isPracticeRecentlyPlayed(practiceID: String) -> Bool {
        if let completedEntry = completedPractices.first(where: { $0.practiceID == practiceID }) {
            // Check if the completion date is within the last 7 days.
            let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
            return completedEntry.completionDate >= oneWeekAgo
        }
        return false
    }

    func clearCompletedPractices() {
        completedPractices.removeAll()
        SharedUserStorage.delete(forKey: .completedPractices)
        logger.infoMessage("Cleared completed practices.")
        updateLearningSequenceInFirestore()
    }
    
    /// Clears only specific practice IDs (used for clearing path step completions)
    func clearSpecificPractices(_ practiceIds: [String]) {
        let beforeCount = completedPractices.count
        completedPractices.removeAll { practiceIds.contains($0.practiceID) }
        let removedCount = beforeCount - completedPractices.count
        SharedUserStorage.save(value: completedPractices, forKey: .completedPractices)
        logger.infoMessage("Cleared \(removedCount) specific practices from \(practiceIds.count) requested IDs.")
        print("🧹 PATH_CLEAR: Removed \(removedCount) path step completions from PracticeManager")
    }
    
    /// Clears all path step completions by pattern (step_1, step_2, etc.)
    /// This works even if PathProgressManager.pathSteps isn't loaded yet
    func clearPathStepsByPattern() {
        print("🧹 PATH_CLEAR [PracticeManager]: clearPathStepsByPattern() called")
        print("🧹 PATH_CLEAR [PracticeManager]: BEFORE - completedPractices count: \(completedPractices.count)")
        print("🧹 PATH_CLEAR [PracticeManager]: BEFORE - IDs: \(completedPractices.map { $0.practiceID })")
        
        let beforeCount = completedPractices.count
        let pathStepsToRemove = completedPractices.filter { $0.practiceID.hasPrefix("step_") }
        print("🧹 PATH_CLEAR [PracticeManager]: Found \(pathStepsToRemove.count) path steps to remove: \(pathStepsToRemove.map { $0.practiceID })")
        
        // Path step IDs follow pattern: step_1, step_2, ..., step_N
        completedPractices.removeAll { $0.practiceID.hasPrefix("step_") }
        let removedCount = beforeCount - completedPractices.count
        
        print("🧹 PATH_CLEAR [PracticeManager]: AFTER - completedPractices count: \(completedPractices.count)")
        print("🧹 PATH_CLEAR [PracticeManager]: AFTER - IDs: \(completedPractices.map { $0.practiceID })")
        
        SharedUserStorage.save(value: completedPractices, forKey: .completedPractices)
        print("🧹 PATH_CLEAR [PracticeManager]: Saved to storage")
        
        // Verify storage was updated
        let storedPractices = SharedUserStorage.retrieve(forKey: .completedPractices, as: [CompletedPractice].self) ?? []
        print("🧹 PATH_CLEAR [PracticeManager]: VERIFY storage - count: \(storedPractices.count), IDs: \(storedPractices.map { $0.practiceID })")
        
        logger.infoMessage("Cleared \(removedCount) path step completions by pattern.")
        print("🧹 PATH_CLEAR [PracticeManager]: Done - removed \(removedCount) path steps")
    }

    // MARK: - Complete Session
    func completeMeditationSession(practiceID: String, startDate: Date, endDate: Date) {
        logger.debugMessage("Completing session \(practiceID)")
        StatsManager.shared.updateMetricsOnSessionCompletion(
            practiceID: practiceID,
            startDate: startDate,
            endDate: endDate
        )
        markPracticeAsCompleted(practiceID: practiceID)
    }

    // MARK: - Master Recommender
    
    /// Recommendation logic:
    /// 1) Filter by user-preferred duration.
    /// 2) If the user's goal != .sleepBetter, try to recommend the next "learn" session sequentially.
    /// 3) Otherwise, within the duration-filtered list, use the current system time to score and recommend practices that are timely.
    /// 4) If no timely candidate exists among the chosen duration, fall back to returning the first available.
    func recommendPractice(forUser audioFiles: [AudioFile]) -> AudioFile? {
        // 1) Length filter
        let lengthFilteredList = filterByUserPreferredLength(audioFiles)
        logger.debugMessage("recommendPractice -> lengthFilteredList count = \(lengthFilteredList.count).")

        // Need the user's answers
        guard let userAnswers = SharedUserStorage.retrieve(forKey: .onboardingAnswers, as: OnboardingAnswers.self) else {
            logger.warnMessage("No OnboardingAnswers => fallback random from lengthFilteredList.")
            let fallback = fallbackPractice(from: audioFiles.filter { !$0.premium })
            storeRecommendation(fallback)
            return fallback
        }

        var recommendation: AudioFile? = nil

        // 3) If goal != .sleepBetter, try "learn first" with sequential logic.
        if userAnswers.goal != .sleepBetter {
            recommendation = getNextLearnPractice(from: lengthFilteredList)
            if let rec = recommendation {
                logger.infoMessage("Recommended next 'learn': \(rec.id).")
                return rec
            }
        }

        // 4) Time-of-day filter and scoring
        let timelyCandidates = lengthFilteredList.filter { isRelevant(forTimeOfDay: $0) }
        if !timelyCandidates.isEmpty {
            let scored = timelyCandidates.map { ($0, scorePractice($0)) }
            if let best = scored.max(by: { $0.1 < $1.1 })?.0 {
                storeRecommendation(best)
                logger.infoMessage("Recommended timely session: \(best.id)")
                return best
            }
        }
        
        // Fallback if no timely candidate exists among the chosen duration.
        logger.infoMessage("No timely candidate found in chosen duration, using first available: \(lengthFilteredList.first?.id ?? "nil")")
        return lengthFilteredList.first ?? fallbackPractice(from: audioFiles.filter { !$0.premium })
    }

    private func filterByUserPreferredLength(_ allFiles: [AudioFile]) -> [AudioFile] {
        guard let answers = SharedUserStorage.retrieve(forKey: .onboardingAnswers, as: OnboardingAnswers.self) else {
            logger.warnMessage("No OnboardingAnswers => no length filter => returning all.")
            return allFiles
        }

        logger.debugMessage(
            "filterByUserPreferredLength => userAnswers=[\(answers.experience),\(answers.goal),\(answers.length),\(answers.timeOfDay)]"
        )

        switch answers.length {
        case .twoMin:
            let filtered = allFiles.filter { $0.durations.contains(where: { $0.length == 2 }) }
            logger.debugMessage("2-min => \(filtered.count) matches.")
            return filtered
        case .fiveMin:
            let filtered = allFiles.filter { $0.durations.contains(where: { $0.length == 5 }) }
            logger.debugMessage("5-min => \(filtered.count) matches.")
            return filtered
        case .tenPlus:
            let filtered = allFiles.filter { $0.durations.contains(where: { $0.length >= 10 }) }
            logger.debugMessage("10+ => \(filtered.count) matches.")
            return filtered
        }
    }

    // "Learn first" among length-filtered with sequential logic.
    private func getNextLearnPractice(from list: [AudioFile]) -> AudioFile? {
        let learn = list.filter { $0.category == .learn }
                        .sorted(by: { $0.id < $1.id })
        logger.debugMessage("getNextLearnPractice => sorted learn sessions: \(learn.map { $0.id }.joined(separator: ", "))")
        for (index, session) in learn.enumerated() {
            if !isPracticeCompleted(practiceID: session.id) {
                // Only recommend this session if all previous learn sessions are completed.
                let allPreviousCompleted = learn.prefix(index).allSatisfy { isPracticeCompleted(practiceID: $0.id) }
                if allPreviousCompleted {
                    storeRecommendation(session)
                    logger.debugMessage("Next learn sequentially recommended: \(session.id)")
                    return session
                } else {
                    logger.debugMessage("Session \(session.id) not recommended because not all previous sessions are completed. Recommending first uncompleted session.")
                    return learn.first { !isPracticeCompleted(practiceID: $0.id) }
                }
            }
        }
        logger.debugMessage("All learn sessions are completed or none available for recommendation.")
        return nil
    }

    /// Private helper: Fallback practice from a list of free practices.
    private func fallbackPractice(from free: [AudioFile]) -> AudioFile? {
        if let fallback = free.first(where: { $0.id == "learn_001" }) {
            return fallback
        }
        return free.first
    }

    /// Returns the time interval name for a given hour.
    /// - Morning: 5:00–11:59
    /// - Noon: 12:00–15:59
    /// - Evening: 16:00–23:59 and 0:00–4:59 (grouping evening and night together)
    private func getTimeInterval(forHour hour: Int) -> String {
        if hour >= 5 && hour < 12 {
            return "Morning"
        } else if hour >= 12 && hour < 16 {
            return "Noon"
        } else {
            return "Evening"
        }
    }

    /// Checks whether a practice is relevant for the current time-of-day.
    /// If the practice has any time-of-day tag (e.g. "morning", "noon", "evening", or "night"), then it must match the current interval.
    private func isRelevant(forTimeOfDay practice: AudioFile) -> Bool {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let currentInterval = getTimeInterval(forHour: currentHour).lowercased()  // "morning", "noon", or "evening"
        let tagsLower = practice.tags.map { $0.lowercased() }
        let possibleTimeTags = ["morning", "noon", "evening", "night"]
        let hasAnyTimeTag = tagsLower.contains(where: { possibleTimeTags.contains($0) })
        if hasAnyTimeTag {
            if tagsLower.contains(currentInterval) {
                return true
            } else if currentInterval == "evening" && tagsLower.contains("night") {
                return true
            } else {
                return false
            }
        } else {
            // Universal practices without a time tag are considered relevant.
            return true
        }
    }

    /// Scores a practice by giving bonus points if it is incomplete and timely.
    private func scorePractice(_ practice: AudioFile) -> Int {
        var score = 0
        // Bonus for being incomplete (should always be true for recommended items)
        if !isPracticeCompleted(practiceID: practice.id) {
            score += 10
        }
        // Bonus for matching the current time-of-day
        let currentHour = Calendar.current.component(.hour, from: Date())
        let currentInterval = getTimeInterval(forHour: currentHour).lowercased()
        let tagsLower = practice.tags.map { $0.lowercased() }
        if tagsLower.contains(currentInterval) || (currentInterval == "evening" && tagsLower.contains("night")) {
            score += 15
        }
        // Additional scoring based on specific tags
        if practice.tags.contains(where: { $0.caseInsensitiveCompare("Relaxation") == .orderedSame }) {
            score += 10
        }
        if practice.tags.contains(where: { $0.caseInsensitiveCompare("Visualization") == .orderedSame }) {
            score += 8
        }
        if practice.tags.contains(where: { $0.caseInsensitiveCompare("Breath work") == .orderedSame || $0.caseInsensitiveCompare("Breathing") == .orderedSame }) {
            score += 5
        }
        return score
    }

    /// Checks if a practice has been completed.
    func isPracticeCompleted(practiceID: String) -> Bool {
        return completedPractices.contains(where: { $0.practiceID == practiceID })
    }

    /// Stores the recommendation in User Storage.
    private func storeRecommendation(_ practice: AudioFile?) {
        if let p = practice {
            SharedUserStorage.save(value: p.id, forKey: .lastRecommendation)
            SharedUserStorage.save(value: Date(), forKey: .lastRecommendationTime)
            logger.debugMessage("storeRecommendation => set lastRecommendation=\(p.id)")
        } else {
            SharedUserStorage.delete(forKey: .lastRecommendation)
            SharedUserStorage.delete(forKey: .lastRecommendationTime)
            logger.debugMessage("storeRecommendation => cleared last rec")
        }
    }

    // MARK: - Learning Sequence
    private func updateLearningSequenceInFirestore() {
        let done = completedPractices.map { $0.practiceID }
        let learnDone = audioFiles.filter {
            done.contains($0.id) && $0.category == .learn
        }.map { $0.id }
        FirestoreManager.shared.updateLearningSequence(["completedPractices": learnDone])
        updateCompletedLearnTag(with: learnDone)
    }

    private func updateCompletedLearnTag(with doneLearn: [String]) {
        let shortIDs = doneLearn.map { $0.replacingOccurrences(of: "learn_", with: "") }
        let joined = shortIDs.joined(separator: ",")
        if joined.count <= 256 {
            pushService.setTag(key: "completed_learn", value: joined)
        } else {
            let truncated = Array(shortIDs.prefix(50)).joined(separator: ",")
            pushService.setTag(key: "completed_learn", value: truncated)
        }
    }

    // MARK: - Onboarding Recommender
    /// Recommends a practice for onboarding based on user answers and duration.
    func recommendOnboardingPractice(
        answers: OnboardingAnswers,
        audioFiles: [AudioFile]
    ) -> AudioFile? {
        SharedUserStorage.save(value: answers, forKey: .onboardingAnswers)
        logger.debugMessage("recommendOnboardingPractice => just saved answers=\(answers)")

        let free = audioFiles.filter { !$0.premium }

        let lengthFiltered: [AudioFile]
        switch answers.length {
        case .twoMin:
            lengthFiltered = free.filter { $0.durations.contains(where: { $0.length == 2 }) }
        case .fiveMin:
            lengthFiltered = free.filter { $0.durations.contains(where: { $0.length == 5 }) }
        case .tenPlus:
            lengthFiltered = free.filter { $0.durations.contains(where: { $0.length >= 10 }) }
        }
        logger.debugMessage("Onboarding => filtered count=\(lengthFiltered.count) for \(answers.length)")

        // If the user's goal is "Sleep Better", prioritize practices with tags indicating evening/night.
        if answers.goal == .sleepBetter {
            let possible = lengthFiltered.filter { file in
                let tagsLower = file.tags.map { $0.lowercased() }
                return tagsLower.contains("evening") || tagsLower.contains("sleep") || tagsLower.contains("night")
            }
            if let firstMatching = possible.first {
                return firstMatching
            }
        }
        
        // For all other goals, check for timely candidates (based on system time)
        let timelyCandidates = lengthFiltered.filter { isRelevant(forTimeOfDay: $0) }
        if !timelyCandidates.isEmpty {
            // Choose the candidate with the highest score.
            let scored = timelyCandidates.map { ($0, scorePractice($0)) }
            if let best = scored.max(by: { $0.1 < $1.1 })?.0 {
                logger.infoMessage("Onboarding recommended timely session: \(best.id)")
                return best
            }
        }
        
        // Fallback if no timely candidate exists among the chosen duration.
        logger.infoMessage("No timely candidate found in chosen duration, using first available: \(lengthFiltered.first?.id ?? "nil")")
        return lengthFiltered.first ?? fallbackPractice(from: free)
    }
}
