//
//  PreRecordedContentAdapter.swift
//  imagine
//
//  Created for Clean Recommendation Card Architecture
//
//  Adapts AudioFile to the MeditationContent protocol,
//  enabling unified card rendering for pre-recorded (explore/routine) meditations.
//

import Foundation

// MARK: - Pre-Recorded Content Adapter

/// Wraps an AudioFile to conform to MeditationContent protocol
struct PreRecordedContentAdapter: MeditationContent {
    
    // MARK: - Original Data
    
    /// The underlying AudioFile data
    let audioFile: AudioFile
    
    // MARK: - MeditationContent Conformance
    
    var contentId: String {
        audioFile.id
    }
    
    var contentTitle: String {
        audioFile.title
    }
    
    var contentDescription: String {
        audioFile.description
    }
    
    var durationMinutes: Int {
        audioFile.durations.first?.length ?? 10
    }
    
    var contentType: MeditationContentType {
        .preRecorded
    }
    
    var primaryLabel: String {
        audioFile.title
    }
    
    var secondaryLabel: String? {
        nil  // Pre-recorded sessions don't have a secondary label
    }
    
    var typeLabel: String {
        // Derive from time-based tags or default to "Daily Routine"
        if audioFile.tags.contains("Morning") {
            return "Morning"
        } else if audioFile.tags.contains("Noon") || audioFile.tags.contains("Midday") {
            return "Midday"
        } else if audioFile.tags.contains("Evening") {
            return "Evening"
        } else if audioFile.tags.contains("Night") || audioFile.tags.contains("Sleep") {
            return "Night"
        }
        return "Daily Routine"
    }
    
    // MARK: - Background Image
    
    /// Background image URL from Firebase Storage
    var backgroundImageURL: URL? {
        guard let imageFile = audioFile.imageFile else { return nil }
        return convertGsUrlToHttps(imageFile)
    }
    
    // MARK: - PreRecorded-Specific Properties
    
    /// All available durations for this session
    var availableDurations: [Duration] {
        audioFile.durations
    }
    
    /// Tags associated with the session
    var tags: [String] {
        audioFile.tags
    }
    
    /// Whether this is a premium session
    var isPremium: Bool {
        audioFile.premium
    }
    
    /// Category of the audio file
    var category: AudioCategory {
        audioFile.category
    }
}
