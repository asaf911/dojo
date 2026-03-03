import SwiftUI

// MARK: - Chat Message Component

struct AIChatMessage: View {
    let message: ChatMessage
    @ObservedObject var conversationState: AIConversationState
    @ObservedObject var manager: AIRequestManager
    @ObservedObject var scrollCoordinator: SmoothScrollCoordinator
    
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
    
    // Action processing state for sensei onboarding CTAs
    @State private var actionIsProcessing: Bool = false
    
    // Post-practice typing sequence state
    // Stages: 0=praise typing, 1=praise done, 2=streak typing, 3=streak done, 4=show graph, 5=hr text typing, 6=complete
    @State private var postPracticeStage: Int = 0
    
    /// Whether this message contains card content that should span full width
    private var hasCardContent: Bool {
        message.meditation != nil ||
        message.dualRecommendation != nil ||
        message.pathRecommendation != nil ||
        message.exploreRecommendation != nil ||
        message.postPracticeContent != nil
    }
    
    var body: some View {
        if message.isUser {
            userMessageView
        } else {
            aiMessageView
        }
    }
    
    // MARK: - User Message View
    
    private var userMessageView: some View {
        HStack {
            Spacer()
            HStack(alignment: .center, spacing: 10) {
                Text(message.content)
                    .nunitoFont(size: 16, style: .medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color(red: 0.08, green: 0.08, blue: 0.14).opacity(0.55))
            .cornerRadius(23)
            .overlay(
                RoundedRectangle(cornerRadius: 23)
                    .inset(by: 0.5)
                    .stroke(Color(red: 0.89, green: 0.89, blue: 0.89).opacity(0.1), lineWidth: 1)
            )
            .frame(maxWidth: .infinity * 0.65, alignment: .trailing)
        }
        .padding(.leading, 60)
    }
    
    // MARK: - AI Message View
    
    private var aiMessageView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                // Message content
                VStack(alignment: .leading, spacing: 8) {
                    // Content with typing animation for latest message
                    let isLatestMessage = message.id == conversationState.latestAIMessageId
                    
                    if let promptEducation = message.senseiPromptEducation {
                        senseiPromptEducationView(promptEducation: promptEducation)
                    } else if let question = message.senseiQuestion {
                        senseiQuestionView(question: question)
                    } else if let senseiMessage = message.senseiMessage {
                        senseiMessageView(message: senseiMessage)
                    } else if let meditation = message.meditation {
                        // AI Custom Meditation Card with acknowledgment text above
                        AIMeditationMessageView(
                            message: message,
                            meditation: meditation,
                            conversationState: conversationState,
                            scrollCoordinator: scrollCoordinator,
                            isLatestMessage: isLatestMessage,
                            onPlay: onPlay
                        )
                    } else if let dualRec = message.dualRecommendation {
                        // Dual recommendation with primary and secondary options
                        DualRecommendationMessageView(
                            message: message,
                            dualRecommendation: dualRec,
                            conversationState: conversationState,
                            manager: manager,
                            isLatestMessage: isLatestMessage,
                            onPathPlay: onDualPathPlay,
                            onExplorePlay: onDualExplorePlay,
                            onCustomPlay: onDualCustomPlay
                        )
                    } else if let prompt = message.postSessionPrompt {
                        // Post-session prompt: "Would you like to meditate more?"
                        PostSessionPromptMessageView(
                            message: message,
                            prompt: prompt,
                            conversationState: conversationState,
                            isLatestMessage: isLatestMessage,
                            onYes: { onPostSessionPromptResponse?(true) },
                            onNo: { onPostSessionPromptResponse?(false) }
                        )
                    } else if let pathStep = message.pathRecommendation {
                        // Path step recommendation with text above card
                        PathRecommendationMessageView(
                            message: message,
                            pathStep: pathStep,
                            conversationState: conversationState,
                            isLatestMessage: isLatestMessage,
                            onPlay: onPathPlay
                        )
                    } else if let exploreSession = message.exploreRecommendation {
                        // Explore session recommendation with text above card
                        ExploreRecommendationMessageView(
                            message: message,
                            audioFile: exploreSession,
                            conversationState: conversationState,
                            isLatestMessage: isLatestMessage,
                            onPlay: onExplorePlay
                        )
                    } else {
                        // When content is empty (our temporary placeholder), show Sensei thinking animation
                        if message.content.isEmpty {
                            SenseiThinkingAnimationView(
                                isActive: Binding.constant(true),
                                intent: Binding(
                                    get: { manager.classifiedIntent },
                                    set: { _ in }
                                )
                            )
                        } else if let postPractice = message.postPracticeContent {
                            // Post-practice message with structured sections
                            postPracticeMessageView(content: postPractice, isLatestMessage: isLatestMessage)
                        } else if isLatestMessage {
                            // Regular AI message with typing animation
                            // Legacy: Heart rate graph card (for backward compatibility)
                            if let hrData = message.heartRateData, hrData.samples.count >= 2 {
                                HeartRateGraphCard(
                                    samples: hrData.samples,
                                    startBPM: hrData.startBPM,
                                    endBPM: hrData.endBPM
                                )
                                .padding(.bottom, 12)
                            }
                            
                            UnifiedTypingView(
                                content: .text(message.content),
                                isTyping: $conversationState.isTyping,
                                conversationCount: conversationState.conversation.count
                            ) {
                                conversationState.handleTypingComplete()
                            }
                            .onChange(of: conversationState.isTyping) { oldTyping, newTyping in
                                if isLatestMessage && newTyping {
                                    logger.aiChat("🧠 AI_SCROLL: Regular message typing started")
                                    NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                                }
                            }
                        } else {
                            // Static older AI message
                            // Legacy: Heart rate graph card (for backward compatibility)
                            if let hrData = message.heartRateData, hrData.samples.count >= 2 {
                                HeartRateGraphCard(
                                    samples: hrData.samples,
                                    startBPM: hrData.startBPM,
                                    endBPM: hrData.endBPM
                                )
                                .padding(.bottom, 12)
                            }
                            
                            Text(message.content)
                                .nunitoFont(size: 16, style: .medium)
                                .foregroundColor(.white)
                                .lineSpacing(4)
                        }
                    }
                }
            }
            .frame(maxWidth: hasCardContent ? .infinity : .infinity * 0.75, alignment: .leading)
            
