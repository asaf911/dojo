//
//  DualRecommendationMessageView.swift
//  imagine
//
//  Created for Dual Recommendation System
//
//  Renders both primary and secondary recommendations in the AI chat.
//  Supports typing animations and all three recommendation types:
//  Path, Explore, and Custom.
//

import SwiftUI

// MARK: - Dual Recommendation Message View

/// Main view for rendering dual recommendations in AI chat
/// Shows primary recommendation first, then secondary with a divider
struct DualRecommendationMessageView: View {
    let message: ChatMessage
    let dualRecommendation: DualRecommendation
    @ObservedObject var conversationState: AIConversationState
    @ObservedObject var manager: AIRequestManager
    let isLatestMessage: Bool
    let onPathPlay: ((PathStep, RecommendationPosition) -> Void)?
    let onExplorePlay: ((AudioFile, RecommendationPosition) -> Void)?
    let onCustomPlay: ((AITimerResponse, RecommendationPosition) -> Void)?
    
    // MARK: - State
    
    /// Typing sequence stages:
    /// -1 = typing welcome greeting (if exists)
    /// 0 = typing primary intro
    /// 1 = primary intro done, show primary card
    /// 2 = typing secondary intro
    /// 3 = secondary intro done, show secondary card
    /// 4 = complete
    @State private var typingStage: Int = 0
    @State private var welcomeComplete: Bool = false
    /// Tracks whether the first-welcome context message has finished typing.
    /// Only relevant when `dualRecommendation.primary.contextMessage != nil`.
    @State private var contextComplete: Bool = false
    @State private var showPrimaryCard: Bool = false
    @State private var showSecondaryDivider: Bool = false
    @State private var showSecondaryCard: Bool = false
    
    /// Tracks which card is currently selected in the dual recommendation
    /// nil = neither selected (initial state)
    /// true = secondary selected (primary deselected)
    /// false = primary selected (secondary deselected)
    @State private var secondarySelected: Bool? = nil
    
    // MARK: - Completion Tracking
    
    /// Which card was played (to mark complete when player closes)
    enum PlayedCard { case primary, secondary }
    @State private var playedCard: PlayedCard? = nil
    
    /// Instance-scoped completion for non-path sessions
    @State private var primaryCompleted: Bool = false
    @State private var secondaryCompleted: Bool = false
    
    /// Access to navigation state for detecting player sheet dismissal
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    /// Check if primary recommendation is a path (uses persistent completion)
    private var isPrimaryPath: Bool {
        if case .path = dualRecommendation.primary.type { return true }
        return false
    }
    
    /// Check if secondary recommendation is a path (uses persistent completion)
    private var isSecondaryPath: Bool {
        guard let secondary = dualRecommendation.secondary else { return false }
        if case .path = secondary.type { return true }
        return false
    }
    
    /// Check if this recommendation has a welcome greeting
    private var hasWelcomeGreeting: Bool {
        dualRecommendation.primary.welcomeGreeting != nil
    }
    
