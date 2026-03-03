//
//  ChatKeyboardController.swift
//  Dojo
//
//  Single source of truth for AI chat keyboard state management
//

import SwiftUI
import Combine

// MARK: - Keyboard Focus State Machine

enum ChatKeyboardFocusState: Equatable {
    /// Keyboard is collapsed and should stay collapsed
    case collapsed
    /// Keyboard is expanded (user is typing)
    case expanded
    /// Keyboard is suppressed - will not auto-expand until released
    /// Used during AI response, onboarding, etc.
    case suppressed(reason: SuppressionReason)
    
    enum SuppressionReason: Equatable {
        case aiResponding      // AI is generating/typing response
        case onboarding        // Onboarding flow is active
        case menuOpen          // Side menu is open
    }
    
    var shouldAllowFocus: Bool {
        switch self {
        case .collapsed, .expanded:
            return true
        case .suppressed:
            return false
        }
    }
    
    var debugDescription: String {
        switch self {
        case .collapsed: return "collapsed"
        case .expanded: return "expanded"
        case .suppressed(let reason):
            switch reason {
            case .aiResponding: return "suppressed(aiResponding)"
            case .onboarding: return "suppressed(onboarding)"
            case .menuOpen: return "suppressed(menuOpen)"
            }
        }
    }
}

// MARK: - Chat Keyboard Controller

@MainActor
final class ChatKeyboardController: ObservableObject {
    static let shared = ChatKeyboardController()
    
    /// The current keyboard focus state - single source of truth
    @Published private(set) var state: ChatKeyboardFocusState = .collapsed
    
    /// Whether the keyboard should be focused (derived from state)
    var shouldBeFocused: Bool {
        state == .expanded
    }
    
    /// Track if keyboard was expanded before suppression (for restore)
    private var wasExpandedBeforeSuppression: Bool = false
    
    private init() {}
    
    // MARK: - Public API
    
    /// User wants to expand the keyboard (tapped on input field)
    func userRequestedExpand() {
        guard state.shouldAllowFocus else {
            logger.aiChat("🧠 KEYBOARD_CTRL: User expand blocked - state=\(state.debugDescription)")
            return
        }
        logger.aiChat("🧠 KEYBOARD_CTRL: User requested expand")
        state = .expanded
        persistExpanded()
    }
    
    /// User submitted a message - collapse and suppress until AI responds
    func userSubmittedMessage() {
        logger.aiChat("🧠 KEYBOARD_CTRL: User submitted message - collapsing and suppressing")
        state = .suppressed(reason: .aiResponding)
        persistCollapsed()
    }
    
    /// AI has finished responding - release suppression
    func aiResponseComplete() {
        logger.aiChat("🧠 KEYBOARD_CTRL: AI response complete - releasing suppression")
        if case .suppressed(reason: .aiResponding) = state {
            state = .collapsed
        }
    }
    
    /// Collapse keyboard (user scrolled, tapped elsewhere, etc.)
    func collapse() {
        logger.aiChat("🧠 KEYBOARD_CTRL: Collapse requested - current state=\(state.debugDescription)")
        if case .suppressed = state {
            // Don't change suppression state, just note we want collapsed
            return
        }
        state = .collapsed
        persistCollapsed()
    }
    
    /// Suppress keyboard for onboarding
    func suppressForOnboarding() {
        logger.aiChat("🧠 KEYBOARD_CTRL: Suppressing for onboarding")
        wasExpandedBeforeSuppression = (state == .expanded)
        state = .suppressed(reason: .onboarding)
    }
    
    /// Release onboarding suppression
    func releaseOnboardingSuppression(expandKeyboard: Bool = false) {
        logger.aiChat("🧠 KEYBOARD_CTRL: Releasing onboarding suppression, expand=\(expandKeyboard)")
        if case .suppressed(reason: .onboarding) = state {
            if expandKeyboard {
                state = .expanded
                persistExpanded()
            } else {
                state = .collapsed
            }
        }
    }
    
    /// Suppress keyboard for menu
    func suppressForMenu() {
        logger.aiChat("🧠 KEYBOARD_CTRL: Suppressing for menu")
        wasExpandedBeforeSuppression = (state == .expanded)
        state = .suppressed(reason: .menuOpen)
    }
    
    /// Release menu suppression, optionally restoring previous state
    func releaseMenuSuppression(restore: Bool) {
        logger.aiChat("🧠 KEYBOARD_CTRL: Releasing menu suppression, restore=\(restore), wasExpanded=\(wasExpandedBeforeSuppression)")
        if case .suppressed(reason: .menuOpen) = state {
            if restore && wasExpandedBeforeSuppression {
                state = .expanded
            } else {
                state = .collapsed
            }
        }
        wasExpandedBeforeSuppression = false
    }
    
    /// Restore persisted keyboard state on appear (only if not suppressed)
    func restorePersistedState() {
        guard case .collapsed = state else {
            logger.aiChat("🧠 KEYBOARD_CTRL: Cannot restore - state=\(state.debugDescription)")
            return
        }
        let wasExpanded = SharedUserStorage.retrieve(forKey: .aiChatKeyboardExpanded, as: Bool.self, defaultValue: false)
        logger.aiChat("🧠 KEYBOARD_CTRL: Restoring persisted state: \(wasExpanded)")
        if wasExpanded {
            state = .expanded
        }
    }
    
    /// Force collapse (used when view appears to ensure clean state)
    func forceCollapse() {
        logger.aiChat("🧠 KEYBOARD_CTRL: Force collapse")
        if case .suppressed = state {
            // Keep suppression but note we want collapsed
            return
        }
        state = .collapsed
    }
    
    /// Clear stale suppression on view appear
    /// This fixes bugs where the keyboard gets stuck if:
    /// - User leaves Sensei while AI is responding (aiResponding)
    /// - Menu is opened but not properly dismissed (menuOpen)
    /// When the view appears fresh, these suppressions should be cleared so user can interact
    func clearStaleSuppressionOnAppear() {
        if case .suppressed(let reason) = state {
            // Only clear aiResponding and menuOpen - onboarding is intentional
            if reason == .aiResponding || reason == .menuOpen {
                logger.aiChat("🧠 KEYBOARD_CTRL: Clearing stale suppression on appear (was: \(reason))")
                state = .collapsed
            }
        }
    }
    
    /// Reset to initial state (for testing)
    func reset() {
        logger.aiChat("🧠 KEYBOARD_CTRL: Reset")
        state = .collapsed
        wasExpandedBeforeSuppression = false
    }
    
    // MARK: - Private Helpers
    
    private func persistExpanded() {
        SharedUserStorage.save(value: true, forKey: .aiChatKeyboardExpanded)
    }
    
    private func persistCollapsed() {
        SharedUserStorage.save(value: false, forKey: .aiChatKeyboardExpanded)
    }
}