            if !hasCardContent {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: MessageHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
            }
        )
    }
    
    // MARK: - Post-Practice Message View
    
    /// Displays structured post-practice content in order with staged typing animation:
    /// 1. Completion praise (typed)
    /// 2. Streak message (typed)
    /// 3. Heart rate graph (revealed)
    /// 4. Heart rate text (typed, if available)
    @ViewBuilder
    private func postPracticeMessageView(content: ChatPostPracticeContent, isLatestMessage: Bool) -> some View {
        let hasGraph = content.heartRateGraphData != nil && (content.heartRateGraphData?.samples.count ?? 0) >= 2
        let hasHRText = content.heartRateMessage != nil && !(content.heartRateMessage?.isEmpty ?? true)
        
        VStack(alignment: .leading, spacing: 12) {
            // Section 1: Completion Praise
            if isLatestMessage && postPracticeStage == 0 {
                // Typing the praise
                TypingText(
                    text: content.completionPraise,
                    font: Font.custom("Nunito", size: 16).weight(.medium),
                    color: .white,
                    onComplete: {
                        postPracticeStage = 1
                        // Small delay before next section
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            postPracticeStage = 2
                        }
                    }
                )
                .lineSpacing(4)
            } else if postPracticeStage >= 1 || !isLatestMessage {
                // Praise complete - show static
                Text(content.completionPraise)
                    .nunitoFont(size: 16, style: .medium)
                    .foregroundColor(.white)
                    .lineSpacing(4)
            }
            
            // Section 2: Streak Message
            if !content.streakMessage.isEmpty {
                if isLatestMessage && postPracticeStage == 2 {
                    // Typing the streak message
                    TypingText(
                        text: content.streakMessage,
                        font: Font.custom("Nunito", size: 16).weight(.medium),
                        color: .white,
                        onComplete: {
                            postPracticeStage = 3
                            // Small delay before graph
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                postPracticeStage = 4
                            }
                        }
                    )
                    .lineSpacing(4)
                } else if postPracticeStage >= 3 || !isLatestMessage {
                    // Streak complete - show static
                    Text(content.streakMessage)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
            
            // Section 3: Heart Rate Graph (if available)
            if hasGraph, let hrData = content.heartRateGraphData {
                if postPracticeStage >= 4 || !isLatestMessage {
                    HeartRateGraphCard(
                        samples: hrData.samples,
                        startBPM: hrData.startBPM,
                        endBPM: hrData.endBPM
                    )
                    .padding(.vertical, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .onAppear {
                        if isLatestMessage && postPracticeStage == 4 {
                            // Delay before HR text
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                postPracticeStage = 5
                            }
                        }
                    }
                }
            }
            
            // Section 4: Heart Rate Text (if available)
            if hasHRText, let hrMessage = content.heartRateMessage {
                if isLatestMessage && postPracticeStage == 5 {
                    // Typing the HR text
                    TypingText(
                        text: hrMessage,
                        font: Font.custom("Nunito", size: 16).weight(.medium),
                        color: .white,
                        onComplete: {
                            postPracticeStage = 6
                            conversationState.handleTypingComplete()
                        }
                    )
                    .lineSpacing(4)
                } else if postPracticeStage >= 6 || !isLatestMessage {
                    // HR text complete - show static
                    Text(hrMessage)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
            
            // Note: Path next-step and path-complete recommendations are now handled
            // as separate dual recommendation messages after post-practice typing completes,
            // triggered by AIChatContainerView via DualRecommendationOrchestrator.
        }
        .onAppear {
            if isLatestMessage && conversationState.isTyping {
                // Start the typing sequence
                postPracticeStage = 0
            }
        }
        .onChange(of: postPracticeStage) { oldStage, newStage in
            if isLatestMessage && newStage > oldStage {
                logger.aiChat("🧠 AI_SCROLL: Post-practice stage changed: \(oldStage) -> \(newStage)")
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
            
            // Handle completion when no graph or HR text
            if isLatestMessage {
                let hasGraph = content.heartRateGraphData != nil && (content.heartRateGraphData?.samples.count ?? 0) >= 2
                let hasHRText = content.heartRateMessage != nil && !(content.heartRateMessage?.isEmpty ?? true)
                
                // If no graph and streak done, complete
                if !hasGraph && newStage == 3 {
                    conversationState.handleTypingComplete()
                }
                // If has graph but no HR text and graph shown, complete
                else if hasGraph && !hasHRText && newStage == 4 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        conversationState.handleTypingComplete()
                    }
                }
            }
        }
        // Safety timeout - force complete after 10 seconds
        .onAppear {
            if isLatestMessage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    if conversationState.isTyping && postPracticeStage < 6 {
                        postPracticeStage = 6
                        conversationState.handleTypingComplete()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions

    @ViewBuilder
    private func senseiMessageView(message: SenseiOnboardingMessage) -> some View {
        let isLatestMessage = self.message.id == conversationState.latestAIMessageId
        
        VStack(alignment: .leading, spacing: 16) {
            // Message content with typing animation
            VStack(alignment: .leading, spacing: 8) {
                if isLatestMessage && conversationState.isTyping {
                    // Animated typing view for latest message with preserved formatting
                    SenseiTypingView(
                        message: message,
                        isTyping: $conversationState.isTyping,
                        conversationCount: conversationState.conversation.count
                    ) {
                        conversationState.handleTypingComplete()
                    }
                    .onChange(of: conversationState.isTyping) { oldTyping, newTyping in
                        if isLatestMessage && newTyping {
                            logger.aiChat("🧠 AI_SCROLL: Sensei message typing started")
                            NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                        }
                    }
                } else {
                    // Static view for older messages or when typing is complete
                    if !message.title.isEmpty {
                        Text(message.title)
                            .font(Font.custom("Nunito", size: 22).weight(.bold))
                            .kerning(0.32)
                            .foregroundColor(.selectedLightPurple)
                    }
                    
                    if !message.body.isEmpty {
                        Text(message.body)
                            .nunitoFont(size: 16, style: .medium)
                            .foregroundColor(.white)
                            .lineSpacing(4)
                    }
                    
                    if let caption = message.caption, !caption.isEmpty {
                        Text(caption)
                            .nunitoFont(size: 14, style: .regular)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // CTA attached to message (if present) - only show after typing completes
            if let cta = message.cta, (!isLatestMessage || conversationState.isTypingComplete) {
                SenseiCTAView(
                    continueTitle: cta.primaryTitle,
                    skipTitle: cta.skipTitle,
                    isEnabled: true,
                    isLoading: manager.isLoading || actionIsProcessing,
                    isValid: true,
                    onContinue: {
                        guard !actionIsProcessing else { return }
                        actionIsProcessing = true
                        onSenseiMessageCTA(message, cta, false)
                    },
                    onSkip: cta.skipTitle != nil ? {
                        guard !actionIsProcessing else { return }
                        actionIsProcessing = true
                        onSenseiMessageCTA(message, cta, true)
                    } : nil
                )
            }
        }
    }
    
    @ViewBuilder
    private func senseiQuestionView(question: SenseiOnboardingQuestion) -> some View {
        let isLatestMessage = message.id == conversationState.latestAIMessageId
        
        VStack(alignment: .leading, spacing: 16) {
            // Preamble and question with typing animation
            if isLatestMessage && conversationState.isTyping {
                // Animated typing view for preamble + question
                SenseiQuestionTypingView(
                    question: question,
                    isTyping: $conversationState.isTyping,
                    conversationCount: conversationState.conversation.count
                ) {
                    conversationState.handleTypingComplete()
                }
                .onChange(of: conversationState.isTyping) { oldTyping, newTyping in
                    if isLatestMessage && newTyping {
                        logger.aiChat("🧠 AI_SCROLL: Sensei question typing started")
                        NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                    }
                }
            } else {
                // Static view for older messages or when typing is complete
                // Show preamble (regular text)
                if let preamble = question.preamble, !preamble.isEmpty {
                    Text(preamble)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
                
                // Show question (bold 22pt)
                if !question.question.isEmpty {
                    Text(question.question)
                        .font(Font.custom("Nunito", size: 22).weight(.bold))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
            
            // Options and CTA - only show after typing completes
            if !isLatestMessage || conversationState.isTypingComplete {
                if let cta = question.cta {
                    QuestionOptionsView(
                        preamble: nil, // Already shown above with typing
                        question: "", // Already shown above with typing
                        options: question.options,
                        continueTitle: cta.primaryTitle,
                        skipTitle: cta.skipTitle,
                        allowsMultipleSelection: question.allowsMultipleSelection,
                        isLatestMessage: isLatestMessage,
                        onContinue: { selectedOption in
                            guard !actionIsProcessing else { return }
                            actionIsProcessing = true
                            onSenseiQuestion(question, selectedOption, false)
                        },
                        onSkip: cta.skipTitle != nil ? {
                            guard !actionIsProcessing else { return }
                            actionIsProcessing = true
                            onSenseiQuestion(question, nil, true)
                        } : nil,
                        conversationState: conversationState
                    )
                } else {
                    // Fallback if no CTA (shouldn't happen but handle gracefully)
                    QuestionOptionsView(
                        preamble: nil,
                        question: "",
                        options: question.options,
                        continueTitle: "Continue",
                        skipTitle: nil,
                        allowsMultipleSelection: question.allowsMultipleSelection,
                        isLatestMessage: isLatestMessage,
                        onContinue: { selectedOption in
                            guard !actionIsProcessing else { return }
                            actionIsProcessing = true
                            onSenseiQuestion(question, selectedOption, false)
                        },
                        onSkip: nil,
                        conversationState: conversationState
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private func senseiPromptEducationView(promptEducation: SenseiOnboardingPromptEducation) -> some View {
        let isLatestMessage = message.id == conversationState.latestAIMessageId
        
        // Contextual text based on how user arrived at final step
        let arrivedViaSkip = SenseiOnboardingState.shared.arrivedAtFinalViaSkip
        
        let contextualIntroText: String = arrivedViaSkip
            ? "That's completely fine."
            : "Thank you. I now have everything I need to create your first personalized practice."
        
        let contextualPreamble: String = arrivedViaSkip
            ? "Anything specific you'd like?"
            : "Any other requests?"
        
        // Combine introText and preamble for typing animation
        let fullTypingText = contextualIntroText + "\n\n" + contextualPreamble
        
        VStack(alignment: .leading, spacing: 16) {
            // Text with typing animation for latest message
            if isLatestMessage && conversationState.isTyping {
                UnifiedTypingView(
                    content: .text(fullTypingText),
                    isTyping: $conversationState.isTyping,
                    conversationCount: conversationState.conversation.count
                ) {
                    conversationState.handleTypingComplete()
                }
                .onChange(of: conversationState.isTyping) { oldTyping, newTyping in
                    if isLatestMessage && newTyping {
                        logger.aiChat("🧠 AI_SCROLL: Prompt education typing started")
                        NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                    }
                }
            } else {
                // Static text when not typing - show both parts with proper styling
                VStack(alignment: .leading, spacing: 8) {
                    // Intro text (regular style)
                    Text(contextualIntroText)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                    
                    // Preamble (bold question style)
                    Text(contextualPreamble)
                        .font(Font.custom("Nunito", size: 22).weight(.bold))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
            
            // Show prompt education content after typing completes
            if !isLatestMessage || conversationState.isTypingComplete {
                PromptEducationView(
                    preamble: "", // Already shown above with typing
                    instruction: promptEducation.instruction,
                    examplePrompts: promptEducation.examplePrompts,
                    isLatestMessage: isLatestMessage,
                    onAction: { action in
                        onSenseiPromptEducation(promptEducation, action)
                    }
                )
            }
        }
    }
    
}

// MARK: - AI Meditation Message View (Simple: ACK types, card appears, scroll follows)

/// Displays AI meditation messages with simple, predictable behavior:
/// 1. Acknowledgment text types in (scroll follows naturally)
/// 2. Card appears immediately after typing (no animation)
/// 3. Scroll continues to bottom
private struct AIMeditationMessageView: View {
    let message: ChatMessage
    let meditation: AITimerResponse
    @ObservedObject var conversationState: AIConversationState
    @ObservedObject var scrollCoordinator: SmoothScrollCoordinator
    let isLatestMessage: Bool
    
    let onPlay: (AITimerResponse) -> Void
    
    // Track if card should be shown (after typing completes for latest message)
    @State private var showCard: Bool = false
    
    private var hasAcknowledgment: Bool {
        !message.content.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Acknowledgment text with typing effect for latest message
            if hasAcknowledgment {
                if isLatestMessage && !showCard {
                    UnifiedTypingView(
                        content: .text(message.content),
                        isTyping: .constant(true),
                        conversationCount: conversationState.conversation.count
                    ) {
                        // Typing complete - show card immediately, no animation
                        showCard = true
                        conversationState.handleTypingComplete()
                    }
                } else {
                    Text(message.content)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                }
            }
            
            // Card appears immediately when showCard is true - no animation
            if showCard {
                AICustomMeditationCardView(
                    meditation: meditation,
                    onPlay: onPlay
                )
            }
        }
        .onAppear {
            // For non-latest messages or messages without acknowledgment, show card immediately
            if !isLatestMessage || !hasAcknowledgment {
                showCard = true
            }
        }
    }
}

// MARK: - Path Recommendation Message View

/// Displays path recommendation messages with simple, predictable behavior:
/// 1. Recommendation text types in (scroll follows naturally)
/// 2. Path card appears immediately after typing (no animation)
/// 3. Scroll continues to bottom
private struct PathRecommendationMessageView: View {
    let message: ChatMessage
    let pathStep: PathStep
    @ObservedObject var conversationState: AIConversationState
    let isLatestMessage: Bool
    
    let onPlay: ((PathStep) -> Void)?
    
    // Track if card should be shown (after typing completes for latest message)
    @State private var showCard: Bool = false
    
    // Two-phase typing for first step: welcome first, then message
    @State private var welcomeComplete: Bool = false
    
    private var hasRecommendationText: Bool {
        !message.content.isEmpty
    }
    
    /// Welcome greeting for first step only (styled differently)
    private var welcomeGreeting: String? {
        guard pathStep.order == 1 else { return nil }
        let firstName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)?
            .split(separator: " ").first.map(String.init)
        return firstName.map { "Welcome \($0)," } ?? "Welcome traveler,"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recommendation text with typing effect for latest message
            if hasRecommendationText {
                if isLatestMessage && !showCard {
                    // Typing animation in progress
                    VStack(alignment: .leading, spacing: 8) {
                        if let welcome = welcomeGreeting {
                            if !welcomeComplete {
                                // Phase 1: Type welcome with custom styling
                                StyledTypingView(
                                    text: welcome,
                                    font: .custom("Nunito", size: 22).weight(.bold),
                                    color: .textPurple
                                ) {
                                    welcomeComplete = true
                                }
                            } else {
                                // Welcome complete - show static
                                Text(welcome)
                                    .font(.custom("Nunito", size: 22).weight(.bold))
                                    .foregroundColor(.textPurple)
                            }
                        }
                        
                        // Phase 2: Type message (only after welcome completes, or immediately if no welcome)
                        if welcomeGreeting == nil || welcomeComplete {
                            UnifiedTypingView(
                                content: .text(message.content),
                                isTyping: .constant(true),
                                conversationCount: conversationState.conversation.count
                            ) {
                                // Typing complete - show card immediately, no animation
                                showCard = true
                                conversationState.handleTypingComplete()
                            }
                        }
                    }
                } else {
                    // Static display with custom welcome styling
                    VStack(alignment: .leading, spacing: 8) {
                        if let welcome = welcomeGreeting {
                            Text(welcome)
                                .font(.custom("Nunito", size: 22).weight(.bold))
                                .foregroundColor(.textPurple)
                        }
                        
                        Text(message.content)
                            .nunitoFont(size: 16, style: .medium)
                            .foregroundColor(.white)
                            .lineSpacing(4)
                    }
                }
            }
            
            // Card appears immediately when showCard is true - no animation
            if showCard {
                AIPathRecommendationCardView(
                    pathStep: pathStep,
                    onPlay: { step in
                        onPlay?(step)
                    }
                )
            }
        }
        .onAppear {
            // For non-latest messages or messages without recommendation text, show card immediately
            if !isLatestMessage || !hasRecommendationText {
                showCard = true
            }
            // If no welcome greeting, skip to message phase
            if welcomeGreeting == nil {
                welcomeComplete = true
            }
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

// MARK: - Explore Recommendation Message View

/// Displays explore recommendation messages with simple, predictable behavior:
/// 1. Recommendation text types in (scroll follows naturally)
/// 2. Explore card appears immediately after typing (no animation)
/// 3. Scroll continues to bottom
private struct ExploreRecommendationMessageView: View {
    let message: ChatMessage
    let audioFile: AudioFile
    @ObservedObject var conversationState: AIConversationState
    let isLatestMessage: Bool
    
    let onPlay: ((AudioFile) -> Void)?
    
    // Track if card should be shown (after typing completes for latest message)
    @State private var showCard: Bool = false
    
    private var hasRecommendationText: Bool {
        !message.content.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recommendation text with typing effect for latest message
            if hasRecommendationText {
                if isLatestMessage && !showCard {
                    UnifiedTypingView(
                        content: .text(message.content),
                        isTyping: .constant(true),
                        conversationCount: conversationState.conversation.count
                    ) {
                        // Typing complete - show card immediately, no animation
                        showCard = true
                        conversationState.handleTypingComplete()
                    }
                } else {
                    Text(message.content)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
            
            // Card appears immediately when showCard is true - no animation
            if showCard {
                AIExploreRecommendationCardView(
                    audioFile: audioFile,
                    onPlay: { session in
                        onPlay?(session)
                    }
                )
            }
        }
        .onAppear {
            // For non-latest messages or messages without recommendation text, show card immediately
            if !isLatestMessage || !hasRecommendationText {
                showCard = true
            }
        }
    }
}

// MARK: - Post Session Prompt Message View

/// Displays a post-session prompt message with typing animation and Yes/No buttons.
/// The question text types in first, then the buttons appear after typing completes.
private struct PostSessionPromptMessageView: View {
    let message: ChatMessage
    let prompt: PostSessionPrompt
    @ObservedObject var conversationState: AIConversationState
    let isLatestMessage: Bool
    
    let onYes: () -> Void
    let onNo: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Question text with typing animation for latest message
            if isLatestMessage && conversationState.isTyping {
                UnifiedTypingView(
                    content: .text(message.content),
                    isTyping: $conversationState.isTyping,
                    conversationCount: conversationState.conversation.count
                ) {
                    conversationState.handleTypingComplete()
                }
                .onChange(of: conversationState.isTyping) { oldTyping, newTyping in
                    if isLatestMessage && newTyping {
                        logger.aiChat("🤔 [POST_SESSION_PROMPT] Question typing started")
                        NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                    }
                }
            } else {
                // Static text for older messages or after typing completes
                Text(message.content)
                    .nunitoFont(size: 16, style: .medium)
                    .foregroundColor(.white)
                    .lineSpacing(4)
            }
            
            // Buttons appear after typing completes
            if !isLatestMessage || conversationState.isTypingComplete {
                PostSessionPromptView(
                    prompt: prompt,
                    isLatestMessage: isLatestMessage,
                    onYes: onYes,
                    onNo: onNo
                )
            }
        }
    }
}
