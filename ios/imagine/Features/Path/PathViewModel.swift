//
//  PathViewModel.swift
//  imagine
//
//  Deprecated: This ViewModel now delegates to PathProgressManager.
//  Kept for backward compatibility with views that still use it.
//

import Foundation
import Combine

@MainActor
class PathViewModel: ObservableObject {
    @Published var pathSteps: [PathStep] = []
    @Published var audioFiles: [AudioFile] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to PathProgressManager changes
        PathProgressManager.shared.$pathSteps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] steps in
                guard let self = self else { return }
                // Add the regular steps from PathProgressManager
                self.pathSteps = steps
                // Add the "coming soon" system step
                self.appendComingSoonStep()
                // Create audio files from all steps
                self.audioFiles = self.pathSteps.map { $0.toAudioFile() }
            }
            .store(in: &cancellables)
    }
    
    func loadPathSteps() {
        // Delegate to the unified PathProgressManager
        PathProgressManager.shared.loadPathSteps()
    }
    
    /// Adds a "coming soon" system step at the end of the path steps list
    private func appendComingSoonStep() {
        // Find the highest order number in the current steps
        let maxOrder = pathSteps.map { $0.order }.max() ?? 0
        let nextOrder = maxOrder + 1
        
        // Create the "coming soon" step
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
        
        // Add the step to the end of the array
        pathSteps.append(comingSoonStep)
    }
}