    /// Check if this recommendation has a contextual body message
    private var hasContextMessage: Bool {
        dualRecommendation.primary.contextMessage != nil
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Primary Recommendation Section
            primarySection
            
            // MARK: - Secondary Recommendation Section (if exists)
            if dualRecommendation.secondary != nil {
                secondarySection
            }
        }
        .onChange(of: navigationCoordinator.showPlayerSheet) { oldValue, newValue in
            // Player sheet just closed - only mark the played card as completed
            // if the session was truly completed (100% / session_complete), not just partially played.
            print("[DualRec] onChange showPlayerSheet: \(oldValue) -> \(newValue), playedCard: \(String(describing: playedCard)), sessionFullyCompleted: \(navigationCoordinator.lastSessionFullyCompleted), msgId: \(message.id)")
            if oldValue == true && newValue == false {
                if let played = playedCard {
                    let sessionCompleted = navigationCoordinator.lastSessionFullyCompleted
                    print("[DualRec] Player closed, played: \(played), sessionCompleted: \(sessionCompleted), isPrimaryPath: \(isPrimaryPath), isSecondaryPath: \(isSecondaryPath)")
                    // Only mark non-path sessions as completed when the session was fully completed.
                    // Path cards use persistent PracticeManager and are handled separately.
                    if sessionCompleted {
                        switch played {
                        case .primary:
                            if !isPrimaryPath {
                                print("[DualRec] Marking PRIMARY as completed (session fully completed)")
                                primaryCompleted = true
                            }
                        case .secondary:
                            if !isSecondaryPath {
                                print("[DualRec] Marking SECONDARY as completed (session fully completed)")
                                secondaryCompleted = true
                            }
                        }
                    } else {
                        print("[DualRec] Session was NOT fully completed - not marking card as completed")
                    }
                    playedCard = nil
                } else {
                    print("[DualRec] Player closed but playedCard is nil - ignoring")
                }
            }
        }
    }
    
    // MARK: - Primary Section
    
    private var primarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Greeting — first-ever welcome is bold purple; timely greetings are regular sensei text
            if let welcome = dualRecommendation.primary.welcomeGreeting {
                let isWelcome = dualRecommendation.primary.isFirstWelcome
                
                if isLatestMessage && !welcomeComplete {
                    if isWelcome {
                        // First-ever welcome: bold purple typing animation
                        StyledTypingView(
                            text: welcome,
                            font: .custom("Nunito", size: 22).weight(.bold),
                            color: .textPurple
                        ) {
                            welcomeComplete = true
                        }
                    } else {
                        // Timely greeting: regular sensei text typing animation
                        UnifiedTypingView(
                            content: .text(welcome),
                            isTyping: $conversationState.isTyping,
                            conversationCount: conversationState.conversation.count
                        ) {
                            welcomeComplete = true
                        }
                    }
                } else {
                    if isWelcome {
                        // Static first-ever welcome
                        Text(welcome)
                            .font(.custom("Nunito", size: 22).weight(.bold))
                            .foregroundColor(.textPurple)
                    } else {
                        // Static timely greeting
                        Text(welcome)
                            .nunitoFont(size: 16, style: .medium)
                            .foregroundColor(.white)
                            .lineSpacing(4)
                    }
                }
            }
            
            // Context message — shown after welcome, replaces the intro on the first-ever recommendation.
            // Explains why this meditation was chosen, referencing the user's hurdle naturally.
            // When present it drives the card-reveal sequence itself (no separate intro message shown).
            if let context = dualRecommendation.primary.contextMessage, welcomeComplete {
                if isLatestMessage && !contextComplete {
                    UnifiedTypingView(
                        content: .text(context),
                        isTyping: $conversationState.isTyping,
                        conversationCount: conversationState.conversation.count
                    ) {
                        // Context message finished — reveal the primary card immediately
                        contextComplete = true
                        withAnimation(.easeInOut(duration: 0.3)) {
                            typingStage = 1
                            showPrimaryCard = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                        }
                        if dualRecommendation.secondary != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showSecondaryDivider = true
                                    typingStage = 2
                                    conversationState.isTyping = true
                                }
                            }
                        } else {
                            conversationState.handleTypingComplete()
                        }
                    }
                } else {
                    Text(context)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
            
            // Primary intro message — only shown when there is NO context message.
            // When a context message is present it already serves as the intro.
            if !hasContextMessage && (!hasWelcomeGreeting || welcomeComplete) {
                if isLatestMessage && typingStage == 0 {
                    UnifiedTypingView(
                        content: .text(dualRecommendation.primary.introMessage),
                        isTyping: $conversationState.isTyping,
                        conversationCount: conversationState.conversation.count
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            typingStage = 1
                            showPrimaryCard = true
                        }
                        // Trigger scroll after card appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                        }
                        // Continue to secondary after a delay
                        if dualRecommendation.secondary != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showSecondaryDivider = true
                                    typingStage = 2
                                    conversationState.isTyping = true
                                }
                            }
                        } else {
                            // No secondary - mark as complete
                            conversationState.handleTypingComplete()
                        }
                    }
                } else if !isLatestMessage || typingStage >= 1 {
                    // Static primary intro
                    Text(dualRecommendation.primary.introMessage)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                }
            }
            
            // Primary card
            if showPrimaryCard || !isLatestMessage || typingStage >= 1 {
                primaryCardView
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onAppear {
            // If no welcome greeting, mark welcome as complete immediately
            if !hasWelcomeGreeting {
                welcomeComplete = true
            }
            // If no context message, mark context as complete immediately so the
            // intro is not blocked waiting for a context that will never arrive.
            if !hasContextMessage {
                contextComplete = true
            }
        }
    }
    
    // MARK: - Secondary Section
    
    @ViewBuilder
    private var secondarySection: some View {
        if let secondary = dualRecommendation.secondary {
            // Secondary intro message (no divider - just "Or..." message)
            if isLatestMessage && typingStage == 2 {
                UnifiedTypingView(
                    content: .text(secondary.introMessage),
                    isTyping: $conversationState.isTyping,
                    conversationCount: conversationState.conversation.count
                ) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        typingStage = 3
                        showSecondaryCard = true
                    }
                    // Trigger scroll after card appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                    }
                    // Mark as complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        typingStage = 4
                        conversationState.handleTypingComplete()
                    }
                }
            } else if showSecondaryDivider || !isLatestMessage || typingStage >= 2 {
                // Static secondary intro
                Text(secondary.introMessage)
                    .nunitoFont(size: 16, style: .medium)
                    .foregroundColor(.white)
            }
            
            // Secondary card
            if showSecondaryCard || !isLatestMessage || typingStage >= 3 {
                secondaryCardView(for: secondary)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
    
    // MARK: - Primary Card View
    
    @ViewBuilder
    private var primaryCardView: some View {
        let _ = print("[DualRec] Rendering primaryCardView - primaryCompleted: \(primaryCompleted), secondaryCompleted: \(secondaryCompleted), playedCard: \(String(describing: playedCard)), msgId: \(message.id)")
        switch dualRecommendation.primary.type {
        case .path(let pathStep):
            AIPathRecommendationCardView(
                pathStep: pathStep,
                onPlay: { step in
                    print("[DualRec] PRIMARY path tapped, setting playedCard = .primary, msgId: \(message.id)")
                    playedCard = .primary
                    onPathPlay?(step, .primary)
                },
                isDeselected: secondarySelected == true,
                onSelect: handlePrimarySelected
            )
            
        case .explore(let audioFile):
            AIExploreRecommendationCardView(
                audioFile: audioFile,
                onPlay: { file in
                    print("[DualRec] PRIMARY explore tapped, setting playedCard = .primary, msgId: \(message.id)")
                    playedCard = .primary
                    onExplorePlay?(file, .primary)
                },
                isCompleted: primaryCompleted,
                isDeselected: secondarySelected == true,
                onSelect: handlePrimarySelected
            )
            
        case .custom(let meditation):
            AICustomMeditationCardView(
                meditation: meditation,
                onPlay: { med in
                    print("[DualRec] PRIMARY custom tapped, setting playedCard = .primary, msgId: \(message.id)")
                    playedCard = .primary
                    onCustomPlay?(med, .primary)
                },
                isCompleted: primaryCompleted,
                isDeselected: secondarySelected == true,
                onSelect: handlePrimarySelected
            )
        }
    }
    
    // MARK: - Secondary Card View
    
    @ViewBuilder
    private func secondaryCardView(for item: RecommendationItem) -> some View {
        switch item.type {
        case .path(let pathStep):
            AIPathRecommendationCardView(
                pathStep: pathStep,
                onPlay: { step in
                    print("[DualRec] SECONDARY path tapped, setting playedCard = .secondary, msgId: \(message.id)")
                    playedCard = .secondary
                    onPathPlay?(step, .secondary)
                },
                isSecondary: true,
                isDeselected: secondarySelected == false,
                onSelect: handleSecondarySelected
            )
            
        case .explore(let audioFile):
            AIExploreRecommendationCardView(
                audioFile: audioFile,
                onPlay: { file in
                    print("[DualRec] SECONDARY explore tapped, setting playedCard = .secondary, msgId: \(message.id)")
                    playedCard = .secondary
                    onExplorePlay?(file, .secondary)
                },
                isCompleted: secondaryCompleted,
                isSecondary: true,
                isDeselected: secondarySelected == false,
                onSelect: handleSecondarySelected
            )
            
        case .custom(let meditation):
            AICustomMeditationCardView(
                meditation: meditation,
                onPlay: { med in
                    print("[DualRec] SECONDARY custom tapped, setting playedCard = .secondary, msgId: \(message.id)")
                    playedCard = .secondary
                    onCustomPlay?(med, .secondary)
                },
                isCompleted: secondaryCompleted,
                isSecondary: true,
                isDeselected: secondarySelected == false,
                onSelect: handleSecondarySelected
            )
        }
    }
    
    // MARK: - Selection Handlers
    
    private func handlePrimarySelected() {
        withAnimation(.easeOut(duration: 0.25)) {
            secondarySelected = false
        }
    }
    
    private func handleSecondarySelected() {
        withAnimation(.easeOut(duration: 0.25)) {
            secondarySelected = true
        }
    }
}

