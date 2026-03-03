import SwiftUI

// MARK: - Chat Messages List Component

struct AIChatMessageList: View {
    @ObservedObject var conversationState: AIConversationState
    @ObservedObject var manager: AIRequestManager
    @ObservedObject var keyboardObserver: KeyboardObserver
    @StateObject private var scrollCoordinator = SmoothScrollCoordinator()
    
    let onPlay: (AITimerResponse) -> Void
    let onSenseiMessageCTA: (SenseiOnboardingMessage, SenseiOnboardingCTA, Bool) -> Void
    let onSenseiQuestion: (SenseiOnboardingQuestion, String?, Bool) -> Void
    let onSenseiPromptEducation: (SenseiOnboardingPromptEducation, PromptEducationAction) -> Void
    let onPathPlay: ((PathStep) -> Void)?
    let onExplorePlay: ((AudioFile) -> Void)?
    // Dual recommendation callbacks with position
    let onDualPathPlay: ((PathStep, RecommendationPosition) -> Void)?
    let onDualExplorePlay: ((AudioFile, RecommendationPosition) -> Void)?
    let onDualCustomPlay: ((AITimerResponse, RecommendationPosition) -> Void)?
    // Post-session prompt callback (true = yes, false = no)
    let onPostSessionPromptResponse: ((Bool) -> Void)?
    @Binding var showLastStepThinking: Bool
    
    @State private var lastContentHeight: CGFloat = 0
    @State private var isUserScrolling: Bool = false
    @State private var scrollReenableTask: Task<Void, Never>?
    @State private var scrollDebounceTask: Task<Void, Never>?
    
    // MARK: - Visibility Tracking for Keyboard Scroll Adjustment
    @State private var visibleMessageIds: Set<UUID> = []
    @State private var bottomMostVisibleId: UUID?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Ephemeral welcome removed - greeting is now injected as a real AI message
                    
                    // Conversation messages with date dividers
                    ForEach(conversationState.conversation.withDateDividers()) { item in
                        switch item {
                        case .dateDivider(let date, _):
                            ChatDateDivider(date: date)
                            
                        case .message(let message):
                            AIChatMessage(
                                message: message,
                                conversationState: conversationState,
                                manager: manager,
                                scrollCoordinator: scrollCoordinator,
                                onPlay: onPlay,
                                onSenseiMessageCTA: onSenseiMessageCTA,
                                onSenseiQuestion: onSenseiQuestion,
                                onSenseiPromptEducation: onSenseiPromptEducation,
                                onPathPlay: onPathPlay,
                                onExplorePlay: onExplorePlay,
                                onDualPathPlay: onDualPathPlay,
                                onDualExplorePlay: onDualExplorePlay,
                                onDualCustomPlay: onDualCustomPlay,
                                onPostSessionPromptResponse: onPostSessionPromptResponse
                            )
                            .id(message.id)
                            .onAppear {
                                visibleMessageIds.insert(message.id)
                                updateBottomMostVisible()
                            }
                            .onDisappear {
                                visibleMessageIds.remove(message.id)
                                updateBottomMostVisible()
                            }
                        }
                    }
                    
                    // Last step thinking animation (onboarding completion)
                    if showLastStepThinking {
                        SenseiThinkingAnimationView(
                            isActive: $showLastStepThinking,
                            intent: Binding(
                                get: { manager.classifiedIntent },
                                set: { _ in }
                            )
                        )
                        .id("last-step-thinking")
                    }
                    
