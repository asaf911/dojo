//
//  AppFunctions.swift
//
//  Utility functions for the app, including caching of audio files and clearing cache.
//

import Foundation
import FirebaseStorage
import AVFoundation
import Kingfisher

class AppFunctions {
    
    // Cache for loaded audio files
    private static let cacheDuration: TimeInterval = 60 * 60 * 24 // 24 hours
    private static var cachedAudioFiles: [AudioFile]?
    private static var lastLoadTime: Date?
    
    // MARK: - Existing Utility Functions
    static func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    static func formatTimeInMinutes(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        return "\(minutes)"
    }
    
    static func loadAudioFiles(forceFetch: Bool = false, completion: @escaping ([AudioFile]) -> Void) {
        // If we have cached files and they're not expired, use them
        if let cachedFiles = cachedAudioFiles,
           let lastLoad = lastLoadTime,
           !forceFetch,
           Date().timeIntervalSince(lastLoad) < cacheDuration {
            completion(cachedFiles)
            return
        }

        let lastFetchTime = SharedUserStorage.retrieve(forKey: .lastFetchTime, as: Date.self) ?? Date.distantPast
        let currentTime = Date()
        let threshold: TimeInterval = 24 * 60 * 60 // 24 hours

        // Check if we need to fetch new data
        if forceFetch || (currentTime.timeIntervalSince(lastFetchTime) > threshold && ConnectivityHelper.isConnectedToInternet()) {
            fetchAudioFilesFromServer(completion: completion)
        } else {
            fetchAudioFilesLocally(with: nil, completion: completion)
        }
    }
    
    private static func fetchAudioFilesFromServer(completion: @escaping ([AudioFile]) -> Void) {
        let storage = Storage.storage()
        let storageRef = storage.reference(forURL: serverPath() + Config.audioFileJsonFileName)
        
        storageRef.getData(maxSize: 10 * 1024 * 1024) { data, error in
            if let error = error {
                fetchAudioFilesLocally(with: error, completion: completion)
                return
            }
            
            guard let data = data else {
                let dataError = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data is nil after fetching from server"])
                fetchAudioFilesLocally(with: dataError, completion: completion)
                return
            }
            
            logger.eventMessage("Fetched audioFiles.json from server, data length: \(data.count)")
            if let dataString = String(data: data, encoding: .utf8) {
                logger.eventMessage("Data fetched from server: \(dataString)")
            }
            
            do {
                let decoder = JSONDecoder()
                let audioFiles = try decoder.decode([AudioFile].self, from: data)
                logger.eventMessage("Successfully decoded audio files from server.")
                processImageURLs(for: audioFiles) { updatedAudioFiles in
                    DispatchQueue.main.async {
                        saveAudioFilesToCache(updatedAudioFiles, withTimeStamp: true)
                        cachedAudioFiles = updatedAudioFiles
                        lastLoadTime = Date()
                        completion(updatedAudioFiles)
                    }
                }
            } catch {
                logger.eventMessage("Decoding error when decoding audio files from server: \(error.localizedDescription)")
                if let decodingError = error as? DecodingError {
                    printDecodingError(decodingError)
                }
                fetchAudioFilesLocally(with: error, completion: completion)
            }
        }
    }
    
    private static func saveAudioFilesToCache(_ audioFiles: [AudioFile], withTimeStamp: Bool) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(audioFiles)
            
