//
//  CustomContentAdapter.swift
//  imagine
//
//  Created for Clean Recommendation Card Architecture
//
//  Adapts AITimerResponse to the MeditationContent protocol,
//  enabling unified card rendering for AI-generated custom meditations.
//

import Foundation

// MARK: - Custom Content Adapter

/// Wraps an AITimerResponse to conform to MeditationContent protocol
struct CustomContentAdapter: MeditationContent {
    
    // MARK: - Original Data
    
    /// The underlying AITimerResponse data
    let aiResponse: AITimerResponse
    
    // MARK: - MeditationContent Conformance
    
    var contentId: String {
        aiResponse.meditationConfiguration.id.uuidString
    }
    
    var contentTitle: String {
        aiResponse.meditationConfiguration.title ?? "Custom Meditation"
    }
    
    var contentDescription: String {
        aiResponse.description
    }
    
    var durationMinutes: Int {
        aiResponse.meditationConfiguration.duration
    }
    
    var contentType: MeditationContentType {
        .custom
    }
    
    var primaryLabel: String {
        contentTitle
    }
    
    var secondaryLabel: String? {
        nil  // Custom meditations don't have a secondary label
    }
    
    var typeLabel: String {
        "AI Generated"
    }
    
    var backgroundImageURL: URL? {
        // Custom cards use static asset (CustomCardBackground)
        nil
    }
    
    // MARK: - Custom-Specific Properties
    
    /// The full meditation configuration
    var configuration: MeditationConfiguration {
        aiResponse.meditationConfiguration
    }
    
    /// Deep link to launch this meditation
    var deepLink: URL {
        aiResponse.deepLink
    }
}
