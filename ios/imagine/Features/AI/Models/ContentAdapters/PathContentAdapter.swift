//
//  PathContentAdapter.swift
//  imagine
//
//  Created for Clean Recommendation Card Architecture
//
//  Adapts PathStep to the MeditationContent protocol,
//  enabling unified card rendering for path step recommendations.
//

import Foundation
import SwiftUI

// MARK: - Path Content Adapter

/// Wraps a PathStep to conform to MeditationContent protocol
struct PathContentAdapter: MeditationContent {
    
    // MARK: - Original Data
    
    /// The underlying PathStep data
    let pathStep: PathStep
    
    /// Whether this step is completed (stored at creation time)
    let isCompleted: Bool
    
    // MARK: - MeditationContent Conformance
    
    var contentId: String {
        pathStep.id
    }
    
    var contentTitle: String {
        pathStep.title
    }
    
    var contentDescription: String {
        pathStep.description
    }
    
    var durationMinutes: Int {
        pathStep.duration
    }
    
    var contentType: MeditationContentType {
        .path
    }
    
    var primaryLabel: String {
        "Step \(pathStep.order)"
    }
    
    var secondaryLabel: String? {
        "The Path"
    }
    
    var typeLabel: String {
        pathStep.isLesson ? "Lesson" : "Practice"
    }
    
    var backgroundImageURL: URL? {
        // Path cards use static asset, not URL
        nil
    }
    
    // MARK: - Factory Methods
    
    /// Create adapter with completion status from PathProgressManager
    /// Must be called from MainActor context (e.g., SwiftUI View body)
    @MainActor
    static func createSync(from pathStep: PathStep, progressManager: PathProgressManager) -> PathContentAdapter {
        let completed = progressManager.isStepCompleted(pathStep.id)
        return PathContentAdapter(pathStep: pathStep, isCompleted: completed)
    }
    
    /// Create adapter with explicit completion status
    static func create(from pathStep: PathStep, isCompleted: Bool) -> PathContentAdapter {
        PathContentAdapter(pathStep: pathStep, isCompleted: isCompleted)
    }
}