            // Save to UserDefaults
            SharedUserStorage.save(value: data, forKey: .audioFilesKey)
            if withTimeStamp {
                SharedUserStorage.save(value: Date(), forKey: .lastFetchTime)
            }
            logger.eventMessage("Saved audio files to UserDefaults.")
        } catch {
            logger.eventMessage("Failed to save audio files to cache: \(error.localizedDescription)")
        }
    }
    
    private static func loadAudioFilesFromCache() -> [AudioFile]? {
        if let data = SharedUserStorage.retrieve(forKey: .audioFilesKey, as: Data.self) {
            do {
                let decoder = JSONDecoder()
                let audioFiles = try decoder.decode([AudioFile].self, from: data)
                return audioFiles
            } catch {
                logger.eventMessage("Failed to load audio files from cache: \(error.localizedDescription)")
            }
        }
        return nil
    }
    
    private static func loadLocalAudioFiles(completion: @escaping ([AudioFile]) -> Void) {
        guard let url = Bundle.main.url(forResource: "audioFiles", withExtension: "json") else {
            logger.eventMessage("Failed to locate local audioFiles.json in bundle.")
            completion([])
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            logger.eventMessage("Loaded local audioFiles.json, data length: \(data.count)")
            if let dataString = String(data: data, encoding: .utf8) {
                logger.eventMessage("Data loaded from local file: \(dataString)")
            }
            let decoder = JSONDecoder()
            let audioFiles = try decoder.decode([AudioFile].self, from: data)
            logger.eventMessage("Successfully decoded local audio files.")
            processImageURLs(for: audioFiles) { updatedAudioFiles in
                DispatchQueue.main.async {
                    saveAudioFilesToCache(updatedAudioFiles, withTimeStamp: false)
                    completion(updatedAudioFiles)
                }
            }
        } catch {
            logger.eventMessage("Failed to decode local audioFiles.json: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                printDecodingError(decodingError)
            }
            completion([])
        }
    }
    
    private static func processImageURLs(for audioFiles: [AudioFile], completion: @escaping ([AudioFile]) -> Void) {
        var updatedAudioFiles = audioFiles
        let dispatchGroup = DispatchGroup()
        
        for index in updatedAudioFiles.indices {
            if let imageFile = updatedAudioFiles[index].imageFile, imageFile.hasPrefix(serverPath()) {
                dispatchGroup.enter()
                let storageRef = Storage.storage().reference(forURL: imageFile)
                storageRef.downloadURL { url, error in
                    if let error = error {
                        logger.eventMessage("Failed to download image URL: \(error.localizedDescription)")
                    } else if let url = url {
                        updatedAudioFiles[index].imageFile = url.absoluteString
                    }
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(updatedAudioFiles)
        }
    }
    
    private static func fetchAudioFilesLocally(with error: Error?, completion: @escaping ([AudioFile]) -> Void) {
        if let error = error {
            logger.eventMessage("Failed to fetch audio files: \(error.localizedDescription)")
        }
        if let cachedAudioFiles = loadAudioFilesFromCache() {
            logger.eventMessage("Using cached audio files from UserDefaults.")
            self.cachedAudioFiles = cachedAudioFiles
            lastLoadTime = Date()
            completion(cachedAudioFiles)
        } else {
            logger.eventMessage("Loading local audio files.")
            loadLocalAudioFiles(completion: completion)
        }
    }
    
    // MARK: - New Clearing Functions
    
    private static func clearLibraryData() {
        SharedUserStorage.delete(forKey: .audioFilesKey)
        SharedUserStorage.delete(forKey: .lastFetchTime)
        // Also clear in-memory cache so the next loadAudioFiles() call fetches from server
        cachedAudioFiles = nil
        lastLoadTime = nil
        logger.eventMessage("Cleared library data (audioFiles & lastFetchTime) from UserDefaults and in-memory cache.")
    }
    
    private static func clearDownloadedAudioFiles() {
        let fileManager = FileManager.default
        let documentsDirectory = FileManagerHelper.shared.getDocumentsDirectory()
        
        do {
            let mp3Files = try fileManager.contentsOfDirectory(atPath: documentsDirectory.path)
            mp3Files.forEach { file in
                if file.hasSuffix(".mp3") {
                    let filePath = documentsDirectory.appendingPathComponent(file)
                    if fileManager.fileExists(atPath: filePath.path) {
                        do {
                            try fileManager.removeItem(at: filePath)
                            logger.eventMessage("Cleared downloaded audio file: \(file)")
                        } catch {
                            logger.eventMessage("Failed to clear \(file): \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            logger.eventMessage("Failed to retrieve contents of documents directory: \(error.localizedDescription)")
        }
    }
    
    private static func clearDownloadedImages() {
        // Clear Kingfisher cache
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache {
            logger.eventMessage("Cleared Kingfisher disk cache.")
        }
        
        let fileManager = FileManager.default
        let documentsDirectory = FileManagerHelper.shared.getDocumentsDirectory()
        
        do {
            let imageFiles = try fileManager.contentsOfDirectory(atPath: documentsDirectory.path)
            imageFiles.forEach { file in
                if file.hasSuffix(".jpg") || file.hasSuffix(".png") {
                    let filePath = documentsDirectory.appendingPathComponent(file)
                    if fileManager.fileExists(atPath: filePath.path) {
                        do {
                            try fileManager.removeItem(at: filePath)
                            logger.eventMessage("Cleared downloaded image: \(file)")
                        } catch {
                            logger.eventMessage("Failed to clear \(file): \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            logger.eventMessage("Failed to retrieve image files in documents directory: \(error.localizedDescription)")
        }
    }
    
    private static func clearCompletedPractices() {
        PracticeManager.shared.clearCompletedPractices()
        logger.eventMessage("Cleared completed practices.")
    }
    
    // Public method to clear selected categories
    static func clearCache(categories: [ClearCacheCategory]) {
        if categories.contains(.libraryData) {
            clearLibraryData()
        }
        if categories.contains(.downloadedAudio) {
            clearDownloadedAudioFiles()
        }
        if categories.contains(.downloadedImages) {
            clearDownloadedImages()
        }
        if categories.contains(.completedPractices) {
            clearCompletedPractices()
        }
        if categories.contains(.sessionHistory) {
            print("📜 HISTORY_CLEAR: AppFunctions triggering session history clear...")
            SessionHistoryManager.shared.clearHistory()
            print("📜 HISTORY_CLEAR: Session history cleared - Firebase will restore on next launch")
        }
        if categories.contains(.onboarding) {
            // Legacy onboarding data cleared elsewhere; flag no longer maintained.
            UserDefaults.standard.synchronize()
            logger.eventMessage("Legacy onboarding flag no longer used; nothing additional to clear.")
        }
        if categories.contains(.pathProgress) {
            print("🧹 PATH_CLEAR [AppFunctions]: Clearing path progress...")
            // Clear path step completions from PracticeManager (both memory and storage)
            PracticeManager.shared.clearPathStepsByPattern()
            // Refresh PathProgressManager to recalculate next step
            Task { @MainActor in
                PathProgressManager.shared.refreshProgress()
                print("🧹 PATH_CLEAR [AppFunctions]: PathProgressManager refreshed, nextStep=\(PathProgressManager.shared.nextStep?.id ?? "nil")")
            }
        }
        if categories.contains(.aiChatHistory) {
            print("🧹 AI_CHAT_CLEAR [AppFunctions]: Clearing AI chat history...")
            SharedUserStorage.delete(forKey: .aiChatHistory)
        }
        logger.eventMessage("Clear cache operation completed for categories: \(categories.map { $0.displayName }.joined(separator: ", "))")
    }
    
    // Helper function for error printing
    private static func printDecodingError(_ error: DecodingError) {
        switch error {
        case .typeMismatch(let type, let context):
            logger.eventMessage("Type mismatch error: \(type), \(context.debugDescription)")
            logger.eventMessage("Coding path: \(context.codingPath)")
        case .valueNotFound(let type, let context):
            logger.eventMessage("Value not found error: \(type), \(context.debugDescription)")
            logger.eventMessage("Coding path: \(context.codingPath)")
        case .keyNotFound(let key, let context):
            logger.eventMessage("Key not found error: \(key), \(context.debugDescription)")
            logger.eventMessage("Coding path: \(context.codingPath)")
        case .dataCorrupted(let context):
            logger.eventMessage("Data corrupted error: \(context.debugDescription)")
            logger.eventMessage("Coding path: \(context.codingPath)")
        @unknown default:
            logger.eventMessage("Unknown decoding error: \(error)")
        }
    }
    
    private static func serverPath() -> String {
        #if DEVENV
        return Config.storagePathPrefix + Config.devServerPath
        #else
        return Config.storagePathPrefix + Config.productionServerPath
        #endif
    }
}

// MARK: - Notification.Name extension
extension Notification.Name {
    static let didUpdateCumulativeMeditationTime = Notification.Name("didUpdateCumulativeMeditationTime")
    static let didUpdateMeditationStreak = Notification.Name("didUpdateMeditationStreak")
    static let didUpdateLongestMeditationStreak = Notification.Name("didUpdateLongestMeditationStreak")
    static let didUpdateSessionCount = Notification.Name("didUpdateSessionCount")
    static let didUpdateAverageSessionDuration = Notification.Name("didUpdateAverageSessionDuration")
    static let didUpdateLongestSessionDuration = Notification.Name("didUpdateLongestSessionDuration")
    static let didUpdateAudioFiles = Notification.Name("didUpdateAudioFiles") // Ensure this is included
    static let onboardingCompleted = NSNotification.Name("onboardingCompleted")
    static let didLogPracticeEvent = Notification.Name("didLogPracticeEvent")
    static let subscriptionStatusUpdated = Notification.Name("subscriptionStatusUpdated")
    static let aiOnboardingCleared = Notification.Name("aiOnboardingCleared")
    static let aiScrollTrigger = Notification.Name("aiScrollTrigger") // Trigger scroll when dynamic content appears
    static let aiTriggerSubscription = Notification.Name("aiTriggerSubscription") // Trigger subscription flow when unsubscribed user requests meditation
    static let aiPathGuidanceRecommendation = Notification.Name("aiPathGuidanceRecommendation") // Path guidance recommendation from AI
    static let aiExploreGuidanceRecommendation = Notification.Name("aiExploreGuidanceRecommendation") // Explore session recommendation from AI
    static let practiceCompletedNotification = Notification.Name("practiceCompletedNotification")
    static let pathStepCompletedNotification = Notification.Name("pathStepCompletedNotification")
}
