//
//  PostSessionPrompt.swift
//  imagine
//
//  Post-session prompt model for the "Would you like to meditate more?" flow.
//  Displayed in AI chat after a completed meditation session instead of
//  auto-showing recommendations.
//

import Foundation

// MARK: - Post Session Prompt

/// Configuration for the post-session "continue meditating?" prompt.
/// The question text lives in `ChatMessage.content` (consistent with all other message types).
/// This struct carries only the button labels.
struct PostSessionPrompt: Codable, Equatable {
    /// Label for the affirmative button (e.g. "Yes, I'd love to")
    let yesLabel: String
    /// Label for the decline button (e.g. "No, I'm good")
    let noLabel: String
    
    /// Whether this is a path-complete context (triggers phase transition before recommendation)
    let isPathComplete: Bool
    
    /// Whether the user has already responded to this prompt.
    /// Persisted so the buttons stay in their final state across view re-renders.
    var responded: Bool
    
    /// Which button the user tapped (true = yes, false = no). Only meaningful when `responded` is true.
    var respondedYes: Bool
    
    // MARK: - Defaults
    
    /// Standard post-session prompt with default labels
    static func standard(isPathComplete: Bool = false) -> PostSessionPrompt {
        PostSessionPrompt(
            yesLabel: "Yes, I'd love to",
            noLabel: "No, I'm good",
            isPathComplete: isPathComplete,
            responded: false,
            respondedYes: false
        )
    }
}
