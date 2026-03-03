//
//  SenseiAnimation.swift
//  imagine
//
//  Defines animation types and configurations for the Sensei component.
//
//  USAGE:
//  ------
//  Animation types define WHAT animation to play:
//
//      animator.setAnimation(.listening)
//      animator.setAnimation(.idle)
//
//  Animation configs define HOW the animation behaves (timing, easing):
//
//      let config = SenseiAnimationConfig.defaultFloat
//      // duration: 2.5s, repeats forever, easeInOut
//
//  ADDING NEW ANIMATIONS:
//  ----------------------
//  1. Add a new case to SenseiAnimationType
//  2. Add implementation in SenseiAnimator.setAnimation(_:)
//  3. Optionally add a preset config in SenseiAnimationConfig
//

import SwiftUI

// MARK: - Animation Types

/// Defines all possible Sensei animation states.
///
/// Each animation type represents a distinct visual behavior for the Sensei character
/// and its aura. The animator interprets these types and applies the appropriate
/// transforms and effects.
///
/// **Baseline Implementation:**
/// Currently, all types produce the same "listening" animation (gentle float).
/// Distinct behaviors will be added in future iterations.
enum SenseiAnimationType: Equatable, CaseIterable {
    
    /// Default idle state - gentle floating animation.
    /// Use when Sensei is present but not actively engaged.
    case idle
    
    /// Listening state - attentive, calm presence.
    /// Use when Sensei is receiving input from the user.
    case listening
    
    /// Thinking state - processing, contemplative.
    /// Use when Sensei is "working" (e.g., building screen).
    /// Future: Will include pulsing aura effect.
    case thinking
    
    /// Ready state - energized, prepared.
    /// Use when presenting results or calls-to-action.
    /// Future: Will have brighter aura and subtle bounce.
    case ready
    
    // MARK: - Display Properties
    
    /// Human-readable name for debugging and previews
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .ready: return "Ready"
        }
    }
    
    /// Description of the animation behavior
    var description: String {
        switch self {
        case .idle:
            return "Gentle floating motion, calm aura"
        case .listening:
            return "Attentive presence, minimal movement"
        case .thinking:
            return "Active processing, pulsing aura"
        case .ready:
            return "Energized state, bright aura"
        }
    }
}

// MARK: - Animation Configuration

/// Configuration for animation timing and behavior.
///
/// Use preset configurations or create custom ones:
///
///     // Use a preset
///     let config = SenseiAnimationConfig.defaultFloat
///
///     // Create custom
///     let custom = SenseiAnimationConfig(
///         duration: 1.5,
///         delay: 0.2,
///         repeatBehavior: .forever(autoreverses: true)
///     )
struct SenseiAnimationConfig {
    
    /// Duration of one animation cycle (in seconds)
    let duration: Double
    
    /// Delay before animation starts (in seconds)
    let delay: Double
    
    /// How the animation repeats
    let repeatBehavior: RepeatBehavior
    
    /// Animation curve/easing
    let curve: AnimationCurve
    
    // MARK: - Repeat Behavior
    
    /// Defines how an animation repeats
    enum RepeatBehavior: Equatable {
        /// Play once and stop
        case once
        
        /// Repeat forever
        case forever(autoreverses: Bool)
        
        /// Repeat a specific number of times
        case count(Int, autoreverses: Bool)
    }
    
    // MARK: - Animation Curve
    
    /// Supported animation curves
    enum AnimationCurve {
        case linear
        case easeIn
        case easeOut
        case easeInOut
        case spring(response: Double, dampingFraction: Double)
        
        /// Convert to SwiftUI Animation
        func toAnimation(duration: Double) -> Animation {
            switch self {
            case .linear:
                return .linear(duration: duration)
            case .easeIn:
                return .easeIn(duration: duration)
            case .easeOut:
                return .easeOut(duration: duration)
            case .easeInOut:
                return .easeInOut(duration: duration)
            case .spring(let response, let dampingFraction):
                return .spring(response: response, dampingFraction: dampingFraction)
            }
        }
    }
    
    // MARK: - Initialization
    
    init(
        duration: Double = 2.5,
        delay: Double = 0,
        repeatBehavior: RepeatBehavior = .forever(autoreverses: true),
        curve: AnimationCurve = .easeInOut
    ) {
        self.duration = duration
        self.delay = delay
        self.repeatBehavior = repeatBehavior
        self.curve = curve
    }
    
    // MARK: - Preset Configurations
    
    /// Default floating animation - gentle, continuous
    /// Used for idle and listening states
    static let defaultFloat = SenseiAnimationConfig(
        duration: 2.5,
        delay: 0,
        repeatBehavior: .forever(autoreverses: true),
        curve: .easeInOut
    )
    
    /// Subtle breathing animation - very gentle scale
    static let subtleBreathing = SenseiAnimationConfig(
        duration: 4.0,
        delay: 0,
        repeatBehavior: .forever(autoreverses: true),
        curve: .easeInOut
    )
    
    /// Pulse animation for aura - slightly faster
    static let auraPulse = SenseiAnimationConfig(
        duration: 2.0,
        delay: 0,
        repeatBehavior: .forever(autoreverses: true),
        curve: .easeInOut
    )
    
    /// Quick entrance animation
    static let entrance = SenseiAnimationConfig(
        duration: 0.6,
        delay: 0,
        repeatBehavior: .once,
        curve: .spring(response: 0.6, dampingFraction: 0.8)
    )
}

// MARK: - Animation Parameters

/// Concrete animation values used by the animator.
/// These define the actual transform amounts for each animation type.
struct SenseiAnimationParameters {
    
    // MARK: - Float Animation
    
    /// Vertical distance for floating animation (in points)
    static let floatDistance: CGFloat = 2.0
    
    /// Duration of one float cycle
    static let floatDuration: Double = 2.5
    
    // MARK: - Scale Animation
    
    /// Maximum scale increase for breathing effect
    static let breathingScaleAmount: CGFloat = 0.02
    
    /// Maximum scale increase for aura pulse
    static let auraPulseScaleAmount: CGFloat = 0.1
    
    // MARK: - Opacity Animation
    
    /// Minimum opacity during aura pulse
    static let auraPulseMinOpacity: Double = 0.8
    
    // MARK: - Rotation Animation
    
    /// Duration for one full 360° rotation of the aura (in seconds)
    /// Lower = faster rotation, Higher = slower rotation
    static let auraRotationDuration: Double = 16.0
}
