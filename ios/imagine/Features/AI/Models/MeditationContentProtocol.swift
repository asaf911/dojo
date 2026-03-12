//
//  MeditationContentProtocol.swift
//  imagine
//
//  Created for Clean Recommendation Card Architecture
//
//  Protocol-based abstraction that allows all meditation types
//  (Path, PreRecorded, Custom) to be handled uniformly by card views.
//

import Foundation
import SwiftUI

// MARK: - Meditation Content Type

/// Identifies the type of meditation content for styling and behavior
enum MeditationContentType: String, Codable {
    case path           // Path step meditation (lessons/practices)
    case preRecorded    // Pre-recorded daily routine session
    case custom         // AI-generated custom meditation
    
    /// Whether this is a session type (custom or preRecorded) vs path
    var isSessionType: Bool {
        self == .custom || self == .preRecorded
    }
    
    /// Accent color for this content type
    var accentColor: Color {
        switch self {
        case .path: return .textTurquoise
        case .preRecorded: return .textTurquoise  // Unified with path and custom
        case .custom: return .textTurquoise  // Custom uses same turquoise as path
        }
    }
    
    /// Completed state accent color (for path)
    var completedAccentColor: Color {
        return .textPurple
    }
    
    /// Background image name (if applicable)
    var backgroundImageName: String? {
        switch self {
        case .path: return "PathCardBackground"
        case .preRecorded: return nil
        case .custom: return "CustomCardBackground"
        }
    }
}

// MARK: - Card Presentation Mode

/// Defines the visual presentation and interaction style of a card
enum CardPresentationMode: Equatable {
    case primary      // Full-featured card with all details and controls
    case secondary    // Compact card with dark overlay, minimal controls
    
    /// Opacity of the dark overlay (secondary cards are dimmed)
    var darkOverlayOpacity: Double {
        switch self {
        case .primary: return 0.0
        case .secondary: return 0.80
        }
    }
    
    /// Whether to show expanded controls (play button, customize)
    var showFullControls: Bool {
        switch self {
        case .primary: return true
        case .secondary: return false
        }
    }
}

// MARK: - Meditation Content Protocol

/// Protocol that all meditation content types must conform to.
/// Enables unified handling of Path, PreRecorded, and Custom meditations.
protocol MeditationContent {
    /// Unique identifier for the content
    var contentId: String { get }
    
    /// Display title of the meditation
    var contentTitle: String { get }
    
    /// Description text for the meditation
    var contentDescription: String { get }
    
    /// Duration in minutes
    var durationMinutes: Int { get }
    
    /// The type of meditation content
    var contentType: MeditationContentType { get }
    
    // MARK: - Card Header Labels
    
    /// Primary label shown in header (e.g., "Step 1", title for others)
    var primaryLabel: String { get }
    
    /// Secondary label shown after bullet (e.g., "The Path", nil for others)
    var secondaryLabel: String? { get }
    
    /// Type descriptor (e.g., "Lesson", "Morning Routine", "AI Generated")
    var typeLabel: String { get }
    
    // MARK: - Background Image
    
    /// URL for background image (used by pre-recorded content with dynamic images)
    var backgroundImageURL: URL? { get }
}

// MARK: - Default Implementations

extension MeditationContent {
    /// Formatted duration text (e.g., "5 min")
    var durationText: String {
        "\(durationMinutes) min"
    }
    
    /// Metadata line combining type and duration (e.g., "Lesson • 5 min")
    var metadataText: String {
        "\(typeLabel) • \(durationText)"
    }
    
    /// Full header text with primary and secondary labels
    var headerText: String {
        if let secondary = secondaryLabel {
            return "\(primaryLabel) • \(secondary)"
        }
        return primaryLabel
    }
    
    /// Default: no background image URL (uses static asset or gradient)
    var backgroundImageURL: URL? {
        nil
    }
}

// MARK: - Firebase Storage URL Conversion

/// Converts Firebase Storage gs:// URLs to HTTPS URLs
func convertGsUrlToHttps(_ gsUrl: String) -> URL? {
    // Resolve to content bucket (rewrites dev bucket URLs to prod)
    let resolved = Config.resolveMediaUrl(gsUrl)
    // Convert gs:// URL to https:// URL for Firebase Storage
    // Format: gs://bucket-name/path/to/file.jpg
    // Becomes: https://firebasestorage.googleapis.com/v0/b/bucket-name/o/path%2Fto%2Ffile.jpg?alt=media
    let gsPrefix = "gs://"
    guard resolved.hasPrefix(gsPrefix) else {
        // Already an https URL or other format
        return URL(string: resolved)
    }
    
    let withoutPrefix = resolved.dropFirst(gsPrefix.count)
    let components = withoutPrefix.split(separator: "/", maxSplits: 1)
    
    guard components.count == 2 else { return nil }
    
    let bucket = String(components[0])
    
    // Create a properly encoded path by handling each path component separately
    let pathString = String(components[1])
    let pathComponents = pathString.split(separator: "/")
    
    // Encode each path component individually
    let encodedPathComponents = pathComponents.map { component -> String in
        let str = String(component)
        return str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? str
    }
    
    // Join the encoded components with %2F (URL-encoded forward slash)
    let encodedPath = encodedPathComponents.joined(separator: "%2F")
    
    return URL(string: "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encodedPath)?alt=media")
}
