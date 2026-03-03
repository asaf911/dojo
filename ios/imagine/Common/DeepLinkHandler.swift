//
//  DeepLinkHandler.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-27
//

import Foundation
import SwiftUI

class DeepLinkHandler {
    
    // Handles incoming URLs and navigates to the appropriate screen.
    static func handleIncomingURL(_ url: URL, source: String = "universalLink", eventName: String = "deep_link_open", navigationCoordinator: NavigationCoordinator) {
        logger.eventMessage("Deep link received: \(url.absoluteString)")
        
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = urlComponents?.queryItems
        
        // Check if the URL uses abbreviated deep link parameters ("dur" key)
        if let _ = queryItems?.first(where: { $0.name == "dur" })?.value {
            logger.eventMessage("Deep link contains abbreviated meditation configuration parameters.")
            // Ensure catalogs are loaded before decoding so ids (bs, bb, cues) resolve to models
            let group = DispatchGroup()
            group.enter()
            CatalogsManager.shared.fetchCatalogs(triggerContext: "DeepLinkHandler|incoming link resolve") { _ in group.leave() }
            group.notify(queue: .main) {
                guard let queryItems = urlComponents?.queryItems,
                      let meditationConfiguration = MeditationConfiguration(queryItems: queryItems) else {
                    logger.errorMessage("Failed to parse MeditationConfiguration from deep link after prefetch.")
                    return
                }
                let mirror = Mirror(reflecting: meditationConfiguration)
                var bbId: String = "None"
                if let beatChild = mirror.children.first(where: { $0.label == "binauralBeat" }) {
                    let beatMirror = Mirror(reflecting: beatChild.value)
                    if let id = beatMirror.children.first(where: { $0.label == "id" })?.value as? String {
                        bbId = id
                    }
                }
                logger.eventMessage("Parsed meditation configuration from deep link after prefetch: dur=\(meditationConfiguration.duration) bs=\(meditationConfiguration.backgroundSound.id) bb=\(bbId) cues=\(meditationConfiguration.cueSettings.count)")
                navigationCoordinator.applyDeepLinkMeditationConfiguration(meditationConfiguration)
            }
            return
        }
        
        // Fallback: check for practiceId deep links (unchanged)
        if let practiceId = queryItems?.first(where: { $0.name == "practiceId" })?.value {
            logger.eventMessage("Extracted Practice ID: \(practiceId)")
            DispatchQueue.main.async {
                // First navigate to main view
                navigationCoordinator.navigateTo(.main)
                
                findAudioFile(by: practiceId) { audioFile in
                    if let audioFile = audioFile {
                        logger.eventMessage("Audio file found for deep link: \(audioFile.id)")
                        
                        // Check if we're already in player view
                        if case .player(let currentFile, _, _) = navigationCoordinator.currentView {
                            // We're already in the player - update the current view instead of navigating again
                            logger.eventMessage("Already in player view with file: \(currentFile.id), updating to: \(audioFile.id)")
                            // Fade out background music before updating player
                            GeneralBackgroundMusicController.shared.fadeOutForPractice()
                            navigationCoordinator.currentView = .player(audioFile: audioFile, durationIndex: 0, isDownloading: true)
                        } else {
                            // Navigate to player normally
                            // Fade out background music before navigating to player
                            GeneralBackgroundMusicController.shared.fadeOutForPractice()
                            navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
                        }
                    } else {
                        logger.eventMessage("No audio file found for Practice ID: \(practiceId)")
                    }
                }
            }
        } else {
            logger.eventMessage("No valid practiceId found in deep link URL.")
        }
    }
    
    // Handles deep links from push notifications with retargeting support.
    static func handleDeepLinkFromPushNotification(_ url: URL, navigationCoordinator: NavigationCoordinator) {
        logger.eventMessage("Handling push notification deep link: \(url.absoluteString)")
        handleIncomingURL(url, source: "pushNotification", eventName: "push_deep_link_open", navigationCoordinator: navigationCoordinator)
    }

    // Finds an audio file by its practiceId, searching both regular audio files and Path steps.
    static func findAudioFile(by practiceId: String, completion: @escaping (AudioFile?) -> Void) {
        // First search in regular audio files
        AppFunctions.loadAudioFiles { audioFiles in
            if let foundAudioFile = audioFiles.first(where: { $0.id == practiceId }) {
                completion(foundAudioFile)
                return
            }
            
            // If not found in regular audio files, search in Path steps
            findPathStepAudioFile(by: practiceId, completion: completion)
        }
    }
    
    // Finds a Path step by its practiceId and converts it to AudioFile.
    private static func findPathStepAudioFile(by practiceId: String, completion: @escaping (AudioFile?) -> Void) {
        // First try to use cached Path steps from PathProgressManager (MainActor)
        Task { @MainActor in
            let cachedPathSteps = PathProgressManager.shared.pathSteps
            if !cachedPathSteps.isEmpty {
                if let foundPathStep = cachedPathSteps.first(where: { $0.id == practiceId }) {
                    let audioFile = foundPathStep.toAudioFile()
                    completion(audioFile)
                    return
                }
                // If not found in cache, return nil
                completion(nil)
                return
            }
            
            // If no cached data, fetch Path steps from server
            FirestoreManager.shared.fetchPathSteps { response in
                guard let steps = response?.steps else {
                    logger.eventMessage("No Path steps found for Practice ID: \(practiceId)")
                    completion(nil)
                    return
                }
                
                if let foundPathStep = steps.first(where: { $0.id == practiceId }) {
                    let audioFile = foundPathStep.toAudioFile()
                    logger.eventMessage("Path step found for deep link: \(foundPathStep.id)")
                    completion(audioFile)
                } else {
                    logger.eventMessage("No Path step found for Practice ID: \(practiceId)")
                    completion(nil)
                }
            }
        }
    }
}