// MARK: - Styled Typing View

/// A typing view that supports custom font and color styling
private struct StyledTypingView: View {
    let text: String
    let font: Font
    let color: Color
    let onComplete: () -> Void
    
    @State private var displayedText = ""
    @State private var currentIndex = 0
    @State private var isComplete = false
    
    var body: some View {
        Text(displayedText + (isComplete ? "" : "▋"))
            .font(font)
            .foregroundColor(color)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onAppear {
                startTypingAnimation()
            }
    }
    
    private func startTypingAnimation() {
        let characters = Array(text)
        
        func typeNextCharacter() {
            guard currentIndex < characters.count else {
                isComplete = true
                onComplete()
                return
            }
            
            displayedText.append(characters[currentIndex])
            currentIndex += 1
            
            // Typing speed - slightly faster for welcome
            let delay = 0.025
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                typeNextCharacter()
            }
        }
        
        // Small initial delay before starting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            typeNextCharacter()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DualRecommendationMessageView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundNavy.ignoresSafeArea()
            
            VStack {
                Text("DualRecommendationMessageView Preview")
                    .foregroundColor(.white)
                    .nunitoFont(size: 16, style: .medium)
                Text("Use in actual app context for full preview")
                    .foregroundColor(.textGray)
                    .nunitoFont(size: 14, style: .regular)
            }
            .padding()
        }
    }
}
#endif
