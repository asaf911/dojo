//
//  PracticeTapHandler.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-23
//

import SwiftUI
import UIKit

struct PracticeTapHandler {

    static func handlePracticeTap(
        audioFile: AudioFile,
        navigateToPlayer: Binding<Bool>,
        selectedFile: Binding<AudioFile?>,
        audioPlayerManager: AudioPlayerManager,
        isDownloading: Binding<Bool>,
        showSubscriptionView: Binding<Bool>,
        subscriptionManager: SubscriptionManager
    ) {
        HapticManager.shared.impact(.light)
        
        logger.eventMessage("DEBUG: Tapped on audio file: \(audioFile.title)")

        // 📊 Reset BPM tracker state for new practice (but don't start tracking yet)
        // Actual tracking will start when audio begins playing in AudioPlayerManager.play()
        PracticeBPMTracker.shared.resetData()
        print("🎯 PracticeTapHandler: RESET BPM tracker for new practice: '\(audioFile.title)' (tracking will start when audio plays)")

        // Fade out background music over 1 second
        // This will set muted state for current session but not affect user preference
        GeneralBackgroundMusicController.shared.fadeOutForPractice()

        // Step 1: Check subscription gate (post-first-session, not subscribed)
        checkSubscriptionStatus(subscriptionManager: subscriptionManager) {
            DispatchQueue.main.async {
                if subscriptionManager.shouldGatePlay {
                    subscriptionManager.logGateState()
                    #if DEBUG
                    print("📊 [SUBSCRIPTION_GATE] Play blocked — source=PracticeTapHandler")
                    #endif
                    logger.eventMessage("DEBUG: Play gated. Navigating to SubscriptionView.")
                    showSubscriptionView.wrappedValue = true
                } else {
                    // First update the selected file and navigate to player immediately
                    selectedFile.wrappedValue = audioFile
                    audioPlayerManager.selectedFile = audioFile
                    navigateToPlayer.wrappedValue = true
                    
                    // Then initiate download in the background if needed
                    startPracticePreload(
                        audioFile: audioFile,
                        audioPlayerManager: audioPlayerManager,
                        isDownloading: isDownloading
                    )
                }
            }
        }
    }

    private static func checkSubscriptionStatus(subscriptionManager: SubscriptionManager, completion: @escaping () -> Void) {
        subscriptionManager.refreshSubscriptionStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completion()
        }
    }

    private static func startPracticePreload(
        audioFile: AudioFile,
        audioPlayerManager: AudioPlayerManager,
        isDownloading: Binding<Bool>
    ) {
        // Set downloading flag to show loading indicator in PlayerScreenView
        isDownloading.wrappedValue = true
        
        // Start preloading
        let durationIndex = 0  // Default duration index
        logger.eventMessage("DEBUG: Preloading audio player for: \(audioFile.title)")
        
        audioPlayerManager.preloadAudioFile(file: audioFile, durationIndex: durationIndex) {
            DispatchQueue.main.async {
                logger.eventMessage("DEBUG: Preload finished for: \(audioFile.title)")
                isDownloading.wrappedValue = false
            }
        }
    }
}
