//
//  PathView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-10
//  Updated by Asaf Shamir on 2025-02-23
//  Now integrated with native interactive drag‑to‑pop gesture and subscription sheet trigger
//

import SwiftUI
import UIKit

struct PathView: View {
    @Binding var showCommunitySheet: Bool
    @Binding var source: String?
    
    @ObservedObject private var progressManager = PathProgressManager.shared
    @State private var navigateToPlayer: Bool = false
    @State private var isDownloading: Bool = false
    
    // Observables
    @EnvironmentObject var audioPlayerManager: AudioPlayerManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @ObservedObject var practiceManager = PracticeManager.shared
    @ObservedObject var bpmTracker = PracticeBPMTracker.shared
    
    // Menu toggle environment
    @Environment(\.toggleMenu) private var toggleMenu
    
    let userName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Use presentationMode for the custom back button.
    @Environment(\.presentationMode) var presentationMode
    
    // State for handling pending path step
    @State private var pendingPathStep: PathStep?
    
    // Path steps with the "coming soon" placeholder appended
    private var pathStepsWithComingSoon: [PathStep] {
        var steps = progressManager.pathSteps
        // Add the "coming soon" system step as the last step
        let maxOrder = steps.map { $0.order }.max() ?? 0
        let nextOrder = maxOrder + 1
        let comingSoonStep = PathStep(
            id: "coming_soon_\(nextOrder)",
            title: "Coming soon...",
            description: "More meditation content is on the way",
            audioUrl: "",
            duration: -1,
            imageUrl: "",
            order: nextOrder,
            premium: false,
            isLesson: false
        )
        steps.append(comingSoonStep)
        return steps
    }

    var body: some View {
        DojoScreenContainer(
            headerTitle: "The Path",
            headerSubtitle: nil,
            backgroundImageName: "PathBackground",
            backAction: { presentationMode.wrappedValue.dismiss() },
            showBackButton: false,
            menuAction: toggleMenu,
            showMenuButton: true
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Use our dedicated PathGalleryView for the Path feature
                PathGalleryView(
                    pathSteps: pathStepsWithComingSoon,
                    selectedFile: $audioPlayerManager.selectedFile,
                    audioPlayerManager: audioPlayerManager,
                    subscriptionManager: subscriptionManager
                )
            }
        }
        .onAppear {
            fetchSubscriptionStatus()
            progressManager.loadPathSteps()
            checkForPendingPathStep()
        }
        .onDisappear {
        }
        .navigationBarBackButtonHidden(true)
        // Enable interactive pop by embedding an accessor view that sets the gesture delegate.
        .background(InteractivePopGestureSetter())
    }
    
    // MARK: - Helper Functions for PathView
    
    private func shouldShowPracticeSummary() -> Bool {
        return audioPlayerManager.didJustFinishSession
    }
    
    private func completionRatePercent() -> Double {
        guard audioPlayerManager.totalDuration > 0 else { return 0 }
        return (audioPlayerManager.currentTime / audioPlayerManager.totalDuration) * 100
    }
    
    private func practiceDurationMinutes() -> Int {
        Int(ceil(audioPlayerManager.totalDuration / 60.0))
    }
    
    private func finalStartBPM() -> Double {
        return bpmTracker.startBPM
    }
    
    private func finalEndBPM() -> Double {
        return bpmTracker.endBPM
    }
    
    private func dismissSummary() {
        withAnimation {
            navigationCoordinator.resetPracticeRating()
            bpmTracker.resetData()
            audioPlayerManager.didJustFinishSession = false
            navigationCoordinator.showPracticeRating = false
        }
    }
    
    private func fetchSubscriptionStatus() {
        subscriptionManager.refreshSubscriptionStatus()
    }
    
    // Check if there's a pending path step to handle
    private func checkForPendingPathStep() {
        // Check if there's a pending path step ID stored
        if let pendingStepId = SharedUserStorage.retrieve(forKey: .pendingPathStepId, as: String.self) {
            // Log that we found a pending step
            logger.eventMessage("PathView: Found pending path step ID: \(pendingStepId)")
            
            // Minimal delay to ensure view is ready but transition feels immediate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Find the matching path step
                if let matchingStep = progressManager.pathSteps.first(where: { $0.id == pendingStepId }) {
                    // Log that we found the matching step
                    logger.eventMessage("PathView: Found matching path step: \(matchingStep.title)")
                    
                    // Store the path step for use in handlePendingPathStep
                    self.pendingPathStep = matchingStep
                    
                    // Handle the pending path step immediately
                    handlePendingPathStep()
                    // Clear the stored ID after handling
                    SharedUserStorage.delete(forKey: .pendingPathStepId)
                } else {
                    logger.eventMessage("PathView: Could not find matching path step for ID: \(pendingStepId)")
                    // Clean up if we couldn't find the step
                    SharedUserStorage.delete(forKey: .pendingPathStepId)
                }
            }
        }
    }
    
    // Handle the pending path step directly using NavigationCoordinator
    private func handlePendingPathStep() {
        guard let step = pendingPathStep else { return }
        
        // Convert PathStep to AudioFile
        let audioFile = step.toAudioFile()
        
        // Log that we're handling the pending step
        logger.eventMessage("PathView: Handling pending path step: \(step.title) with NavigationCoordinator")
        
        // Check subscription gate (post-first-session, not subscribed)
        if subscriptionManager.shouldGatePlay {
            subscriptionManager.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=PathView")
            #endif
            navigationCoordinator.subscriptionSource = .pathStep
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        
        // Fade out background music over 2 seconds
        GeneralBackgroundMusicController.shared.fadeOutMusic(duration: 2.0)
        
        // Set the audio file directly first
        audioPlayerManager.selectedFile = audioFile
        
        // Set up SessionContextManager for the path session
        SessionContextManager.shared.setupPathSession(
            entryPoint: .pathScreen,
            pathStep: step,
            origin: .userSelected
        )
        
        // Track analytics
        AnalyticsManager.shared.logEvent("path_step_tapped_from_path_view", parameters: [
            "step_id": step.id,
            "step_title": step.title,
            "step_order": step.order,
            "is_premium": step.premium,
            "is_lesson": step.isLesson
        ])
        
        // Store current date as last session date
        SharedUserStorage.save(value: Date(), forKey: .lastMeditationDate)
        
        // Use NavigationCoordinator directly to show the player
        navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
        
        // Reset the pending path step
        pendingPathStep = nil
    }
}

struct PathView_Previews: PreviewProvider {
    @State static var showCommunitySheet = false
    @State static var source: String? = nil
    
    static var previews: some View {
        PathView(showCommunitySheet: $showCommunitySheet, source: $source)
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(NavigationCoordinator())
            .environmentObject(AudioPlayerManager())
            .environmentObject(PracticeManager.shared)
            .background(Color.backgroundDarkPurple)
    }
}
