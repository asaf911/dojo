//
//  PreviewMeditationContent.swift
//  imagine
//
//  Created for Clean Recommendation Card Architecture
//
//  Preview helpers for displaying card previews in Xcode Canvas.
//

import SwiftUI

#if DEBUG
/// Sample meditation content for SwiftUI previews
enum PreviewMeditationContent {
    
    // MARK: - Path Content
    
    static var pathIncomplete: MeditationContent {
        PreviewPathContent(
            contentId: "path_step_1",
            contentTitle: "Introduction to Meditation",
            contentDescription: "Learn the fundamentals of meditation practice and begin your journey to mindfulness.",
            durationMinutes: 10,
            primaryLabel: "Step 1",
            secondaryLabel: "The Path",
            typeLabel: "Lesson"
        )
    }
    
    static var pathCompleted: MeditationContent {
        PreviewPathContent(
            contentId: "path_step_2",
            contentTitle: "Deep Breathing Techniques",
            contentDescription: "Master essential breathing exercises for relaxation and focus.",
            durationMinutes: 15,
            primaryLabel: "Step 2",
            secondaryLabel: "The Path",
            typeLabel: "Practice"
        )
    }
    
    // MARK: - PreRecorded Content
    
    static var preRecorded: MeditationContent {
        PreviewPreRecordedContent(
            contentId: "routine_001",
            contentTitle: "Good Morning",
            contentDescription: "A 10-minute morning session to start your day with clarity and focus.",
            durationMinutes: 10,
            typeLabel: "Morning"
        )
    }
    
    // MARK: - Custom Content
    
    static var custom: MeditationContent {
        PreviewCustomContent(
            contentId: "custom_001",
            contentTitle: "Relaxation Meditation",
            contentDescription: "Breathwork, Body Awareness, Mantra, Focus, and visualization with spa background.",
            durationMinutes: 10
        )
    }
}

// MARK: - Preview Content Types

private struct PreviewPathContent: MeditationContent {
    let contentId: String
    let contentTitle: String
    let contentDescription: String
    let durationMinutes: Int
    let primaryLabel: String
    let secondaryLabel: String?
    let typeLabel: String
    
    var contentType: MeditationContentType { .path }
    var backgroundImageURL: URL? { nil }
}

private struct PreviewPreRecordedContent: MeditationContent {
    let contentId: String
    let contentTitle: String
    let contentDescription: String
    let durationMinutes: Int
    let typeLabel: String
    
    var contentType: MeditationContentType { .preRecorded }
    var primaryLabel: String { contentTitle }
    var secondaryLabel: String? { nil }
    var backgroundImageURL: URL? {
        // Sample Firebase Storage URL for preview
        URL(string: "https://firebasestorage.googleapis.com/v0/b/imagine-c6162.appspot.com/o/practice_images%2FGood%20Morning.png?alt=media")
    }
}

private struct PreviewCustomContent: MeditationContent {
    let contentId: String
    let contentTitle: String
    let contentDescription: String
    let durationMinutes: Int
    
    var contentType: MeditationContentType { .custom }
    var primaryLabel: String { contentTitle }
    var secondaryLabel: String? { nil }
    var typeLabel: String { "AI Generated" }
    var backgroundImageURL: URL? { nil }
}
#endif
