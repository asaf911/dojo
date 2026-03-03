//
//  SenseiStyle.swift
//  imagine
//
//  Defines visual appearance styles for the Sensei component.
//  Each style configures aura color, opacity, and animation behavior.
//
//  USAGE:
//  ------
//  Use predefined styles:
//
//      SenseiView(style: .listening)
//      SenseiView(style: .thinking)
//      SenseiView(style: .ready)
//
//  Or create a custom style:
//
//      SenseiView(style: .custom(
//          auraColor: .purple,
//          auraOpacity: 0.6
//      ))
//
//  STYLE GUIDE:
//  ------------
//  - .listening: Default calm state, subtle purple aura
//  - .thinking:  Active processing, slightly brighter, animated aura
//  - .ready:     Completion state, brightest aura
//  - .custom:    For special cases requiring unique appearance
//
//  ADDING NEW STYLES:
//  ------------------
//  1. Add a new case to the enum
//  2. Add color/opacity values in computed properties
//  3. Set animatesAura if the style should pulse
//

import SwiftUI

// MARK: - SenseiStyle

/// Visual appearance styles for the Sensei component.
///
/// Each style defines the aura's color, opacity, and whether
/// it should animate (pulse). Use these to match Sensei's
/// appearance to the current screen context.
enum SenseiStyle: Equatable {
    
    // MARK: - Predefined Styles
    
    /// Listening state - calm, attentive presence.
    /// Default purple aura, no animation.
    /// Use on: SenseiScreen, general input screens
    case listening
    
    /// Thinking state - active processing.
    /// Slightly brighter aura with pulse animation.
    /// Use on: BuildingScreen, loading states
    case thinking
    
    /// Ready state - completion, call-to-action.
    /// Brightest aura, confident presence.
    /// Use on: ReadyScreen, success states
    case ready
    
    /// Custom style for special cases.
    /// Specify exact color and opacity.
    case custom(auraColor: Color, auraOpacity: Double)
    
    // MARK: - Appearance Properties
    
    /// The aura's base color for this style.
    ///
    /// Colors are deep purples that blend with the dark background
    /// while providing visible glow when combined with opacity.
    var auraColor: Color {
        switch self {
        case .listening:
            // Deep purple - subtle, calm
            return Color(red: 0.27, green: 0.11, blue: 0.47)
        case .thinking:
            // Brighter purple - more active
            return Color(red: 0.35, green: 0.15, blue: 0.55)
        case .ready:
            // Medium-bright purple - confident
            return Color(red: 0.30, green: 0.12, blue: 0.50)
        case .custom(let color, _):
            return color
        }
    }
    
    /// The aura's base opacity for this style.
    ///
    /// Higher values create a more visible, prominent aura.
    /// The gradient still fades to transparent at the edges.
    var auraOpacity: Double {
        switch self {
        case .listening:
            return 0.5   // Subtle presence
        case .thinking:
            return 0.6   // Slightly more visible
        case .ready:
            return 0.7   // Most prominent
        case .custom(_, let opacity):
            return opacity
        }
    }
    
    /// Whether the aura should animate (pulse) in this style.
    ///
    /// When true, the aura will scale and fade rhythmically.
    /// The animator's `isAuraPulsing` property controls this.
    var animatesAura: Bool {
        switch self {
        case .thinking:
            return true   // Pulse during "processing"
        default:
            return false  // Static aura
        }
    }
    
    // MARK: - Display Properties
    
    /// Human-readable name for debugging and previews
    var displayName: String {
        switch self {
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .ready: return "Ready"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Equatable Conformance

extension SenseiStyle {
    static func == (lhs: SenseiStyle, rhs: SenseiStyle) -> Bool {
        switch (lhs, rhs) {
        case (.listening, .listening),
             (.thinking, .thinking),
             (.ready, .ready):
            return true
        case (.custom(let lColor, let lOpacity), .custom(let rColor, let rOpacity)):
            // Compare color components (approximate)
            return lOpacity == rOpacity && lColor.description == rColor.description
        default:
            return false
        }
    }
}
