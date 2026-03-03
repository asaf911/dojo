//
//  SenseiAnimator.swift
//  imagine
//
//  Central coordinator for all Sensei animations.
//  This class is the single source of truth for animation state.
//
//  USAGE:
//  ------
//  Basic usage with SenseiView (internal animator):
//
//      SenseiView(style: .listening)  // Creates its own animator
//
//  Advanced usage with external animator (for parent control):
//
//      struct MyScreen: View {
//          @StateObject private var senseiAnimator = SenseiAnimator()
//
//          var body: some View {
//              VStack {
//                  SenseiView(style: .listening, animator: senseiAnimator)
//
//                  Button("Change Animation") {
//                      senseiAnimator.setAnimation(.thinking)
//                  }
//              }
//          }
//      }
//
//  ANIMATION STATES:
//  -----------------
//  The animator publishes transform values that views observe:
//  - characterOffset: Vertical position offset for floating
//  - characterScale: Scale transform for breathing effects
//  - characterOpacity: Fade in/out for transitions
//  - auraScale: Scale transform for aura pulsing
//  - auraOpacity: Aura fade effects
//  - isAuraPulsing: Whether aura should pulse
//  - isAuraRotating: Whether aura should rotate clockwise
//
//  ADDING NEW ANIMATIONS:
//  ----------------------
//  1. Add case to SenseiAnimationType (in SenseiAnimation.swift)
//  2. Add private method: startXxxAnimation()
//  3. Add case to switch in setAnimation(_:)
//

import SwiftUI
import Combine

// MARK: - SenseiAnimator

/// Coordinates all Sensei animation states.
///
/// Use this class to control Sensei animations programmatically.
/// Views observe the published properties to apply transforms.
@MainActor
final class SenseiAnimator: ObservableObject {
    
    // MARK: - Published Character States
    
    /// Vertical offset for character floating animation.
    /// Positive values move down, negative move up.
    @Published private(set) var characterOffset: CGSize = .zero
    
    /// Scale factor for character (1.0 = normal size).
    /// Used for breathing and emphasis effects.
    @Published private(set) var characterScale: CGFloat = 1.0
    
    /// Character opacity (0.0 - 1.0).
    /// Used for fade transitions.
    @Published private(set) var characterOpacity: Double = 1.0
    
    // MARK: - Published Aura States
    
    /// Scale factor for aura (1.0 = normal size).
    /// Used for pulsing effects.
    @Published private(set) var auraScale: CGFloat = 1.0
    
    /// Aura opacity (0.0 - 1.0).
    /// Used for fade and intensity effects.
    @Published private(set) var auraOpacity: Double = 1.0
    
    /// Whether the aura should be pulsing.
    /// Aura view observes this to start/stop pulse animation.
    @Published private(set) var isAuraPulsing: Bool = false
    
    /// Whether the aura should be rotating.
    /// Aura view observes this to start/stop rotation animation.
    @Published private(set) var isAuraRotating: Bool = false
    
    // MARK: - Animation State
    
    /// Currently active animation type
    @Published private(set) var currentAnimation: SenseiAnimationType = .idle
    
    /// Whether any animation is currently running
    @Published private(set) var isAnimating: Bool = false
    
    // MARK: - Private State
    
    /// Tracks the floating animation toggle state
    private var isFloatingUp: Bool = false
    
    // MARK: - Initialization
    
    init() {
        // Animator starts in idle state, animation begins on setAnimation call
    }
    
    // MARK: - Public API
    
    /// Set the current animation type.
    ///
    /// This is the main method to control Sensei animations.
    /// Call this to change between animation states.
    ///
    /// - Parameters:
    ///   - type: The animation type to play
    ///   - animated: Whether to animate the transition (default: true)
    ///
    /// Example:
    /// ```
    /// animator.setAnimation(.listening)
    /// animator.setAnimation(.thinking)
    /// ```
    func setAnimation(_ type: SenseiAnimationType, animated: Bool = true) {
        currentAnimation = type
        isAnimating = true
        
        // BASELINE: All types use the same listening animation for now
        // Future: Add switch statement with distinct implementations
        switch type {
        case .idle:
            startListeningAnimation()
        case .listening:
            startListeningAnimation()
        case .thinking:
            startListeningAnimation()  // TODO: Add pulsing aura
        case .ready:
            startListeningAnimation()  // TODO: Add brighter presence
        }
    }
    
    /// Stop all animations and reset to default state.
    ///
    /// Use this when the Sensei view disappears or needs to reset.
    func stopAllAnimations() {
        isAnimating = false
        isAuraPulsing = false
        isAuraRotating = false
        
        withAnimation(.easeOut(duration: 0.3)) {
            characterOffset = .zero
            characterScale = 1.0
            characterOpacity = 1.0
            auraScale = 1.0
            auraOpacity = 1.0
        }
    }
    
    /// Reset to initial state without animation.
    ///
    /// Use this for immediate state reset (e.g., before entrance animation).
    func resetState() {
        isAnimating = false
        isAuraPulsing = false
        isAuraRotating = false
        isFloatingUp = false
        characterOffset = .zero
        characterScale = 1.0
        characterOpacity = 1.0
        auraScale = 1.0
        auraOpacity = 1.0
    }
    
    // MARK: - Animation Implementations
    
    /// Baseline "listening" animation - gentle floating with rotating aura.
    ///
    /// Character floats up and down with subtle movement.
    /// Aura rotates slowly clockwise for a meditative effect.
    private func startListeningAnimation() {
        isAuraPulsing = false
        isAuraRotating = true  // Enable slow clockwise rotation
        
        // Toggle floating direction
        isFloatingUp = true
        
        // Apply floating animation
        let floatDistance = SenseiAnimationParameters.floatDistance
        let duration = SenseiAnimationParameters.floatDuration
        
        withAnimation(
            .easeInOut(duration: duration)
            .repeatForever(autoreverses: true)
        ) {
            characterOffset = CGSize(width: 0, height: -floatDistance)
        }
    }
    
    // MARK: - Future Animation Placeholders
    
    // These will be implemented when adding distinct animations per screen:
    //
    // private func startThinkingAnimation() {
    //     isAuraPulsing = true
    //     // More active floating + aura pulse
    // }
    //
    // private func startReadyAnimation() {
    //     isAuraPulsing = false
    //     // Brighter presence, subtle bounce
    // }
    //
    // private func startCelebratingAnimation() {
    //     // Bounce effect with scale
    // }
}

// MARK: - Preview Support

#if DEBUG
extension SenseiAnimator {
    /// Creates an animator in a specific state for previews
    static func preview(animation: SenseiAnimationType) -> SenseiAnimator {
        let animator = SenseiAnimator()
        animator.setAnimation(animation)
        return animator
    }
}
#endif
