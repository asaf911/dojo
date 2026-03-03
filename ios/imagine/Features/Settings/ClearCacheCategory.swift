//
//  ClearCacheCategory.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-16
//

import Foundation

enum ClearCacheCategory: CaseIterable {
    case libraryData
    case downloadedAudio
    case downloadedImages
    case completedPractices
    case sessionHistory  // Meditation session history (syncs back from Firebase)
    case onboarding   // App onboarding only
    case pathProgress // Path step completion progress
    case aiChatHistory // AI chat conversation history
    case clearUIDAndSignOut  // New case for complete reset with sign out

    var displayName: String {
        switch self {
        case .libraryData:
            return "Library Data"
        case .downloadedAudio:
            return "Downloaded Audio Files"
        case .downloadedImages:
            return "Downloaded Images"
        case .completedPractices:
            return "Completed Practices"
        case .sessionHistory:
            return "Session History"
        case .onboarding:
            return "Onboarding Data"
        case .pathProgress:
            return "Path Progress"
        case .aiChatHistory:
            return "AI Chat History"
        case .clearUIDAndSignOut:
            return "Clear UID and Sign Out"
        }
    }

    var description: String {
        switch self {
        case .libraryData:
            return "Clear locally stored metadata (audio files list)."
        case .downloadedAudio:
            return "Remove all downloaded audio files."
        case .downloadedImages:
            return "Remove all cached images."
        case .completedPractices:
            return "Reset your completed practice history."
        case .sessionHistory:
            return "Clear local meditation history. Will sync back from Firebase on next app launch."
        case .onboarding:
            return "Clear legacy onboarding recommendation data and timestamps."
        case .pathProgress:
            return "Reset Path step completion progress. Clears which steps you've completed."
        case .aiChatHistory:
            return "Clear AI chat conversation history. Start fresh with Sensei."
        case .clearUIDAndSignOut:
            return "Completely reset user identity, forget Firebase UID, and sign out. This creates a fresh user session for testing."
        }
    }

    /// Clears the cache for the given category.
    func clearCache() {
        switch self {
        case .libraryData:
            SharedUserStorage.delete(forKey: .audioFilesKey)
            logger.eventMessage("Library Data cache cleared.")
        case .downloadedAudio:
            let fileManager = FileManager.default
            if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let audioDirectory = documentsDirectory.appendingPathComponent("DownloadedAudio")
                do {
                    if fileManager.fileExists(atPath: audioDirectory.path) {
                        try fileManager.removeItem(at: audioDirectory)
                        logger.eventMessage("Downloaded audio files cleared.")
                    } else {
                        logger.eventMessage("Downloaded audio directory not found.")
                    }
                } catch {
                    logger.errorMessage("Error clearing downloaded audio files: \(error.localizedDescription)")
                }
            }
        case .downloadedImages:
            // Implement your logic to clear downloaded images.
            logger.eventMessage("Downloaded images cleared.")
        case .completedPractices:
            SharedUserStorage.delete(forKey: .completedPractices)
            logger.eventMessage("Completed practices cache cleared.")
        case .sessionHistory:
            let beforeCount = SessionHistoryManager.shared.totalSessionCount
            print("📜 HISTORY_CLEAR: Starting clear - \(beforeCount) sessions locally")
            SessionHistoryManager.shared.clearHistory()
            let afterCount = SessionHistoryManager.shared.totalSessionCount
            print("📜 HISTORY_CLEAR: Clear complete - \(afterCount) sessions remaining")
            print("📜 HISTORY_CLEAR: History will sync from Firebase on next app launch")
            logger.eventMessage("Session history cleared locally. Will sync from Firebase on next launch.")
        case .onboarding:
            // Clear legacy onboarding recommendation data and timestamps.
            SharedUserStorage.delete(forKey: .onboardingRecommendedPractice)
            SharedUserStorage.delete(forKey: .onboardingCompletionTime)
            // Force synchronization in case of caching issues.
            UserDefaults.standard.synchronize()
            logger.eventMessage("Legacy onboarding recommendation data and timestamps cleared and synchronized.")
        case .pathProgress:
            // Clear path step completion data
            // Path steps are tracked in PracticeManager.completedPractices
            // Path step IDs follow pattern: step_1, step_2, ..., step_N
            print("🧹 PATH_CLEAR [ClearCache]: .pathProgress case triggered")
            print("🧹 PATH_CLEAR [ClearCache]: Creating Task to clear path progress...")
            Task { @MainActor in
                print("🧹 PATH_CLEAR [ClearCache]: Task started on MainActor")
                
                // Get path step IDs from PathProgressManager if loaded
                let pathStepIds = PathProgressManager.shared.pathSteps.map { $0.id }
                print("🧹 PATH_CLEAR [ClearCache]: PathProgressManager has \(pathStepIds.count) path steps loaded")
                
                // Also clear by pattern in case pathSteps aren't loaded yet
                // This ensures clearing works even before Firebase fetch completes
                print("🧹 PATH_CLEAR [ClearCache]: Calling PracticeManager.clearPathStepsByPattern()...")
                PracticeManager.shared.clearPathStepsByPattern()
                
                print("🧹 PATH_CLEAR [ClearCache]: Calling PathProgressManager.refreshProgress()...")
                // Refresh the PathProgressManager to reflect the cleared state
                PathProgressManager.shared.refreshProgress()
                
                print("🧹 PATH_CLEAR [ClearCache]: After refresh - nextStep=\(PathProgressManager.shared.nextStep?.id ?? "nil"), completedCount=\(PathProgressManager.shared.completedStepCount)")
                print("🧹 PATH_CLEAR [ClearCache]: Task completed")
            }
            print("🧹 PATH_CLEAR [ClearCache]: Task dispatched (runs async)")
            logger.eventMessage("Path progress cache cleared.")
        case .aiChatHistory:
            // Clear AI chat conversation history stored in UserDefaults
            SharedUserStorage.delete(forKey: .aiChatHistory)
            logger.eventMessage("AI chat history cleared.")
            print("🧹 AI_CHAT_CLEAR: AI chat history removed from storage")
        case .clearUIDAndSignOut:
            // This is a special case that needs to be handled differently
            // It will be handled in the ClearCacheView completion handler
            logger.eventMessage("Clear UID and sign out initiated.")
        }
    }

}
