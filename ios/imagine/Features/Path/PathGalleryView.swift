//
//  PathGalleryView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-04-25
//

import SwiftUI

struct PathGalleryView: View {
    // Path steps to display
    let pathSteps: [PathStep]
    
    // Bindings and objects required for navigation and playback
    @Binding var selectedFile: AudioFile?
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    @ObservedObject var subscriptionManager: SubscriptionManager
    
    // Use the unified PathProgressManager for step states
    @ObservedObject private var progressManager = PathProgressManager.shared
    
    var body: some View {
        // Main scrollable content with mask
        ScrollView(.vertical, showsIndicators: false) {
            // Top spacer to prevent content starting in faded state
            Spacer().frame(height: 5)
            // Apply a mask to the entire content to create the fade effect
            HStack(alignment: .top, spacing: 7) {
                // Left column
                VStack(spacing: 150) {
                    //Spacer().frame(height: 30)
                    ForEach(getLeftColumnSteps()) { step in
                        PathStepView(
                            pathStep: step,
                            selectedFile: $selectedFile,
                            audioPlayerManager: audioPlayerManager,
                            subscriptionManager: subscriptionManager,
                            stepState: getStepState(for: step)
                        )
                        .id(step.id)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Right column - starts with offset
                VStack(spacing: 150) {
                    // Replace the flexible Spacer with a fixed height spacer
                    Spacer().frame(height: 30)  // Fixed 60pt offset at the top
                    
                    ForEach(getRightColumnSteps()) { step in
                        PathStepView(
                            pathStep: step,
                            selectedFile: $selectedFile,
                            audioPlayerManager: audioPlayerManager,
                            subscriptionManager: subscriptionManager,
                            stepState: getStepState(for: step)
                        )
                        .id(step.id)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 26)
            // Footer clearance handled by DojoScreenContainer
            .padding(.bottom, HeaderLayout.footerClearance)
        }
        .topFadeMask(height: 5)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    // Helper functions to split steps into left and right columns
    private func getLeftColumnSteps() -> [PathStep] {
        let sortedSteps = pathSteps.sorted(by: { $0.order < $1.order })
        return stride(from: 0, to: sortedSteps.count, by: 2).map { sortedSteps[$0] }
    }
    
    private func getRightColumnSteps() -> [PathStep] {
        let sortedSteps = pathSteps.sorted(by: { $0.order < $1.order })
        return stride(from: 1, to: sortedSteps.count, by: 2).map { sortedSteps[$0] }
    }
    
    // Determine the state of each step based on completion status and order
    private func getStepState(for step: PathStep) -> PathStepState {
        return progressManager.getStepState(for: step)
    }
}

// PathProgressEngine is now consolidated in PathProgressManager.swift

struct PathGalleryView_Previews: PreviewProvider {
    static var samplePathSteps: [PathStep] = [
        PathStep(
            id: "step_1",
            title: "What Is Meditation?",
            description: "Begin your journey with the fundamentals of meditation",
            audioUrl: "gs://imagine-c6162.appspot.com/Path/Step_1-What_Is_Meditation.mp3",
            duration: 5,
            imageUrl: "gs://imagine-c6162.appspot.com/practice_images/Deep Body Scan.png",
            order: 1,
            premium: false,
            isLesson: true
        ),
        PathStep(
            id: "step_2",
            title: "First Practice",
            description: "Learn to focus on your breath",
            audioUrl: "gs://imagine-c6162.appspot.com/Path/Step_2-First_Practice.mp3",
            duration: 10,
            imageUrl: "gs://imagine-c6162.appspot.com/practice_images/Deep Body Scan.png",
            order: 2,
            premium: false,
            isLesson: true
        ),
        PathStep(
            id: "step_3",
            title: "The Art of Relaxation",
            description: "Discover deep relaxation through body awareness",
            audioUrl: "gs://imagine-c6162.appspot.com/Path/Step_3-The_Art_of_Relaxation.mp3",
            duration: 5,
            imageUrl: "gs://imagine-c6162.appspot.com/practice_images/Deep Body Scan.png",
            order: 3,
            premium: true,
            isLesson: false
        ),
        PathStep(
            id: "step_4",
            title: "Deep Body Scan",
            description: "Discover deep relaxation through body awareness",
            audioUrl: "gs://imagine-c6162.appspot.com/Path/Step_4-Deep_Body_Scan.mp3",
            duration: 10,
            imageUrl: "gs://imagine-c6162.appspot.com/practice_images/Deep Body Scan.png",
            order: 4,
            premium: true,
            isLesson: false
        )
    ]
    
    static var previews: some View {
        PathGalleryView(
            pathSteps: samplePathSteps,
            selectedFile: .constant(nil),
            audioPlayerManager: AudioPlayerManager(),
            subscriptionManager: SubscriptionManager.shared
        )
        .environmentObject(NavigationCoordinator())
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.backgroundDarkPurple)
    }
}