                    // Bottom anchor for smooth scrolling
                    Color.clear
                        .frame(height: 20)
                        .id("bottom-anchor")
                }
                .animation(nil, value: conversationState.conversation.count)
                .padding(.top, 32)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ScrollContentHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                    }
                )
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                // Dismiss keyboard when tapping on the scroll view content
                dismissKeyboard()
            }
            .gesture(
                DragGesture(minimumDistance: 25)
                    .onChanged { value in
                        // Only disable follow mode if this is actual scrolling (significant vertical movement)
                        // Button taps have minimal drag distance and low velocity, so they won't trigger this
                        let verticalMovement = abs(value.translation.height)
                        let velocity = abs(value.velocity.height)
                        
                        // Require significant movement AND velocity to distinguish from button taps
                        if verticalMovement > 15 && velocity > 50 {
                            logger.aiChat("🧠 AI_SCROLL: Gesture detected - movement=\(verticalMovement), velocity=\(velocity)")
                            handleUserScrollStart()
                        }
                    }
                    .onEnded { value in
                        let finalMovement = abs(value.translation.height)
                        if finalMovement > 15 {
                            logger.aiChat("🧠 AI_SCROLL: Gesture ended - movement=\(finalMovement)")
                            handleUserScrollEnd()
                        }
                    }
            )
            .onPreferenceChange(ScrollContentHeightPreferenceKey.self) { newHeight in
                handleContentHeightChange(newHeight, proxy: proxy)
            }
            .onPreferenceChange(MessageHeightPreferenceKey.self) { newHeight in
                // When individual message heights change (e.g., options/CTAs appearing),
                // trigger a scroll check after a short delay to allow layout to settle
                logger.aiChat("🧠 AI_SCROLL: MessageHeightPreferenceKey changed to \(newHeight)")
                triggerDebouncedScroll(proxy: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: .aiScrollTrigger)) { _ in
                // Direct scroll trigger from dynamic content (options, CTAs)
                logger.aiChat("🧠 AI_SCROLL: Received aiScrollTrigger notification")
                triggerDebouncedScroll(proxy: proxy)
            }
            .onChange(of: conversationState.conversation.count) { oldCount, newCount in
                if newCount > oldCount {
                    logger.aiChat("🧠 AI_SCROLL: Conversation count changed: \(oldCount) -> \(newCount), followMode=\(scrollCoordinator.shouldFollowContent)")
                    // New message added - enable follow mode and reset user scrolling state
                    isUserScrolling = false
                    scrollCoordinator.enableFollowMode()
                    scrollReenableTask?.cancel()
                    scrollReenableTask = nil
                    
                    // Delay initial scroll slightly to let layout settle (prevents jump from message swap)
                    // This gives SwiftUI time to calculate the new message's height
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        smoothScrollToBottom(proxy: proxy)
                    }
                    
                    // Follow-up scroll to catch any dynamic content
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if scrollCoordinator.shouldFollowContent {
                            smoothScrollToBottom(proxy: proxy)
                        }
                    }
                }
            }
            .onChange(of: conversationState.latestAIMessageId) { oldId, newId in
                if newId != nil {
                    logger.aiChat("🧠 AI_SCROLL: latestAIMessageId changed to \(newId?.uuidString ?? "nil")")
                    // New AI message started - enable follow mode
                    isUserScrolling = false
                    scrollCoordinator.enableFollowMode()
                    scrollReenableTask?.cancel()
                    scrollReenableTask = nil
                    // Note: Scroll is handled by conversation count change, not duplicated here
                }
            }
            .onChange(of: conversationState.isTyping) { oldTyping, newTyping in
                if newTyping {
                    // Typing started - ensure we're following
                    scrollCoordinator.enableFollowMode()
                }
            }
            .onAppear {
                logger.aiChat("🧠 AI_SCROLL: AIChatMessageList appeared - enabling follow mode")
                scrollCoordinator.enableFollowMode()
            }
            .onChange(of: keyboardObserver.keyboardHeight) { oldHeight, newHeight in
                handleKeyboardHeightChange(oldHeight: oldHeight, newHeight: newHeight, proxy: proxy)
            }
        }
    }
    
    // MARK: - Scroll Handling
    
    private func handleContentHeightChange(_ newHeight: CGFloat, proxy: ScrollViewProxy) {
        let heightDelta = newHeight - lastContentHeight
        logger.aiChat("🧠 AI_SCROLL: Height changed from \(lastContentHeight) to \(newHeight), delta=\(heightDelta), followMode=\(scrollCoordinator.shouldFollowContent)")
        
        guard scrollCoordinator.shouldFollowContent else {
            lastContentHeight = newHeight
            logger.aiChat("🧠 AI_SCROLL: Scroll blocked - follow mode disabled")
            return
        }
        
        // Use a small threshold to avoid unnecessary scrolls from minor layout adjustments
        if heightDelta > 1.0 {
            logger.aiChat("🧠 AI_SCROLL: Triggering scroll due to height increase (delta=\(heightDelta))")
            smoothScrollToBottom(proxy: proxy)
        } else if heightDelta < -1.0 {
            // Height decreased - update tracking but don't scroll
            logger.aiChat("🧠 AI_SCROLL: Height decreased by \(abs(heightDelta)), updating tracking only")
        }
        
        lastContentHeight = newHeight
        scrollCoordinator.updateContentHeight(newHeight)
    }
    
    private func triggerDebouncedScroll(proxy: ScrollViewProxy) {
        logger.aiChat("🧠 AI_SCROLL: triggerDebouncedScroll called, followMode=\(scrollCoordinator.shouldFollowContent)")
        
        // Cancel any existing debounce task
        scrollDebounceTask?.cancel()
        
        // Ensure follow mode is enabled when dynamic views appear
        isUserScrolling = false // Reset user scrolling state when dynamic content appears
        scrollCoordinator.enableFollowMode()
        // Cancel any pending re-enable task since we're explicitly enabling now
        scrollReenableTask?.cancel()
        scrollReenableTask = nil
        
        // Debounce scroll trigger to handle rapid sequential updates
        scrollDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(0.05 * 1_000_000_000)) // 50ms debounce
            
            logger.aiChat("🧠 AI_SCROLL: Debounced scroll executing, followMode=\(scrollCoordinator.shouldFollowContent)")
            guard scrollCoordinator.shouldFollowContent else { 
                logger.aiChat("🧠 AI_SCROLL: Debounced scroll blocked - follow mode disabled")
                return 
            }
            smoothScrollToBottom(proxy: proxy)
        }
    }
    
    private func smoothScrollToBottom(proxy: ScrollViewProxy) {
        logger.aiChat("🧠 AI_SCROLL: smoothScrollToBottom called, followMode=\(scrollCoordinator.shouldFollowContent)")
        guard scrollCoordinator.shouldFollowContent else { 
            logger.aiChat("🧠 AI_SCROLL: Scroll blocked - follow mode disabled")
            return 
        }
        
        withAnimation(scrollCoordinator.scrollAnimation) {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
        logger.aiChat("🧠 AI_SCROLL: Scroll executed to bottom-anchor")
    }
    
    private func handleUserScrollStart() {
        logger.aiChat("🧠 AI_SCROLL: User scroll started - disabling follow mode")
        isUserScrolling = true
        scrollCoordinator.disableFollowMode()
        
        // Cancel any pending re-enable task
        scrollReenableTask?.cancel()
        scrollReenableTask = nil
    }
    
    private func handleUserScrollEnd() {
        logger.aiChat("🧠 AI_SCROLL: User scroll ended - will re-enable follow mode in \(AnimationConstants.followModeReenableDelay)s")
        isUserScrolling = false
        
        // Cancel any existing re-enable task
        scrollReenableTask?.cancel()
        
        // Re-enable follow mode after delay if user is not actively scrolling
        scrollReenableTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(AnimationConstants.followModeReenableDelay * 1_000_000_000))
            
            // Only re-enable if user is still not scrolling
            if !isUserScrolling {
                logger.aiChat("🧠 AI_SCROLL: Re-enabling follow mode after user scroll delay")
                scrollCoordinator.enableFollowMode()
            } else {
                logger.aiChat("🧠 AI_SCROLL: Skipping follow mode re-enable - user still scrolling")
            }
        }
    }
    
    // MARK: - Keyboard Scroll Handling
    
    /// Update the bottom-most visible message ID based on current visibility
    private func updateBottomMostVisible() {
        // Find the message that appears last in the conversation among visible ones
        let visibleMessages = conversationState.conversation.filter { visibleMessageIds.contains($0.id) }
        bottomMostVisibleId = visibleMessages.last?.id
        scrollCoordinator.bottomVisibleMessageId = bottomMostVisibleId
    }
    
    /// Handle keyboard height changes by adjusting scroll position
    private func handleKeyboardHeightChange(oldHeight: CGFloat, newHeight: CGFloat, proxy: ScrollViewProxy) {
        if newHeight > oldHeight {
            // Keyboard is appearing or growing - scroll to keep content visible
            logger.aiChat("🧠 AI_SCROLL: Keyboard height increased \(oldHeight) -> \(newHeight), triggering scroll adjustment")
            
            // Update coordinator with keyboard state
            scrollCoordinator.keyboardWillShow(height: newHeight, bottomVisibleMessageId: bottomMostVisibleId)
            
            // Enable follow mode and scroll to bottom
            scrollCoordinator.enableFollowMode()
            
            // Scroll after a brief delay to allow layout to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(keyboardObserver.swiftUIAnimation) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
            
            // Additional delayed scroll to catch any layout changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if scrollCoordinator.shouldFollowContent {
                    withAnimation(scrollCoordinator.scrollAnimation) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
            }
        } else if newHeight == 0 && oldHeight > 0 {
            // Keyboard is hiding
            logger.aiChat("🧠 AI_SCROLL: Keyboard hiding from height=\(oldHeight)")
            scrollCoordinator.keyboardWillHide()
        }
    }
    
    /// Dismiss keyboard by resigning first responder
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        // Persist collapsed state - keyboard will be collapsed on next chat open
        SharedUserStorage.save(value: false, forKey: .aiChatKeyboardExpanded)
    }
}

// MARK: - Preference Keys for Content Height Tracking

/// Preference key to track total scroll content height
struct ScrollContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Preference key to track individual message height changes
/// Used to detect when dynamic views (options, CTAs) appear within messages
struct MessageHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Always update to the latest value to ensure onChange triggers
        // The counter-based approach in QuestionOptionsView ensures unique values
        let next = nextValue()
        if next != value {
            value = next
        }
    }
}
