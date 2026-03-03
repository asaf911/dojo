import SwiftUI

// MARK: - Smooth Scroll Coordinator

/// Manages smooth auto-scrolling behavior for chat content
/// Tracks content height changes and controls follow mode (auto-scroll enabled/disabled)
/// Also coordinates keyboard-aware scrolling to preserve visible content
@MainActor
class SmoothScrollCoordinator: ObservableObject {
    /// Controls whether auto-scroll should follow content growth
    @Published var shouldFollowContent: Bool = true
    
    /// Current total height of scroll content
    @Published var contentHeight: CGFloat = 0
    
    // MARK: - Keyboard Awareness
    
    /// Current keyboard height for scroll compensation
    @Published var keyboardHeight: CGFloat = 0
    
    /// Message ID that was at the bottom of visible area before keyboard appeared
    /// Used to restore scroll position when keyboard dismisses
    @Published var preKeyboardScrollAnchor: UUID?
    
    /// The bottom-most visible message ID (updated by AIChatMessageList)
    @Published var bottomVisibleMessageId: UUID?
    
    /// Animation to use for smooth scrolling
    var scrollAnimation: Animation {
        .easeOut(duration: AnimationConstants.scrollAnimationDuration)
    }
    
    /// Enable follow mode - auto-scroll will track content growth
    func enableFollowMode() {
        let wasEnabled = shouldFollowContent
        shouldFollowContent = true
        if !wasEnabled {
            logger.aiChat("🧠 AI_SCROLL: Follow mode ENABLED")
        }
    }
    
    /// Disable follow mode - auto-scroll will pause
    func disableFollowMode() {
        let wasEnabled = shouldFollowContent
        shouldFollowContent = false
        if wasEnabled {
            logger.aiChat("🧠 AI_SCROLL: Follow mode DISABLED")
        }
    }
    
    /// Update content height and trigger scroll if needed
    /// - Parameter height: New total content height
    func updateContentHeight(_ height: CGFloat) {
        contentHeight = height
        
        // Note: Actual scrolling is handled by the view observing contentHeight changes
        // This method is for tracking purposes
    }
    
    // MARK: - Content Reveal Coordination
    
    /// Prepares for content reveal by pausing auto-scroll
    /// Call this before adding dynamic content (like meditation cards) to prevent premature scrolling
    /// - Parameter animationDuration: How long the reveal animation takes
    /// - Returns: A closure to call when the reveal animation completes to re-enable follow mode
    func prepareForContentReveal(animationDuration: TimeInterval = 0.35) -> () -> Void {
        disableFollowMode()
        logger.aiChat("🧠 AI_SCROLL: Content reveal started - follow mode paused")
        
        return { [weak self] in
            // Re-enable follow mode after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                self?.enableFollowMode()
                logger.aiChat("🧠 AI_SCROLL: Content reveal complete - follow mode resumed")
            }
        }
    }
    
    // MARK: - Keyboard Scroll Coordination
    
    /// Called when keyboard is about to appear or resize
    /// - Parameters:
    ///   - height: New keyboard height
    ///   - bottomVisibleMessageId: The message ID at the bottom of visible area
    func keyboardWillShow(height: CGFloat, bottomVisibleMessageId: UUID?) {
        let previousHeight = keyboardHeight
        keyboardHeight = height
        
        // If this is initial appearance (not just resize), save the anchor
        if previousHeight == 0 && height > 0 {
            preKeyboardScrollAnchor = bottomVisibleMessageId
            logger.aiChat("🧠 AI_SCROLL: Keyboard appearing - height=\(height), savedAnchor=\(bottomVisibleMessageId?.uuidString ?? "nil")")
        } else if height != previousHeight {
            logger.aiChat("🧠 AI_SCROLL: Keyboard resized - height=\(previousHeight) -> \(height)")
        }
    }
    
    /// Called when keyboard will hide
    func keyboardWillHide() {
        let previousHeight = keyboardHeight
        keyboardHeight = 0
        
        logger.aiChat("🧠 AI_SCROLL: Keyboard hiding - was height=\(previousHeight)")
        
        // Clear saved anchor after keyboard fully hides
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.preKeyboardScrollAnchor = nil
        }
    }
}

