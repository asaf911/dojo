import SwiftUI

// MARK: - Centralized Animation Constants

/// Centralized animation constants for AI chat interface
/// All durations are slowed down by 30% (multiplied by 1.3) for smoother, more deliberate animations
struct AnimationConstants {
    // MARK: - Typing Animation
    
    /// Timer interval for character-by-character typing animation
    /// Original: 0.005s, Slowed: 0.0065s (30% slower)
    static let typingInterval: TimeInterval = 0.0065
    
    // MARK: - Animation Durations
    
    /// Button appearance animation duration
    /// Original: 0.2s, Slowed: 0.26s (30% slower)
    static let buttonAnimationDuration: TimeInterval = 0.26
    
    /// Option/item appearance animation duration
    /// Original: 0.3s, Slowed: 0.39s (30% slower)
    static let itemAnimationDuration: TimeInterval = 0.39
    
    // MARK: - Sequential Delays
    
    /// Delay between sequential option appearances
    /// Original: 0.15s, Slowed: 0.195s (30% slower)
    static let sequentialItemDelay: TimeInterval = 0.195
    
    /// Delay between sequential button appearances
    /// Original: 0.3s, Slowed: 0.39s (30% slower)
    static let sequentialButtonDelay: TimeInterval = 0.39
    
    // MARK: - Onboarding Flow Delays
    
    /// Initial onboarding step delay
    /// Original: 0.4s, Slowed: 0.52s (30% slower)
    static let onboardingInitialDelay: TimeInterval = 0.52
    
    /// Onboarding step transition delay
    /// Original: 0.45s, Slowed: 0.585s (30% slower)
    static let onboardingTransitionDelay: TimeInterval = 0.585
    
    /// Extended onboarding step delay
    /// Original: 0.6s, Slowed: 0.78s (30% slower)
    static let onboardingExtendedDelay: TimeInterval = 0.78
    
    /// Onboarding message completion delay
    /// Original: 0.1s, Slowed: 0.13s (30% slower)
    static let onboardingMessageDelay: TimeInterval = 0.13
    
    // MARK: - Scroll Animation
    
    /// Smooth scroll animation duration for auto-scrolling
    /// Optimized for smooth content tracking without jarring movements
    static let scrollAnimationDuration: TimeInterval = 0.2
    
    /// Delay before re-enabling follow mode after user stops scrolling
    /// Allows user to finish their scroll gesture before auto-scroll resumes
    static let followModeReenableDelay: TimeInterval = 0.5
    
    // MARK: - Sensei Thinking Animation
    
    /// Fade duration for thinking animation appearance/disappearance
    static let senseiThinkingFadeDuration: TimeInterval = 0.3
    
    /// Duration each step text is displayed before transitioning to next
    static let senseiThinkingStepDuration: TimeInterval = 2.5
    
    /// Transition duration between step text changes
    static let senseiThinkingStepTransition: TimeInterval = 0.4
    
    /// Gradient animation speed (seconds per full cycle)
    static let senseiThinkingGradientSpeed: Double = 1.25
    
    // MARK: - Animation Curves
    
    /// Ease-out animation for item appearances
    static var itemAppearanceAnimation: Animation {
        .easeOut(duration: itemAnimationDuration)
    }
    
    /// Ease-in animation for button appearances
    static var buttonAppearanceAnimation: Animation {
        .easeIn(duration: buttonAnimationDuration)
    }
}

