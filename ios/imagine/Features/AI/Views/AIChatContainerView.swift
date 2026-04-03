import SwiftUI
import Combine

// MARK: - Chat Container View

@MainActor
final class TimelyRecommendationGate {
    static let shared = TimelyRecommendationGate()
    var isInFlight: Bool = false
    private init() {}
}

struct AIChatContainerView: View {
    @StateObject private var manager = AIRequestManager()
    @StateObject private var keyboardObserver = KeyboardObserver()
    @ObservedObject var conversationState: AIConversationState
    @ObservedObject var keyboardController = ChatKeyboardController.shared
    @ObservedObject private var pathProgressManager = PathProgressManager.shared
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @Environment(\.toggleMenu) private var toggleMenu
    
    @State private var onboardingSteps: SenseiOnboardingSequence = []
    @State private var hasQueuedOnboarding = false
    @State private var activeActionMessageId: UUID?
    @State private var pendingOnboardingStepIndex: Int?
    @State private var pendingOnboardingMessageId: UUID?
    @State private var showLastStepThinking: Bool = false
    @State private var showClearChatConfirmation: Bool = false
    
    var body: some View {
        DojoScreenContainer(
            headerTitle: "Dojo",
            backgroundImageName: GreetingManager.TimeOfDay.fromCurrentHour().dojoBackgroundImageName,
            showBackButton: false,
            menuAction: toggleMenu,
            showMenuButton: true,
            showFooter: false,
            headerTrailing: {
                HeaderControlsView {
                    // Clear chat button
                    Button(action: {
                        // Only show confirmation if there's something to clear
                        if !conversationState.conversation.isEmpty {
                            showClearChatConfirmation = true
                        }
                    }) {
                        Image("cleanChat")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundColor(.white)
                            .accessibilityLabel("Clear chat")
                    }
                }
            }
        ) {
            chatContentView
        }
        .animation(.easeInOut(duration: 0.3), value: keyboardController.shouldBeFocused)
        .onAppear {
            handleOnAppear()
        }
        .onReceive(PostSessionMessageStore.shared.publisher) { report in
            handlePostPracticeReport(report)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiOnboardingCleared)) { _ in
            handleOnboardingCleared()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiTriggerSubscription)) { _ in
            handleSubscriptionTrigger()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiPathGuidanceRecommendation)) { notification in
            handlePathGuidanceRecommendation(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiExploreGuidanceRecommendation)) { notification in
            handleExploreGuidanceRecommendation(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .journeyPhaseChanged)) { notification in
            handleJourneyPhaseChanged(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .journeyShowTransition)) { notification in
            handleJourneyShowTransition(notification)
        }
        .onChange(of: manager.generatedMeditation) { _, newMeditation in
            handleGeneratedMeditation(newMeditation)
        }
        .onChange(of: manager.conversationalResponse) { _, newResponse in
            handleConversationalResponse(newResponse)
        }
        .onChange(of: manager.isLoading) { _, loading in
            handleLoadingChange(loading)
        }
        .onChange(of: manager.error) { _, newError in
            handleError(newError)
        }
        .onChange(of: conversationState.latestAIMessageId) { _, newMessageId in
            handleLatestAIMessageIdChange(newMessageId)
        }
        .onChange(of: keyboardObserver.keyboardHeight) { oldHeight, newHeight in
            handleKeyboardHeightChange(from: oldHeight, to: newHeight)
        }
        .onChange(of: pathProgressManager.isLoaded) { wasLoaded, isLoaded in
            handlePathStepsLoaded(wasLoaded: wasLoaded, isLoaded: isLoaded)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            handleReturnFromBackground()
        }
        .alert("Clear Chat", isPresented: $showClearChatConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearChat()
            }
        } message: {
            Text("This will clear your conversation history. This action cannot be undone.")
        }
    }
    
    // MARK: - View Components
    
    /// Main chat content view - used inside DojoScreenContainer
    private var chatContentView: some View {
        VStack(spacing: 0) {
            // Chat container with designer's specifications
            // Note: DojoScreenContainer automatically adds top offset
            chatContainer
            
            // Space between container and input (consistent spacing)
            Spacer().frame(height: 8)
            
            // Input Area
            AIChatInput(
                conversationState: conversationState,
                manager: manager,
                keyboardController: keyboardController,
                onSend: sendMessage
            )
            
            // Bottom padding (reduced when keyboard visible)
            Spacer().frame(height: keyboardObserver.isKeyboardVisible ? 8 : 26)
        }
    }
    
    /// Chat messages container with styling (matches PlayerView container style)
    /// Layout: Screen edge | 16px | container edge | 16px | content | 16px | container edge | 16px | screen edge
    private var chatContainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            AIChatMessageList(
                conversationState: conversationState,
                manager: manager,
                keyboardObserver: keyboardObserver,
                onPlay: playMeditationDirectly,
                onSenseiMessageCTA: handleSenseiMessageCTA,
                onSenseiQuestion: handleSenseiQuestion,
                onSenseiPromptEducation: handleSenseiPromptEducation,
                onPathPlay: playPathStep,
                onExplorePlay: playExploreSession,
                onDualPathPlay: playDualPathStep,
                onDualExplorePlay: playDualExploreSession,
                onDualCustomPlay: playDualCustomMeditation,
                onPostSessionPromptResponse: handlePostSessionPromptResponse,
                showLastStepThinking: $showLastStepThinking
            )
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .surfaceBackground(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.planBorder.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Event Handlers
    
    private func handleKeyboardHeightChange(from oldHeight: CGFloat, to newHeight: CGFloat) {
        // Skip keyboard-triggered scroll adjustments when AI is responding
        // This prevents UI jumps from brief keyboard flashes during auto-focus rejection
        let isSuppressed = !keyboardController.state.shouldAllowFocus
        
        if newHeight > 0 && oldHeight == 0 {
            // Keyboard appeared
            if isSuppressed {
                logger.aiChat("🧠 AI_DEBUG [KEYBOARD]: Keyboard appeared height=\(newHeight) but SUPPRESSED - skipping scroll")
            } else {
                logger.aiChat("🧠 AI_DEBUG [KEYBOARD]: Keyboard appeared height=\(newHeight), triggering scroll adjustment")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                }
            }
        } else if newHeight == 0 && oldHeight > 0 {
            // Keyboard hidden
            logger.aiChat("🧠 AI_DEBUG [KEYBOARD]: Keyboard hidden from height=\(oldHeight)")
        } else if newHeight != oldHeight {
            // Keyboard resized (e.g., emoji keyboard toggle)
            if isSuppressed {
                logger.aiChat("🧠 AI_DEBUG [KEYBOARD]: Keyboard resized \(oldHeight) -> \(newHeight) but SUPPRESSED - skipping scroll")
            } else {
                logger.aiChat("🧠 AI_DEBUG [KEYBOARD]: Keyboard resized \(oldHeight) -> \(newHeight)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                }
            }
        }
    }
    
    private func handleOnAppear() {
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
        print("📊 JOURNEY: [DEV_SKIP] AIChatContainerView.handleOnAppear() CALLED")
        print("📊 JOURNEY: [DEV_SKIP] Current state:")
        print("📊 JOURNEY: [DEV_SKIP]   - currentPhase: \(ProductJourneyManager.shared.currentPhase.displayName)")
        print("📊 JOURNEY: [DEV_SKIP]   - allStepsCompleted: \(PathProgressManager.shared.allStepsCompleted)")
        print("📊 JOURNEY: [DEV_SKIP]   - nextStep: \(PathProgressManager.shared.nextStep?.id ?? "nil")")
        print("📊 JOURNEY: [DEV_SKIP]   - conversation.count: \(conversationState.conversation.count)")
        #endif
        
        logger.aiChat("🧠 AI_DEBUG handleOnAppear called")
        
        // Clear any stale AI response suppression from previous session
        // This fixes keyboard getting stuck if user left while AI was responding
        keyboardController.clearStaleSuppressionOnAppear()
        
        // Force collapse on appear - will be restored if needed
        keyboardController.forceCollapse()
        
        // Load persisted conversation if available
        conversationState.loadIfNeeded()
        
        // Seed recommendation dedup from persisted history so previous session's
        // recommendations are excluded even after a fresh app launch.
        DualRecommendationOrchestrator.shared.seedRecentlyRecommended(from: conversationState.conversation)
        
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] After loadIfNeeded: conversation.count=\(conversationState.conversation.count)")
        #endif
        
        let onboardingQueued = queueOnboardingIfNeeded(force: false)
        
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] onboardingQueued: \(onboardingQueued)")
        #endif
        
        if onboardingQueued {
            // Onboarding active - suppress keyboard
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] Onboarding queued - suppressing keyboard, NOT showing recommendation")
            print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
            #endif
            keyboardController.suppressForOnboarding()
        } else {
            // No onboarding - restore persisted keyboard state
            keyboardController.restorePersistedState()
            
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] No onboarding queued - calling checkAndShowRecommendation()")
            #endif
            
            // Check if we should show recommendation based on journey phase
            checkAndShowRecommendation()
        }

        // Prefetch resources and config once to avoid cold-start lag
        Task {
            await manager.refreshRules()
            // Warm catalogs
            CatalogsManager.shared.fetchCatalogs(triggerContext: "AIChatContainerView|onAppear preload")
        }
        
        // Check for pending meditation from subscription flow and auto-play
        if let pendingMeditation = navigationCoordinator.pendingAIMeditation {
            logger.aiChat("🧠 AI_DEBUG PENDING_MEDITATION found - auto-playing after subscription flow")
            // Clear pending meditation before playing to prevent loop
            navigationCoordinator.pendingAIMeditation = nil
            // Small delay to let the view settle before navigating
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.playMeditationDirectly(pendingMeditation)
            }
        }
    }
    
    // MARK: - Journey Recommendation
    
    /// Check if we should show a recommendation based on user's journey phase.
    /// Uses DualRecommendationOrchestrator to get both primary and secondary options.
    private func checkAndShowRecommendation() {
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
        print("📊 JOURNEY: [DEV_SKIP] checkAndShowRecommendation() CALLED")
        print("📊 JOURNEY: [DEV_SKIP] Checking conditions...")
        #endif
        
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] checkAndShowRecommendation() called")
        
        // Only show if onboarding is complete
        let onboardingComplete = SenseiOnboardingState.shared.isComplete
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP]   1. SenseiOnboardingState.isComplete: \(onboardingComplete)")
        #endif
        guard onboardingComplete else {
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] ❌ BLOCKED: onboarding not complete")
            print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
            #endif
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] skipped - onboarding not complete")
            logTimelySkip(reason: "onboarding_incomplete")
            return
        }

        if TimelyRecommendationGate.shared.isInFlight {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] skipped - timely fetch already in flight")
            logTimelySkip(reason: "timely_fetch_in_flight")
            return
        }

        // If post-session flow is still active, defer timely suggestion.
        // We'll retry after prompt resolution.
        if isPostSessionFlowActive() {
            hasDeferredTimelyRecommendationCheck = true
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] skipped - post-session prompt flow active, deferring timely suggestion")
            logTimelySkip(reason: "prompt_active")
            return
        }

        // Check slot-based rules - one timely launch suggestion per time slot per day.
        // (Recommendations are appended to the existing conversation thread,
        // so conversation emptiness is intentionally not checked here.)
        let shouldAutoSuggest = ExploreRecommendationManager.shared.shouldAutoSuggestTimelyNow()
        let usedDevTimeOverride = ExploreRecommendationManager.shared.isDevTimeOverrideActive()
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP]   3. shouldAutoSuggestTimelyNow: \(shouldAutoSuggest)")
        print("📊 JOURNEY: [DEV_SKIP]      lastSuggestedSlot: \(ExploreRecommendationManager.shared.getLastSuggestedSlot() ?? "nil")")
        print("📊 JOURNEY: [DEV_SKIP]      currentSlot: \(ExploreRecommendationManager.shared.getCurrentSlotKey())")
        #endif
        guard shouldAutoSuggest else {
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] ❌ BLOCKED: slot already suggested")
            print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
            #endif
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] skipped - slot already suggested")
            logTimelySkip(reason: "slot_used")
            if usedDevTimeOverride {
                ExploreRecommendationManager.shared.clearDevTimeOverride()
            }
            return
        }
        
        let currentPhase = ProductJourneyManager.shared.currentPhase
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP]   4. currentPhase: \(currentPhase.displayName)")
        print("📊 JOURNEY: [DEV_SKIP] ✅ ALL CONDITIONS PASSED - fetching recommendation...")
        #endif
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] current phase: \(currentPhase.displayName) - using dual recommendation orchestrator")

        // For returning users, show a brief timely greeting before thinking appears.
        addTimelyGreetingIfNeeded()

        // Show thinking animation immediately after the greeting — the orchestrator
        // may call AI generation, so we display the same SenseiThinkingAnimationView
        // used for user-initiated requests.
        handleLoadingChange(true)

        TimelyRecommendationGate.shared.isInFlight = true
        isTimelyRecommendationInFlight = true

        // Use the new dual recommendation orchestrator
        timelyRecommendationTask?.cancel()
        timelyRecommendationTask = Task {
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] Calling DualRecommendationOrchestrator.getDualRecommendation()...")
            #endif
            
            // Greeting is shown as a dedicated chat message above thinking.
            // Disable orchestrator greeting here to avoid duplicated greeting copy.
            guard let dualRec = await DualRecommendationOrchestrator.shared.getDualRecommendation(includeGreeting: false) else {
                #if DEBUG
                print("📊 JOURNEY: [DEV_SKIP] ❌ getDualRecommendation() returned nil!")
                print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
                #endif
                logger.aiChat("🧠 AI_DEBUG [JOURNEY] no dual recommendation available")
                await MainActor.run { removeThinkingMessageIfNeeded() }
                await MainActor.run {
                    logTimelySkip(reason: "generation_failed")
                    if usedDevTimeOverride {
                        ExploreRecommendationManager.shared.clearDevTimeOverride()
                    }
                    TimelyRecommendationGate.shared.isInFlight = false
                    isTimelyRecommendationInFlight = false
                    timelyRecommendationTask = nil
                }
                return
            }
            
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] ✅ Got recommendation!")
            print("📊 JOURNEY: [DEV_SKIP]   - primary type: \(dualRec.primary.type.analyticsType)")
            print("📊 JOURNEY: [DEV_SKIP]   - secondary type: \(dualRec.secondary?.type.analyticsType ?? "none")")
            #endif
            
            // Display dual recommendation (thinking message is removed inside displayDualRecommendation)
            await MainActor.run {
                #if DEBUG
                print("📊 JOURNEY: [DEV_SKIP] Displaying recommendation...")
                print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
                #endif
                ExploreRecommendationManager.shared.markTimelySlotAsSuggested()
                AnalyticsManager.shared.logEvent("timely_suggest_slot_marked_after_success", parameters: [
                    "slot": ExploreRecommendationManager.shared.getCurrentSlotKey(),
                    "phase": ProductJourneyManager.shared.currentPhase.analyticsName
                ])
                self.lastRecommendationTrigger = .timely
                displayDualRecommendation(dualRec)
                if usedDevTimeOverride {
                    ExploreRecommendationManager.shared.clearDevTimeOverride()
                }
                TimelyRecommendationGate.shared.isInFlight = false
                isTimelyRecommendationInFlight = false
                timelyRecommendationTask = nil
            }
        }
    }

    private func isPostSessionFlowActive() -> Bool {
        if pendingPostSessionPrompt || pendingPostSessionPromptIsPathComplete {
            return true
        }
        // Only block timely while prompt scheduling is actively in flight.
        // An already-rendered unresolved prompt should not block timely recommendations.
        return postSessionPromptTask != nil
    }

    private func logTimelySkip(reason: String) {
        logger.aiChat("🧠 AI_DEBUG [TIMELY] skipped reason=\(reason)")
        AnalyticsManager.shared.logEvent("timely_suggest_skipped_reason", parameters: [
            "reason": reason,
            "slot": ExploreRecommendationManager.shared.getCurrentSlotKey(),
            "phase": ProductJourneyManager.shared.currentPhase.analyticsName
        ])
    }

    private func addTimelyGreetingIfNeeded() {
        guard shouldShowTimelyPreThinkingGreeting() else {
            return
        }

        let greeting = buildTimelyGreetingMessage()
        conversationState.addAIMessage(text: greeting)
    }

    private func shouldShowTimelyPreThinkingGreeting() -> Bool {
        SharedUserStorage.retrieve(forKey: .hasShownFirstWelcome, as: Bool.self) ?? false
    }

    private func buildTimelyGreetingMessage() -> String {
        let firstName = MessageContext.fromUserStorage().firstName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let slot = ExploreRecommendationManager.TimeOfDay.current()
        let options = timelyGreetingOptions(for: slot, firstName: firstName)
        return options.randomElement() ?? "Hi."
    }

    private func timelyGreetingOptions(
        for slot: ExploreRecommendationManager.TimeOfDay,
        firstName: String?
    ) -> [String] {
        if let firstName, !firstName.isEmpty {
            switch slot {
            case .morning:
                return [
                    "Good morning, \(firstName).",
                    "Morning, \(firstName). Ready to begin your day?"
                ]
            case .noon:
                return [
                    "Good afternoon, \(firstName).",
                    "Hi \(firstName), how is your day?"
                ]
            case .evening:
                return [
                    "Good evening, \(firstName).",
                    "Hey \(firstName), hope you had a good day."
                ]
            case .night:
                return [
                    "Good evening, \(firstName).",
                    "Hey \(firstName), ready to close the day?"
                ]
            }
        }

        switch slot {
        case .morning:
            return [
                "Good morning.",
                "Morning. Ready to begin your day?"
            ]
        case .noon:
            return [
                "Good afternoon.",
                "Hi, how is your day?"
            ]
        case .evening:
            return [
                "Good evening.",
                "Hey, hope you had a good day."
            ]
        case .night:
            return [
                "Good evening.",
                "Hey, ready to close the day?"
            ]
        }
    }
    
    /// Displays a dual recommendation (primary + optional secondary) in the chat
    private func displayDualRecommendation(_ recommendation: DualRecommendation) {
        // Seed the orchestrator's exclusion set so the next recommendation avoids repeats.
        // This also covers the initial recommendation shown on app launch.
        var shownIds: [String] = [recommendation.primaryContentId]
        if let secondary = recommendation.secondary {
            shownIds.append(secondary.contentId)
        }
        DualRecommendationOrchestrator.shared.markAsRecentlyRecommended(shownIds)
        
        // Atomically swap the thinking animation out and the recommendation in.
        // removeThinkingMessageIfNeeded() is a no-op if no thinking message is present,
        // so this is safe to call even when displayDualRecommendation is triggered by
        // paths other than checkAndShowRecommendation (e.g. post-session).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.removeThinkingMessageIfNeeded()
            self.conversationState.addDualRecommendation(recommendation)
            
            // Track analytics
            AnalyticsManager.shared.logEvent("dual_recommendation_shown", parameters: [
                "phase": recommendation.currentPhase.analyticsName,
                "primary_type": recommendation.primary.type.analyticsType,
                "primary_id": recommendation.primaryContentId,
                "secondary_type": recommendation.secondary?.type.analyticsType ?? "none",
                "secondary_id": recommendation.secondaryContentId,
                "has_secondary": recommendation.hasBothOptions,
                "routine_progress": recommendation.routineProgress?.completed ?? 0
            ])
            
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Dual recommendation shown - phase=\(recommendation.currentPhase.displayName) primary=\(recommendation.primary.type.analyticsType) secondary=\(recommendation.secondary?.type.analyticsType ?? "none")")
        }
    }
    
    // MARK: - Legacy Recommendation Methods (kept for journey transitions)
    
    /// Fetches and displays a daily routine recommendation asynchronously
    /// Respects the once-per-time-slot-per-day rule
    /// NOTE: This is kept for backward compatibility with journey transitions
    private func showDailyRoutineRecommendationAsync() {
        // First check if we should auto-suggest for this slot
        guard ExploreRecommendationManager.shared.shouldAutoSuggestNow() else {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Daily routine: skipped (slot already suggested or conditions not met)")
            return
        }
        
        ProductJourneyManager.shared.getDailyRoutineRecommendationAsync { recommendation in
            guard let recommendation = recommendation else {
                logger.aiChat("🧠 AI_DEBUG [JOURNEY] no daily routine recommendation available (async)")
                return
            }
            
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] async got recommendation: \(recommendation.contentId)")
            
            // Mark this slot as suggested so we don't suggest again
            ExploreRecommendationManager.shared.markCurrentSlotAsSuggested()
            
            self.displayRecommendation(recommendation)
        }
    }
    
    /// Auto-generates a time-based custom meditation for the customization phase
    /// Follows same slot rules as daily routines - 1 per time slot per day
    /// NOTE: This is kept for backward compatibility with journey transitions
    private func showCustomizationAutoMeditation() {
        // Check if we should auto-generate for this slot
        guard ExploreRecommendationManager.shared.shouldAutoSuggestCustomNow() else {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Custom meditation: skipped (already suggested for this slot)")
            // Don't show anything - just leave chat empty or show existing conversation
            return
        }
        
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Custom meditation: generating time-based meditation")
        
        // Get the time-based prompt
        let prompt = ExploreRecommendationManager.shared.getTimeBasedCustomPrompt()
        
        // Mark slot as suggested immediately (before async generation)
        ExploreRecommendationManager.shared.markCurrentSlotAsSuggested()
        
        // Small delay for smooth UX, then trigger generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Generate meditation - this will show thinking indicator automatically
            // and handleGeneratedMeditation will be called when ready
            self.manager.generateMeditation(prompt: prompt, conversationHistory: [])
            
            // Set flag to add follow-up message after meditation is generated
            self.pendingCustomFollowUp = true
            
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Custom meditation generation started")
        }
    }
    
    /// Displays a journey recommendation in the chat
    private func displayRecommendation(_ recommendation: JourneyRecommendation) {
        // Add the recommendation with a small delay for smooth UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            switch recommendation {
            case .path(let step, let message, _):
                self.conversationState.addPathRecommendation(text: message, pathStep: step)
                
                // Track analytics (legacy event for backwards compatibility)
                AnalyticsManager.shared.logEvent("path_recommendation_shown_in_chat", parameters: [
                    "step_id": step.id,
                    "step_order": step.order,
                    "step_title": step.title,
                    "is_first_step": step.order == 1
                ])
                
                logger.aiChat("🧠 AI_DEBUG [JOURNEY] Path shown - step_id=\(step.id) step_order=\(step.order)")
                
            case .dailyRoutine(let session, let message, let timeOfDay):
                self.conversationState.addExploreRecommendation(text: message, audioFile: session)
                
                // Mark this slot as suggested (in case this came from transition, not initial check)
                ExploreRecommendationManager.shared.markCurrentSlotAsSuggested()
                
                // Track analytics (legacy event for backwards compatibility)
                AnalyticsManager.shared.logEvent("explore_recommendation_shown_in_chat", parameters: [
                    "session_id": session.id,
                    "session_title": session.title,
                    "time_of_day": timeOfDay,
                    "is_premium": session.premium
                ])
                
                logger.aiChat("🧠 AI_DEBUG [JOURNEY] Daily routine shown - session_id=\(session.id) time=\(timeOfDay) slot=\(ExploreRecommendationManager.shared.getCurrentSlotKey())")
                
            case .custom:
                // Future: Handle custom AI meditation recommendations
                logger.aiChat("🧠 AI_DEBUG [JOURNEY] Custom recommendation - not yet implemented")
                break
            }
        }
    }
    
    private func handleOnboardingCleared() {
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
        print("📊 JOURNEY: [DEV_SKIP] handleOnboardingCleared() received!")
        print("📊 JOURNEY: [DEV_SKIP] Slot state: \(ExploreRecommendationManager.shared.getLastSuggestedSlot() ?? "nil")")
        #endif
        
        logger.aiChat("🧠 AI_DEBUG onboarding_notice received=aiOnboardingCleared")
        SenseiOnboardingState.shared.resetForCurrentUser()
        resetDeferredRecommendationState()
        onboardingSteps = SenseiOnboardingScript.steps(firstName: SenseiOnboardingScript.currentFirstName())
        hasQueuedOnboarding = false
        activeActionMessageId = nil
        
        // Clear conversation to ensure fresh start
        conversationState.clearConversation()
        
        // Queue onboarding if needed
        let queued = queueOnboardingIfNeeded(force: true)
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] queueOnboardingIfNeeded(force: true) = \(queued)")
        #endif
        
        if queued {
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] Onboarding queued - suppressing keyboard")
            print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
            #endif
            keyboardController.suppressForOnboarding()
        } else {
            keyboardController.userRequestedExpand()
            
            // For in-app phases (path, dailyRoutines, customization), show phase-appropriate recommendation
            // This enables dev mode skip-to to immediately show the right content
            let currentPhase = ProductJourneyManager.shared.currentPhase
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] No onboarding queued. Phase: \(currentPhase.displayName), isInAppPhase: \(currentPhase.isInAppPhase)")
            #endif
            
            if currentPhase.isInAppPhase {
                logger.aiChat("🧠 AI_DEBUG [JOURNEY] onboarding cleared for in-app phase \(currentPhase.displayName) - showing recommendation")
                #if DEBUG
                print("📊 JOURNEY: [DEV_SKIP] Scheduling checkAndShowRecommendation() in 0.3s...")
                print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
                #endif
                // Small delay to let the conversation clear settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    #if DEBUG
                    print("📊 JOURNEY: [DEV_SKIP] 0.3s delay complete - calling checkAndShowRecommendation()")
                    #endif
                    self.checkAndShowRecommendation()
                }
            } else {
                #if DEBUG
                print("📊 JOURNEY: [DEV_SKIP] Not in-app phase - NOT showing recommendation")
                print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
                #endif
            }
        }
    }
    
    private func handleSubscriptionTrigger() {
        logger.aiChat("🧠 AI_DEBUG subscription_trigger received - navigating to subscription")
        
        // Remove any thinking message that might be showing
        removeThinkingMessageIfNeeded()
        
        // Track subscription source for contextual resume after subscription flow
        navigationCoordinator.subscriptionSource = .aiMeditationRequest
        
        // Navigate to subscription flow (no need to dismiss - Sensei is now a main view)
        navigationCoordinator.navigateTo(.subscription)
    }
    
    private func handlePathGuidanceRecommendation(_ notification: Notification) {
        logger.aiChat("🧠 AI_DEBUG PATH_GUIDANCE notification received")
        
        // Ensure conversation is loaded before modifying (notification can fire before onAppear)
        conversationState.loadIfNeeded()
        
        // Remove any thinking message that might be showing
        removeThinkingMessageIfNeeded()
        
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? String,
              let step = userInfo["step"] as? PathStep else {
            logger.aiChat("🧠 AI_DEBUG PATH_GUIDANCE invalid notification data")
            keyboardController.aiResponseComplete()
            return
        }
        
        // Add path recommendation with contextual message
        conversationState.addPathRecommendation(text: message, pathStep: step)
        
        // Release AI responding suppression
        keyboardController.aiResponseComplete()
        
        logger.aiChat("🧠 AI_DEBUG PATH_GUIDANCE shown step=\(step.id) title=\(step.title)")
    }
    
    private func handleExploreGuidanceRecommendation(_ notification: Notification) {
        logger.aiChat("🧠 AI_DEBUG [EXPLORE] notification received")
        
        // Ensure conversation is loaded before modifying (notification can fire before onAppear)
        conversationState.loadIfNeeded()
        
        // Remove any thinking message that might be showing
        removeThinkingMessageIfNeeded()
        
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? String,
              let session = userInfo["session"] as? AudioFile else {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE] invalid notification data")
            keyboardController.aiResponseComplete()
            return
        }
        
        // Add explore recommendation with contextual message
        conversationState.addExploreRecommendation(text: message, audioFile: session)
        
        // Release AI responding suppression
        keyboardController.aiResponseComplete()
        
        logger.aiChat("🧠 AI_DEBUG [EXPLORE] shown session=\(session.id) title=\(session.title)")
    }
    
    /// Handle journey phase change notification (especially customization unlock)
    private func handleJourneyPhaseChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let newPhase = userInfo["newPhase"] as? JourneyPhase else {
            return
        }
        
        let isUnlock = userInfo["isUnlock"] as? Bool ?? false
        
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Phase changed notification: \(newPhase.displayName) isUnlock=\(isUnlock)")
        
        // Show celebration message when customization is unlocked
        if isUnlock && newPhase == .customization {
            showCustomizationUnlockCelebration()
        }
    }
    
    /// Called when PathProgressManager.isLoaded changes
    /// Re-checks recommendations when path steps become available (fixes race condition)
    private func handlePathStepsLoaded(wasLoaded: Bool, isLoaded: Bool) {
        // Only act when transitioning from not loaded to loaded
        guard !wasLoaded && isLoaded else { return }
        
        #if DEBUG
        print("📊 JOURNEY: [PATH_STEPS_READY] AI chat received path steps ready signal")
        print("📊 JOURNEY: [PATH_STEPS_READY] Re-checking recommendations...")
        #endif
        
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Path steps loaded - re-checking recommendations")
        
        // Re-check recommendations now that path steps are available
        checkAndShowRecommendation()
    }
    
    /// Called when the app returns to the foreground.
    /// Checks if the time slot changed while the app was backgrounded
    /// and appends a new recommendation if so.
    private func handleReturnFromBackground() {
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] App returned to foreground - checking for new time slot recommendation")
        checkAndShowRecommendation()
    }
    
    /// Shows a celebration message when user unlocks the customization phase
    /// Then auto-generates the first custom meditation
    private func showCustomizationUnlockCelebration() {
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] 🎉 Showing customization unlock celebration!")
        
        // Small delay to let any post-practice messages settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let celebrationMessage = "🎉 You've built a solid daily practice! From now on, I can create fully personalized meditations just for you."
            
            self.conversationState.addAIMessage(text: celebrationMessage)
            
            // Track analytics
            AnalyticsManager.shared.logEvent("customization_phase_unlocked_celebration", parameters: [
                "routines_completed": ProductJourneyManager.shared.getRoutineCompletionCount()
            ])
            
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] ✅ Customization unlock celebration shown")
            
            // After celebration, auto-generate the first custom meditation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.generateFirstCustomMeditation()
            }
        }
    }
    
    /// Generates the first custom meditation right after unlocking customization
    private func generateFirstCustomMeditation() {
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Generating first custom meditation after unlock")
        
        // Get the time-based prompt
        let prompt = ExploreRecommendationManager.shared.getTimeBasedCustomPrompt()
        
        // Mark slot as suggested
        ExploreRecommendationManager.shared.markCurrentSlotAsSuggested()
        
        // Generate meditation
        self.manager.generateMeditation(prompt: prompt, conversationHistory: [])
        
        // Set flag to add follow-up message
        self.pendingCustomFollowUp = true
        
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] First custom meditation generation started")
    }
    
    /// Handle journey transition display (dev mode) - shows the full transition experience
    private func handleJourneyShowTransition(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let fromPhase = userInfo["fromPhase"] as? JourneyPhase,
              let toPhase = userInfo["toPhase"] as? JourneyPhase else {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Invalid transition notification data")
            return
        }
        
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] 🔄 Showing transition: \(fromPhase.displayName) → \(toPhase.displayName)")
        
        // Clear current conversation for fresh transition display
        conversationState.clearConversation()
        
        switch (fromPhase, toPhase) {
        case (.path, .dailyRoutines):
            showPathToDailyRoutinesTransition()
            
        case (.dailyRoutines, .customization):
            showDailyRoutinesToCustomizationTransition()
            
        default:
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] No transition defined for \(fromPhase.displayName) → \(toPhase.displayName)")
        }
    }
    
    /// Shows the Path → Daily Routines transition (simulates completing last path step)
    private func showPathToDailyRoutinesTransition() {
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Displaying Path → Daily Routines transition")
        
        // Step 1: Show the path completion message (from AIPathPostSessionManager)
        let pathCompletionMessage = """
        🎉 Congratulations! You've completed the entire Path!
        
        Your meditation foundation is now solid. You've learned the fundamentals and built a strong practice.
        """
        
        conversationState.addAIMessage(text: pathCompletionMessage)
        
        // Step 2: After a delay, show the daily routines transition and first suggestion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let transitionMessage = "From now on, I'll suggest daily routines based on the time of day."
            self.conversationState.addAIMessage(text: transitionMessage)
            
            // Step 3: After another delay, show dual recommendation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Task {
                    guard let dualRec = await DualRecommendationOrchestrator.shared.getDualRecommendation() else {
                        logger.aiChat("🧠 AI_DEBUG [JOURNEY] ❌ No dual recommendation available for Path → Daily Routines transition")
                        return
                    }
                    await MainActor.run {
                        self.lastRecommendationTrigger = .transition
                        self.displayDualRecommendation(dualRec)
                        logger.aiChat("🧠 AI_DEBUG [JOURNEY] ✅ Dual recommendation shown for Path → Daily Routines transition")
                    }
                }
            }
        }
    }
    
    /// Shows the Daily Routines → Customization transition (simulates unlocking customization)
    private func showDailyRoutinesToCustomizationTransition() {
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Displaying Daily Routines → Customization transition")
        
        // Step 1: Show the context of completing a routine
        let routineCompletionMessage = "Great session! You've been building a consistent daily practice."
        conversationState.addAIMessage(text: routineCompletionMessage)
        
        // Step 2: After a delay, show the unlock celebration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let celebrationMessage = """
            🎉 You've built a solid daily practice!
            
            From now on, I can create fully personalized meditations tailored to your needs, mood, and preferences. Just tell me what you're looking for.
            """
            self.conversationState.addAIMessage(text: celebrationMessage)
            
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] ✅ Customization unlock transition complete")
        }
    }

    private func handleGeneratedMeditation(_ newMeditation: AITimerResponse?) {
        if let meditation = newMeditation {
            logger.aiChat("🧠 AI_DEBUG [MEDITATION]: handleGeneratedMeditation started")
            // Remove temporary thinking message if present
            removeThinkingMessageIfNeeded()
            // Pass the acknowledgment text to display above the card
            let acknowledgment = manager.generatedMeditationAcknowledgment ?? ""
            logger.aiChat("🧠 AI_DEBUG [MEDITATION]: Adding meditation message with acknowledgment len=\(acknowledgment.count)")
            conversationState.addAIMessage(meditation: meditation, acknowledgment: acknowledgment)
            logger.aiChat("🧠 AI_DEBUG [MEDITATION]: Meditation message added, conversation count=\(conversationState.conversation.count)")
            // Clear the acknowledgment after use
            manager.generatedMeditationAcknowledgment = nil
            startButtonAnimation()
            // Keyboard stays suppressed (aiResponding) - will be released when typing completes
            
            // Add follow-up message for auto-generated custom meditations
            if pendingCustomFollowUp {
                pendingCustomFollowUp = false
                // Small delay so the meditation card appears first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.conversationState.addAIMessage(text: "Just ask if you want something different.")
                    logger.aiChat("🧠 AI_DEBUG [JOURNEY] Custom meditation follow-up added")
                }
            }
        }
    }
    
    private func handleConversationalResponse(_ newResponse: String?) {
        if let response = newResponse {
            // Remove temporary thinking message if present
            removeThinkingMessageIfNeeded()
            conversationState.addAIMessage(text: response)
            // Enable CTA handling for the next user reply
            manager.awaitingMeditationConfirmation = true
            manager.conversationalResponse = nil
            // Keyboard stays suppressed (aiResponding) - will be released when typing completes
        }
    }
    
    private func handleError(_ error: String?) {
        guard let errorMessage = error else { return }
        
        // Remove temporary thinking message if present
        removeThinkingMessageIfNeeded()
        
        // Convert error to a friendly Sensei message
        let senseiMessage: String
        if errorMessage.lowercased().contains("internet") || errorMessage.lowercased().contains("network") || errorMessage.lowercased().contains("connection") {
            senseiMessage = "I'm currently offline and need an internet connection to help you. Please reconnect and try again."
        } else {
            senseiMessage = "I ran into a small hiccup. Please try again in a moment."
        }
        
        conversationState.addAIMessage(text: senseiMessage)
        
        // Clear the error so it doesn't trigger again
        manager.error = nil
        
        // Release AI responding suppression since we're done
        keyboardController.aiResponseComplete()
        
        logger.aiChat("🧠 AI_DEBUG ERROR_HANDLED original=\(errorMessage) senseiMessage=\(senseiMessage)")
    }
    
    private func handleLatestAIMessageIdChange(_ newMessageId: UUID?) {
        // When latestAIMessageId becomes nil, it means typing completed for the previous message
        if newMessageId == nil {
            // AI finished typing - release AI responding suppression
            keyboardController.aiResponseComplete()
            
            // Trigger pending post-session prompt after post-practice typing completes
            #if DEBUG
            print("[PostSessionPrompt] Typing complete (latestAIMessageId=nil) - pendingPrompt=\(pendingPostSessionPrompt)")
            #endif
            if pendingPostSessionPrompt {
                pendingPostSessionPrompt = false
                #if DEBUG
                print("[PostSessionPrompt] Triggering showPostSessionPrompt(isPathComplete=\(pendingPostSessionPromptIsPathComplete))")
                #endif
                showPostSessionPrompt(isPathComplete: pendingPostSessionPromptIsPathComplete)
            }
        }
        
        // Check if we're waiting for an onboarding step to appear
        if newMessageId == nil, let messageId = pendingOnboardingMessageId {
            // Verify the message we were waiting for exists and typing is complete
            if conversationState.isTypingComplete && conversationState.conversation.contains(where: { $0.id == messageId }) {
                if let nextIndex = pendingOnboardingStepIndex {
                    // There's a next step - schedule it
                    let stepIndex = nextIndex
                    pendingOnboardingStepIndex = nil
                    pendingOnboardingMessageId = nil
                    // Show next step with smooth transition delay
                    scheduleOnboardingStep(startingAt: stepIndex, delay: AnimationConstants.onboardingMessageDelay)
                } else {
                    // No next step - this was the last step, complete onboarding
                    pendingOnboardingMessageId = nil
                    let totalSteps = onboardingSteps.count
                    completeOnboardingIfNeeded(totalSteps: totalSteps)
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    @discardableResult
    private func queueOnboardingIfNeeded(force: Bool) -> Bool {
        if !force && hasQueuedOnboarding { 
            return true 
        }
        if !force && !conversationState.conversation.isEmpty { 
            return false 
        }

        let firstName = SenseiOnboardingScript.currentFirstName()
        let steps = SenseiOnboardingScript.steps(firstName: firstName)
        onboardingSteps = steps
        
        // Record firstName for personalized meditation generation
        OnboardingResponseCollector.shared.recordFirstName(firstName)

        let totalSteps = steps.count
        guard totalSteps > 0 else { return false }
        guard SenseiOnboardingState.shared.hasPendingSteps(totalSteps: totalSteps) else { return false }

        logger.aiChat("🧠 AI_DEBUG queueOnboardingIfNeeded queuing onboarding totalSteps=\(totalSteps)")
        hasQueuedOnboarding = true
        activeActionMessageId = nil

        SenseiOnboardingState.shared.markFlowPresented(origin: "ai_chat", totalSteps: totalSteps)

        let startIndex = SenseiOnboardingState.shared.currentStepIndex(totalSteps: totalSteps)
        SenseiOnboardingState.shared.setCurrentStepIndex(startIndex, totalSteps: totalSteps)
        scheduleOnboardingStep(startingAt: startIndex, delay: AnimationConstants.onboardingInitialDelay)
        return true
    }

    private func scheduleOnboardingStep(startingAt index: Int, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
            self.presentOnboardingSteps(startingAt: index)
        }
    }

    private func presentOnboardingSteps(startingAt startIndex: Int) {
        let total = onboardingSteps.count
        guard total > 0 else { return }
        guard startIndex < total else {
            completeOnboardingIfNeeded(totalSteps: total)
            return
        }

        let step = onboardingSteps[startIndex]
        SenseiOnboardingState.shared.setCurrentStepIndex(startIndex, totalSteps: total)
        SenseiOnboardingState.shared.markStepViewed(step: step, index: startIndex, totalSteps: total)

        if let message = step as? SenseiOnboardingMessage {
            let messageId = conversationState.addSenseiMessage(message)
            
            // If message has CTA, wait for typing completion then show CTA for user interaction
            if message.cta != nil {
                activeActionMessageId = messageId
                // Keyboard stays suppressed for onboarding
                return
            }
            
            // No CTA - wait for typing animation to complete before auto-advancing
            let nextIndex = SenseiOnboardingState.shared.advance(by: 1, totalSteps: total)
            if nextIndex < total {
                // Store pending step info - will be triggered when typing completes
                pendingOnboardingStepIndex = nextIndex
                pendingOnboardingMessageId = messageId
            } else {
                // Last step - complete onboarding after typing finishes
                pendingOnboardingStepIndex = nil
                pendingOnboardingMessageId = messageId
            }
            return
        }

        if let question = step as? SenseiOnboardingQuestion {
            let messageId = conversationState.addSenseiQuestion(question)
            activeActionMessageId = messageId
            // Keyboard stays suppressed for onboarding
            return
        }
        
        if let promptEducation = step as? SenseiOnboardingPromptEducation {
            let messageId = conversationState.addSenseiPromptEducation(promptEducation)
            activeActionMessageId = messageId
            // Keyboard stays suppressed for onboarding
            return
        }

        let nextIndex = SenseiOnboardingState.shared.advance(by: 1, totalSteps: total)
        scheduleOnboardingStep(startingAt: nextIndex, delay: AnimationConstants.onboardingExtendedDelay)
    }


    private func typingDelay(for text: String) -> TimeInterval {
        let trimmed = text.replacingOccurrences(of: "\n", with: " ")
        let characterCount = max(20, trimmed.count)
        let delay = Double(characterCount) * 0.035
        return min(max(delay, 1.0), 3.0)
    }
    
    private func sendMessage() {
        let trimmedInput = conversationState.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty && !manager.isLoading else { return }
        
        // Collapse keyboard and suppress until AI responds
        keyboardController.userSubmittedMessage()
        
        // Check for internet connectivity before sending
        guard NetworkMonitor.shared.isConnected else {
            // Add user message first
            conversationState.addUserMessage(trimmedInput)
            conversationState.clearInput()
            
            // Add Sensei's offline response
            let offlineMessage = "I'm currently offline and need an internet connection to help you. Please reconnect and try again."
            conversationState.addAIMessage(text: offlineMessage)
            
            // Release suppression since we're not actually calling AI
            keyboardController.aiResponseComplete()
            
            logger.aiChat("🧠 AI_DEBUG OFFLINE user tried to send message while offline")
            return
        }
        
        // Add user message (shows only what user typed)
        conversationState.addUserMessage(trimmedInput)
        
        // Get conversation context for API
        let context = conversationState.getConversationContext()
        
        // Clear input
        conversationState.clearInput()
        
        // Build API prompt - include profile context if first meditation after onboarding
        let apiPrompt: String
        let maxDuration = UserProfileManager.shared.recommendedDuration
        
        if UserProfileManager.shared.profile.isFirstMeditationPending {
            apiPrompt = UserProfileManager.shared.buildFirstMeditationPrompt(userPrompt: trimmedInput)
            
            // Log unified onboarding meditation request event
            let profile = UserProfileManager.shared.profile
            AnalyticsManager.shared.logEvent("ai_onboarding_meditation_requested", parameters: [
                "user_prompt": trimmedInput,
                "goals": profile.goals.map { $0.rawValue }.joined(separator: ", "),
                "current_state": profile.currentState.map { $0.rawValue }.joined(separator: ", "),
                "experience_level": profile.experienceLevel.rawValue,
                "guidance_style": profile.guidanceStyle?.rawValue ?? "",
                "steps_completed": SenseiOnboardingState.shared.stepsCompletedBeforeExit,
                "skipped_early": SenseiOnboardingState.shared.didSkipEarly,
                "total_steps": 6
            ])
            
            // Mark first meditation as generated (profile is retained for future use)
            UserProfileManager.shared.markFirstMeditationGenerated()
        } else {
            apiPrompt = trimmedInput
        }
        
        // Generate AI response with conversation context and optional duration constraint
        manager.generateMeditation(prompt: apiPrompt, conversationHistory: context, maxDuration: maxDuration)
    }

    private func handleSenseiMessageCTA(_ message: SenseiOnboardingMessage, _ cta: SenseiOnboardingCTA, skip: Bool) {
        let total = onboardingSteps.count
        guard total > 0 else { return }

        // Find the AI message ID that contains this CTA and scroll to it
        if let aiMessageId = conversationState.conversation.first(where: { 
            $0.senseiMessage?.id == message.id 
        })?.id {
            conversationState.latestUserMessageId = aiMessageId
        }

        let messageIndex = onboardingSteps.enumerated().first { element in
            if let candidate = element.element as? SenseiOnboardingMessage {
                return candidate.id == message.id
            }
            return false
        }?.offset ?? SenseiOnboardingState.shared.currentStepIndex(totalSteps: total)

        SenseiOnboardingState.shared.setCurrentStepIndex(messageIndex, totalSteps: total)
        SenseiOnboardingState.shared.markStepAction(step: message, actionId: skip ? cta.analyticsSkipId : cta.analyticsActionId, index: messageIndex, totalSteps: total, isSkip: skip)

        activeActionMessageId = nil
        
        // Determine and execute the action
        let action = skip ? (cta.skipAction ?? cta.primaryAction) : cta.primaryAction
        executeOnboardingAction(action, totalSteps: total, source: skip ? "cta_skip" : "cta_continue")
    }
    
    private func handleSenseiQuestion(_ question: SenseiOnboardingQuestion, selectedOption: String?, skip: Bool) {
        let total = onboardingSteps.count
        guard total > 0 else { return }

        // Record the response to user profile for personalized meditation generation
        if !skip, let option = selectedOption {
            let selections = option.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            switch question.id {
            case "new_goal_question":
                UserProfileManager.shared.updateGoals(selections)
            case "new_baseline_question":
                UserProfileManager.shared.updateCurrentState(selections)
            case "new_experience_question":
                UserProfileManager.shared.updateExperience(selections)
            case "new_guidance_question":
                UserProfileManager.shared.updateGuidanceStyle(option)
            default:
                break
            }
        }

        // Find the AI message ID that contains this question and scroll to it
        if let aiMessageId = conversationState.conversation.first(where: { 
            $0.senseiQuestion?.id == question.id 
        })?.id {
            conversationState.latestUserMessageId = aiMessageId
        }

        let questionIndex = onboardingSteps.enumerated().first { element in
            if let candidate = element.element as? SenseiOnboardingQuestion {
                return candidate.id == question.id
            }
            return false
        }?.offset ?? SenseiOnboardingState.shared.currentStepIndex(totalSteps: total)

        SenseiOnboardingState.shared.setCurrentStepIndex(questionIndex, totalSteps: total)
        SenseiOnboardingState.shared.markStepAction(step: question, actionId: skip ? question.analyticsSkipId : question.analyticsActionId, index: questionIndex, totalSteps: total, isSkip: skip, selectedOptions: selectedOption)

        activeActionMessageId = nil
        
        // Determine and execute the action
        let action = skip ? (question.skipAction ?? question.primaryAction) : question.primaryAction
        executeOnboardingAction(action, totalSteps: total, source: skip ? "question_skip" : "question_continue")
    }
    
    private func handleSenseiPromptEducation(_ promptEducation: SenseiOnboardingPromptEducation, _ action: PromptEducationAction) {
        let total = onboardingSteps.count
        guard total > 0 else { return }
        
        // Find the step index for this prompt education step
        let stepIndex = onboardingSteps.enumerated().first { element in
            if let candidate = element.element as? SenseiOnboardingPromptEducation {
                return candidate.id == promptEducation.id
            }
            return false
        }?.offset ?? SenseiOnboardingState.shared.currentStepIndex(totalSteps: total)
        
        SenseiOnboardingState.shared.setCurrentStepIndex(stepIndex, totalSteps: total)
        activeActionMessageId = nil
        
        switch action {
        case .promptSelected(let prompt):
            // Log step action using standard onboarding analytics pattern
            SenseiOnboardingState.shared.markStepAction(
                step: promptEducation,
                actionId: "prompt_selected",
                index: stepIndex,
                totalSteps: total,
                isSkip: false,
                selectedOptions: prompt
            )
            
            // Mark onboarding complete on both state managers
            SenseiOnboardingState.shared.stepsCompletedBeforeExit = stepIndex + 1
            SenseiOnboardingState.shared.didSkipEarly = SenseiOnboardingState.shared.arrivedAtFinalViaSkip
            SenseiOnboardingState.shared.markCompleted(source: "prompt_education_chip_selected", requestId: nil, userPrompt: prompt)
            hasQueuedOnboarding = false
            
            // Mark user profile onboarding complete
            UserProfileManager.shared.markOnboardingComplete(stepsCompleted: stepIndex + 1, totalSteps: total)
            
            logger.aiChat("🧠 AI_DEBUG handleSenseiPromptEducation prompt_selected=\(prompt) skipped=\(SenseiOnboardingState.shared.didSkipEarly)")
            
            // Release onboarding suppression and expand keyboard
            keyboardController.releaseOnboardingSuppression(expandKeyboard: true)
            
            // Animate text into input field character by character
            conversationState.typeIntoInput(prompt)
            
        case .typeMyOwn:
            // Clear any existing input first (cancels any typing animation)
            conversationState.clearInputAnimated()
            
            // Log step action using standard onboarding analytics pattern
            SenseiOnboardingState.shared.markStepAction(
                step: promptEducation,
                actionId: "type_my_own",
                index: stepIndex,
                totalSteps: total,
                isSkip: false
            )
            
            // Mark onboarding complete on both state managers
            SenseiOnboardingState.shared.stepsCompletedBeforeExit = stepIndex + 1
            SenseiOnboardingState.shared.didSkipEarly = SenseiOnboardingState.shared.arrivedAtFinalViaSkip
            SenseiOnboardingState.shared.markCompleted(source: "prompt_education_type_my_own", requestId: nil, userPrompt: nil)
            hasQueuedOnboarding = false
            
            // Mark user profile onboarding complete
            UserProfileManager.shared.markOnboardingComplete(stepsCompleted: stepIndex + 1, totalSteps: total)
            
            logger.aiChat("🧠 AI_DEBUG handleSenseiPromptEducation type_my_own skipped=\(SenseiOnboardingState.shared.didSkipEarly)")
            
            // Release onboarding suppression and expand keyboard
            keyboardController.releaseOnboardingSuppression(expandKeyboard: true)
        }
    }
    
    // MARK: - Centralized Action Executor
    
    private func executeOnboardingAction(_ action: OnboardingAction, totalSteps: Int, source: String) {
        switch action {
        case .advance(let by):
            let nextIndex = SenseiOnboardingState.shared.advance(by: by, totalSteps: totalSteps)
            if nextIndex >= totalSteps {
                completeOnboardingIfNeeded(totalSteps: totalSteps, source: source)
            } else {
                // Mark as NOT skipped if advancing to final step normally
                if nextIndex == totalSteps - 1 {
                    SenseiOnboardingState.shared.arrivedAtFinalViaSkip = false
                }
                scheduleOnboardingStep(startingAt: nextIndex, delay: AnimationConstants.onboardingTransitionDelay)
            }
            
        case .jumpToStep(let stepId):
            if let targetIndex = onboardingSteps.firstIndex(where: { $0.id == stepId }) {
                // Mark as skipped if jumping to the final step
                let isFinalStep = targetIndex == totalSteps - 1
                if isFinalStep {
                    SenseiOnboardingState.shared.arrivedAtFinalViaSkip = true
                }
                SenseiOnboardingState.shared.setCurrentStepIndex(targetIndex, totalSteps: totalSteps)
                scheduleOnboardingStep(startingAt: targetIndex, delay: AnimationConstants.onboardingTransitionDelay)
            } else {
                logger.aiChat("🧠 AI_DEBUG executeOnboardingAction jumpToStep failed - stepId not found: \(stepId)")
            }
            
        case .completeAndGenerate:
            completeOnboardingAndGenerateMeditation(totalSteps: totalSteps, source: source)
        }
    }

    private func completeOnboardingIfNeeded(totalSteps: Int, source: String = "script") {
        guard totalSteps > 0 else { return }
        let current = SenseiOnboardingState.shared.currentStepIndex(totalSteps: totalSteps)
        guard current >= totalSteps else { return }
        if !SenseiOnboardingState.shared.isComplete {
            // Track steps completed (full flow, no skip)
            SenseiOnboardingState.shared.stepsCompletedBeforeExit = totalSteps
            SenseiOnboardingState.shared.didSkipEarly = false
            
            SenseiOnboardingState.shared.markCompleted(source: source, requestId: nil, userPrompt: nil)
            hasQueuedOnboarding = false
            
            // Release onboarding suppression - keyboard stays collapsed unless user taps
            keyboardController.releaseOnboardingSuppression(expandKeyboard: false)
        }
    }
    
    private func completeOnboardingAndGenerateMeditation(totalSteps: Int, source: String) {
        // Track steps completed and skip status before marking complete
        let currentStep = SenseiOnboardingState.shared.currentStepIndex(totalSteps: totalSteps)
        SenseiOnboardingState.shared.stepsCompletedBeforeExit = currentStep + 1 // +1 because index is 0-based
        SenseiOnboardingState.shared.didSkipEarly = source.contains("skip")
        
        // Mark onboarding as complete
        SenseiOnboardingState.shared.markCompleted(source: source, requestId: nil, userPrompt: nil)
        hasQueuedOnboarding = false
        
        // Release onboarding suppression but suppress for AI responding
        keyboardController.releaseOnboardingSuppression(expandKeyboard: false)
        keyboardController.userSubmittedMessage() // Suppress for AI response
        
        // Build personalized prompt from collected responses
        let prompt = OnboardingResponseCollector.shared.buildPrompt()
        
        // Log unified onboarding meditation request event (skip path)
        let responses = OnboardingResponseCollector.shared.responses
        let stepsCompleted = SenseiOnboardingState.shared.stepsCompletedBeforeExit
        let skippedEarly = SenseiOnboardingState.shared.didSkipEarly
        AnalyticsManager.shared.logEvent("ai_onboarding_meditation_requested", parameters: [
            "user_prompt": prompt,
            "goals": responses.goals.joined(separator: ", "),
            "current_state": responses.currentFeeling.joined(separator: ", "),
            "experience_level": responses.experience.joined(separator: ", "),
            "guidance_style": responses.guidanceStyle ?? "",
            "steps_completed": stepsCompleted,
            "skipped_early": skippedEarly,
            "total_steps": totalSteps
        ])
        
        logger.aiChat("🧠 AI_DEBUG ONBOARDING_COMPLETE generating meditation prompt=\(prompt)")
        
        // Get conversation context and generate meditation
        // The loading state will automatically show thinking animation via placeholder message
        // The flag hasCreatedFirstAIMeditation will be set by AIRequestManager upon successful generation
        let context = conversationState.getConversationContext()
        manager.generateMeditation(prompt: prompt, conversationHistory: context)
        
        // Reset collector after generating
        OnboardingResponseCollector.shared.reset()
    }
    
    private func startMeditation(_ meditation: AITimerResponse) {
        manager.startMeditation(with: meditation, navigationCoordinator: navigationCoordinator)
        // Navigation is handled by the AI manager's deep link system
    }
    
    private func playMeditationDirectly(_ meditation: AITimerResponse) {
        // Haptic feedback is handled by the card tap, not here

        // Subscription gate (post-first-session, not subscribed)
        if SubscriptionManager.shared.shouldGatePlay {
            SubscriptionManager.shared.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=AIChatContainerView_playMeditationDirectly")
            #endif
            navigationCoordinator.subscriptionSource = .aiFirstMeditationPlay
            navigationCoordinator.pendingAIMeditation = meditation
            navigationCoordinator.navigateTo(.subscription)
            return
        }

        // Extract configuration from AI response
        let config = meditation.meditationConfiguration

        // Resolve binaural beat from deep link (robust to target membership) and navigate immediately
        // Asset download now happens on the Player screen for unified loading experience
        Task { @MainActor in
            // 1) Make sure BB catalog is loaded before mapping
            // Skip network fetch if already have cached beats OR if offline (use cached data)
            if CatalogsManager.shared.beats.isEmpty && NetworkMonitor.shared.isConnected {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    CatalogsManager.shared.fetchCatalogs(triggerContext: "AIChatContainerView|play meditation resolve") { _ in
                        continuation.resume()
                    }
                }
            }

            // 2) Resolve bb from deep link first; fallback to reflection; else None
            var resolvedBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
            var bbIdFromLink = "None"
            if let components = URLComponents(url: meditation.deepLink, resolvingAgainstBaseURL: false),
               let qItems = components.queryItems,
               let v = qItems.first(where: { $0.name == "bb" })?.value {
                bbIdFromLink = v
                if let beat = CatalogsManager.shared.beats.first(where: { $0.id == bbIdFromLink }) {
                    resolvedBeat = beat
                }
            }
            // Reflection fallback if link did not yield a catalog match
            if resolvedBeat.id == "None" {
                if let beat = (Mirror(reflecting: config).children.first { $0.label == "binauralBeat" }?.value as? BinauralBeat), beat.id != "None" {
                    resolvedBeat = beat
                }
            }
            logger.aiChat("🧠 AI_DEBUG [BB]: direct_play resolve link_bb=\(bbIdFromLink) final=\(resolvedBeat.id) name=\(resolvedBeat.name)")

            // 3) Navigate to countdown immediately - assets will be prepared on Player screen
            // Set up SessionContextManager for the custom meditation session
            let timerConfig = TimerSessionConfig(
                minutes: config.duration,
                backgroundSound: config.backgroundSound,
                binauralBeat: resolvedBeat,
                cueSettings: config.cueSettings,
                title: config.title,
                description: meditation.description
            )
            SessionContextManager.shared.setupCustomMeditationSession(
                entryPoint: .aiChat,
                timerConfig: timerConfig,
                origin: .aiRecommended,
                customizationLevel: .suggested
            )
            
            // Log ai_onboarding_meditation_started if user came from AI onboarding
            if SenseiOnboardingState.shared.isComplete {
                AnalyticsManager.shared.logEvent("ai_onboarding_meditation_started", parameters: [
                    "steps_completed": SenseiOnboardingState.shared.stepsCompletedBeforeExit,
                    "skipped_early": SenseiOnboardingState.shared.didSkipEarly
                ])
            }
            
            navigationCoordinator.navigateToTimerCountdown(
                totalMinutes: config.duration,
                backgroundSound: config.backgroundSound,
                cueSettings: config.cueSettings,
                binauralBeat: resolvedBeat,
                isDeepLinked: false,
                title: config.title,
                description: meditation.description
            )
        }

        // Unified analytics for direct play start, include original request inline when available
        var params: [String: Any] = [
            "stage": "start",
            "start_method": "direct_play",
            // Ensure JSON-safe string for meditation_id
            "meditation_id": String(describing: config.id),
            "duration_min": config.duration,
            "background_sound": config.backgroundSound.name,
            "cue_count": config.cueSettings.count,
            "title": config.title ?? "Unknown"
        ]
        if let ctx = manager.lastRequestContext {
            params["request_id"] = ctx.request_id
            params["user_prompt"] = ctx.user_prompt
            params["prompt_length"] = ctx.prompt_length
            params["request_type"] = ctx.request_type
            params["history_len"] = ctx.history_len
        }
        AnalyticsManager.shared.logEvent("ai_interaction", parameters: params)
        
        // Navigation is handled by navigateToTimerCountdown above
    }
    
    private func startButtonAnimation() {
        // Clear any existing visible buttons
        conversationState.resetButtonVisibility()
        
        let buttons = ["play", "customize"]
        
        // Buttons appear sequentially - slowed by 30% for smoother appearance
        for (index, buttonId) in buttons.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * AnimationConstants.sequentialButtonDelay) {
                withAnimation(AnimationConstants.buttonAppearanceAnimation) {
                    conversationState.showButton(buttonId)
                }
                
                // Add haptic feedback for each button appearance
                HapticManager.shared.impact(.soft)
            }
        }
    }
    
    // MARK: - Path Step Play Handler
    
    private func playPathStep(_ pathStep: PathStep) {
        // Haptic feedback is handled by the card tap, not here
        
        // Convert PathStep to AudioFile
        let audioFile = pathStep.toAudioFile()
        
        // Check subscription gate (post-first-session, not subscribed)
        if SubscriptionManager.shared.shouldGatePlay {
            SubscriptionManager.shared.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=AIChatContainerView_playPathStep")
            #endif
            navigationCoordinator.subscriptionSource = .pathStep
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        
        // Set up SessionContextManager for path session from AI chat
        SessionContextManager.shared.setupPathSession(
            entryPoint: .aiChat,
            pathStep: pathStep,
            origin: .aiRecommended
        )
        
        // Track analytics
        AnalyticsManager.shared.logEvent("path_step_tapped_from_ai_chat", parameters: [
            "step_id": pathStep.id,
            "step_title": pathStep.title,
            "step_order": pathStep.order,
            "is_premium": pathStep.premium,
            "is_lesson": pathStep.isLesson
        ])
        
        // Fade out background music over 2 seconds
        GeneralBackgroundMusicController.shared.fadeOutMusic(duration: 2.0)
        
        // Store current date as last session date
        SharedUserStorage.save(value: Date(), forKey: .lastMeditationDate)
        
        // Navigate to player
        navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
        
        logger.aiChat("🧠 AI_DEBUG PLAY_PATH_STEP step_id=\(pathStep.id) step_title=\(pathStep.title)")
    }
    
    // MARK: - Explore Session Play Handler
    
    private func playExploreSession(_ audioFile: AudioFile) {
        // Haptic feedback is handled by the card tap, not here
        logger.aiChat("🧠 AI_DEBUG [EXPLORE_PLAY] session=\(audioFile.id) title=\(audioFile.title)")
        
        // Check subscription gate (post-first-session, not subscribed)
        if SubscriptionManager.shared.shouldGatePlay {
            SubscriptionManager.shared.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=AIChatContainerView_playExploreSession")
            #endif
            navigationCoordinator.subscriptionSource = .explore
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        
        // Set up SessionContextManager for explore session from AI chat
        SessionContextManager.shared.setupLibrarySession(
            entryPoint: .aiChat,
            audioFile: audioFile,
            origin: .aiRecommended
        )
        
        // Track analytics
        AnalyticsManager.shared.logEvent("explore_session_tapped_from_ai_chat", parameters: [
            "session_id": audioFile.id,
            "session_title": audioFile.title,
            "is_premium": audioFile.premium,
            "category": audioFile.category.rawValue
        ])
        
        // Fade out background music
        GeneralBackgroundMusicController.shared.fadeOutMusic(duration: 2.0)
        
        // Store last session date
        SharedUserStorage.save(value: Date(), forKey: .lastMeditationDate)
        
        // Navigate to player
        navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
        
        logger.aiChat("🧠 AI_DEBUG [EXPLORE_PLAY] navigation complete for session=\(audioFile.id)")
    }
    
    // MARK: - Dual Recommendation Play Handlers (with position tracking)
    
    /// Play a path step from a dual recommendation, tracking primary/secondary position
    private func playDualPathStep(_ pathStep: PathStep, position: RecommendationPosition) {
        // Haptic feedback is handled by the card tap, not here
        
        // Convert PathStep to AudioFile
        let audioFile = pathStep.toAudioFile()
        
        // Check subscription gate (post-first-session, not subscribed)
        if SubscriptionManager.shared.shouldGatePlay {
            SubscriptionManager.shared.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=AIChatContainerView_playDualPathStep")
            #endif
            navigationCoordinator.subscriptionSource = .pathStep
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        
        // Set up SessionContextManager with recommendation position and trigger
        SessionContextManager.shared.setupPathSession(
            entryPoint: .aiChat,
            pathStep: pathStep,
            origin: .aiRecommended,
            recommendationPosition: position,
            recommendationTrigger: lastRecommendationTrigger
        )
        
        // Track analytics with position
        AnalyticsManager.shared.logEvent("path_step_tapped_from_ai_chat", parameters: [
            "step_id": pathStep.id,
            "step_title": pathStep.title,
            "step_order": pathStep.order,
            "is_premium": pathStep.premium,
            "is_lesson": pathStep.isLesson,
            "recommendation_position": position.rawValue,
            "recommendation_trigger": lastRecommendationTrigger.rawValue
        ])
        
        // Fade out background music
        GeneralBackgroundMusicController.shared.fadeOutMusic(duration: 2.0)
        
        // Store current date as last session date
        SharedUserStorage.save(value: Date(), forKey: .lastMeditationDate)
        
        // Navigate to player
        navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
        
        logger.aiChat("🧠 AI_DEBUG [DUAL_PATH_PLAY] step_id=\(pathStep.id) position=\(position.rawValue)")
    }
    
    /// Play an explore session from a dual recommendation, tracking primary/secondary position
    private func playDualExploreSession(_ audioFile: AudioFile, position: RecommendationPosition) {
        logger.aiChat("🧠 AI_DEBUG [DUAL_EXPLORE_PLAY] session=\(audioFile.id) position=\(position.rawValue)")
        
        // Check subscription gate (post-first-session, not subscribed)
        if SubscriptionManager.shared.shouldGatePlay {
            SubscriptionManager.shared.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=AIChatContainerView_playDualExploreSession")
            #endif
            navigationCoordinator.subscriptionSource = .explore
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        
        // Set up SessionContextManager with recommendation position and trigger
        SessionContextManager.shared.setupLibrarySession(
            entryPoint: .aiChat,
            audioFile: audioFile,
            origin: .aiRecommended,
            recommendationPosition: position,
            recommendationTrigger: lastRecommendationTrigger
        )
        
        // Track analytics with position
        AnalyticsManager.shared.logEvent("explore_session_tapped_from_ai_chat", parameters: [
            "session_id": audioFile.id,
            "session_title": audioFile.title,
            "is_premium": audioFile.premium,
            "category": audioFile.category.rawValue,
            "recommendation_position": position.rawValue,
            "recommendation_trigger": lastRecommendationTrigger.rawValue
        ])
        
        // Fade out background music
        GeneralBackgroundMusicController.shared.fadeOutMusic(duration: 2.0)
        
        // Store last session date
        SharedUserStorage.save(value: Date(), forKey: .lastMeditationDate)
        
        // Navigate to player
        navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
        
        logger.aiChat("🧠 AI_DEBUG [DUAL_EXPLORE_PLAY] navigation complete for session=\(audioFile.id)")
    }
    
    /// Play a custom meditation from a dual recommendation, tracking primary/secondary position
    private func playDualCustomMeditation(_ meditation: AITimerResponse, position: RecommendationPosition) {
        logger.aiChat("🧠 AI_DEBUG [DUAL_CUSTOM_PLAY] position=\(position.rawValue)")
        
        // Subscription gate (post-first-session, not subscribed)
        if SubscriptionManager.shared.shouldGatePlay {
            SubscriptionManager.shared.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=AIChatContainerView_playDualCustomMeditation")
            #endif
            navigationCoordinator.subscriptionSource = .aiFirstMeditationPlay
            navigationCoordinator.pendingAIMeditation = meditation
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        
        let config = meditation.meditationConfiguration
        
        // Resolve binaural beat from deep link (matching playMeditationDirectly pattern)
        Task { @MainActor in
            // Make sure BB catalog is loaded before mapping
            if CatalogsManager.shared.beats.isEmpty && NetworkMonitor.shared.isConnected {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    CatalogsManager.shared.fetchCatalogs(triggerContext: "AIChatContainerView|dual custom play resolve") { _ in
                        continuation.resume()
                    }
                }
            }
            
            // Resolve bb from deep link first; fallback to reflection; else None
            var resolvedBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
            var bbIdFromLink = "None"
            if let components = URLComponents(url: meditation.deepLink, resolvingAgainstBaseURL: false),
               let qItems = components.queryItems,
               let v = qItems.first(where: { $0.name == "bb" })?.value {
                bbIdFromLink = v
                if let beat = CatalogsManager.shared.beats.first(where: { $0.id == bbIdFromLink }) {
                    resolvedBeat = beat
                }
            }
            // Reflection fallback if link did not yield a catalog match
            if resolvedBeat.id == "None" {
                if let beat = (Mirror(reflecting: config).children.first { $0.label == "binauralBeat" }?.value as? BinauralBeat), beat.id != "None" {
                    resolvedBeat = beat
                }
            }
            logger.aiChat("🧠 AI_DEBUG [DUAL_CUSTOM_PLAY] bb resolve link_bb=\(bbIdFromLink) final=\(resolvedBeat.id)")
            
            // Create timer config
            let timerConfig = TimerSessionConfig(
                minutes: config.duration,
                backgroundSound: config.backgroundSound,
                binauralBeat: resolvedBeat,
                cueSettings: config.cueSettings,
                title: config.title,
                description: meditation.description
            )
            
            // Set up SessionContextManager with recommendation position and trigger
            SessionContextManager.shared.setupCustomMeditationSession(
                entryPoint: .aiChat,
                timerConfig: timerConfig,
                origin: .aiRecommended,
                customizationLevel: .suggested,
                recommendationPosition: position,
                recommendationTrigger: self.lastRecommendationTrigger
            )
            
            // Navigate to countdown
            navigationCoordinator.navigateToTimerCountdown(
                totalMinutes: config.duration,
                backgroundSound: config.backgroundSound,
                cueSettings: config.cueSettings,
                binauralBeat: resolvedBeat,
                isDeepLinked: false,
                title: config.title,
                description: meditation.description
            )
            
            logger.aiChat("🧠 AI_DEBUG [DUAL_CUSTOM_PLAY] navigation complete, position=\(position.rawValue)")
        }
        
        // Log analytics with position (outside Task since it doesn't need resolved beat)
        AnalyticsManager.shared.logEvent("ai_interaction", parameters: [
            "stage": "start",
            "start_method": "dual_recommendation",
            "meditation_id": String(describing: config.id),
            "duration_min": config.duration,
            "background_sound": config.backgroundSound.name,
            "cue_count": config.cueSettings.count,
            "title": config.title ?? "Unknown",
            "recommendation_position": position.rawValue
        ])
    }

    private func handlePostPracticeReport(_ report: PostPracticeReport) {
        logger.aiChat("📋 [POST_PRACTICE] VIEW_RECEIVED sessionId=\(report.sessionId) status=\(report.status.rawValue) isReadyForDisplay=\(report.isReadyForDisplay) bubbleId=\(report.bubbleId?.uuidString ?? "nil")")
        
        guard report.isReadyForDisplay else {
            logger.aiChat("📋 [POST_PRACTICE] VIEW_SKIP not ready for display")
            return
        }
        
        // CRITICAL: Ensure conversation is loaded before adding any messages.
        // The Combine publisher can fire before onAppear, causing the post-practice
        // message to be added to an empty conversation, which would then overwrite
        // the stored conversation history. This call is idempotent.
        conversationState.loadIfNeeded()

        // Build structured post-practice content
        let postPracticeContent = buildPostPracticeContent(from: report)
        logger.aiChat("📋 [POST_PRACTICE] VIEW_CONTENT_BUILT combinedText_len=\(postPracticeContent.combinedText.count)")

        // Check for existing bubble - if message is already displayed, don't replace content
        // This prevents the jarring UX of praise text changing after the user has already seen it
        if let bubbleId = report.bubbleId, let existingIndex = conversationState.conversation.firstIndex(where: { $0.id == bubbleId && !$0.isUser }) {
            logger.aiChat("📋 [POST_PRACTICE] VIEW_FOUND_EXISTING bubbleId=\(bubbleId) at index=\(existingIndex)")
            
            // Message already displayed - skip replacement, just mark completed if polished
            // The user has already seen the fallback message, so keep it stable
            logger.aiChat("📋 [POST_PRACTICE] VIEW_SKIP_REPLACE already displayed, keeping original content")
            if report.status == .readyPolished {
                logger.aiChat("📋 [POST_PRACTICE] VIEW_MARK_COMPLETED (polish arrived but keeping original)")
                PostSessionMessageStore.shared.markCompleted(sessionId: report.sessionId)
            }
            return
        }

        // New message insertion
        logger.aiChat("📋 [POST_PRACTICE] VIEW_INSERT new message")
        let newBubbleId = conversationState.addPostPracticeMessage(content: postPracticeContent)
        PostSessionMessageStore.shared.markDisplayed(sessionId: report.sessionId, bubbleId: newBubbleId)

        // Log session type details
        if postPracticeContent.isPathPostPractice {
            logger.aiChat("📋 [POST_PRACTICE] VIEW_INSERT_COMPLETE type=path step=\(postPracticeContent.completedPathStep?.id ?? "nil") next=\(postPracticeContent.nextPathStep?.id ?? "nil") pathComplete=\(postPracticeContent.isPathComplete)")
        } else {
            logger.aiChat("📋 [POST_PRACTICE] VIEW_INSERT_COMPLETE type=explore/custom has_hr_graph=\(postPracticeContent.heartRateGraphData != nil)")
        }
        
        // Schedule a post-session prompt after the post-practice typing completes.
        // This applies to ALL session types (path, explore, custom) as the default behavior.
        // The flag is consumed by handleLatestAIMessageIdChange when typing finishes.
        let isPathComplete = postPracticeContent.isPathPostPractice && postPracticeContent.isPathComplete
        pendingPostSessionPrompt = true
        pendingPostSessionPromptIsPathComplete = isPathComplete
        #if DEBUG
        print("[PostSessionPrompt] Flag SET - pendingPrompt=true, isPathComplete=\(isPathComplete), isPathSession=\(postPracticeContent.isPathPostPractice)")
        #endif
        logger.aiChat("🤔 [POST_SESSION_PROMPT] Scheduled after post-practice typing completes isPathComplete=\(isPathComplete)")
        logger.aiChat("📋 [POST_PRACTICE] ═══════════════════════════════════════════════")
    }
    
    /// Shows a post-session prompt asking if the user wants to meditate more.
    /// For path-complete sessions, shows a transition message first, then the prompt.
    /// For non-path-complete sessions, shows the prompt after a short delay.
    private func showPostSessionPrompt(isPathComplete: Bool) {
        #if DEBUG
        print("[PostSessionPrompt] showPostSessionPrompt called - isPathComplete=\(isPathComplete)")
        #endif
        logger.aiChat("🤔 [POST_SESSION_PROMPT] showPostSessionPrompt isPathComplete=\(isPathComplete)")
        
        let delay: TimeInterval
        
        if isPathComplete {
            #if DEBUG
            print("[PostSessionPrompt] Path complete flow - refreshing phase and showing transition message")
            #endif
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] 🎯 Path complete - showing transition + post-session prompt")
            // Refresh phase so orchestrator sees dailyRoutines
            ProductJourneyManager.shared.refreshPhase()
            let phase = ProductJourneyManager.shared.currentPhase.displayName
            #if DEBUG
            print("[PostSessionPrompt] Phase refreshed to: \(phase)")
            #endif
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Phase refreshed to: \(phase)")
            // Show transition message (starts typing)
            conversationState.addAIMessage(text: "From now on, I'll suggest daily routines based on the time of day.")
            delay = 3.0  // Wait for short transition text to type out
        } else {
            #if DEBUG
            print("[PostSessionPrompt] Non-path-complete flow - scheduling prompt with 0.5s delay")
            #endif
            logger.aiChat("🤔 [POST_SESSION_PROMPT] Session completed - scheduling prompt")
            delay = 0.5  // Small delay for smooth UX
        }
        
        #if DEBUG
        print("[PostSessionPrompt] Scheduling prompt in \(delay)s")
        #endif
        postSessionPromptTask?.cancel()
        postSessionPromptTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let prompt = PostSessionPrompt.standard(isPathComplete: isPathComplete)
            let question = "Would you like to keep meditating?"
            self.conversationState.addPostSessionPrompt(question: question, prompt: prompt)
            #if DEBUG
            print("[PostSessionPrompt] ✅ Prompt displayed")
            #endif
            logger.aiChat("🤔 [POST_SESSION_PROMPT] ✅ Prompt shown isPathComplete=\(isPathComplete)")
            self.postSessionPromptTask = nil
        }
    }
    
    /// Handles the user's response to the post-session prompt.
    /// - Parameter wantsMore: true if user tapped "Yes", false if "No"
    private func handlePostSessionPromptResponse(_ wantsMore: Bool) {
        #if DEBUG
        print("[PostSessionPrompt] handlePostSessionPromptResponse wantsMore=\(wantsMore)")
        #endif
        logger.aiChat("🤔 [POST_SESSION_PROMPT] Response received wantsMore=\(wantsMore)")
        
        // Track analytics
        AnalyticsManager.shared.logEvent("post_session_prompt_response", parameters: [
            "response": wantsMore ? "yes" : "no"
        ])
        
        // Persist the response in the message so buttons stay in final state across re-renders
        conversationState.markPostSessionPromptResponded(respondedYes: wantsMore)
        postSessionPromptTask?.cancel()
        postSessionPromptTask = nil
        let shouldRetryDeferredTimely = hasDeferredTimelyRecommendationCheck
        hasDeferredTimelyRecommendationCheck = false
        
        if wantsMore {
            // User wants more — fetch and show dual recommendation
            // No user message echo needed; the highlighted button is sufficient feedback.
            #if DEBUG
            print("[PostSessionPrompt] User said YES - fetching recommendation...")
            #endif
            logger.aiChat("🤔 [POST_SESSION_PROMPT] User said YES - fetching recommendation")
            
            Task {
                guard let dualRec = await DualRecommendationOrchestrator.shared.getDualRecommendation() else {
                    #if DEBUG
                    print("[PostSessionPrompt] ❌ getDualRecommendation() returned nil")
                    #endif
                    logger.aiChat("🤔 [POST_SESSION_PROMPT] ❌ No recommendation available")
                    await MainActor.run {
                        self.conversationState.addAIMessage(text: "I don't have a recommendation right now, but feel free to ask me anytime.")
                    }
                    return
                }
                
                #if DEBUG
                print("[PostSessionPrompt] ✅ Got recommendation - primary=\(dualRec.primary.type.analyticsType) secondary=\(dualRec.secondary?.type.analyticsType ?? "none")")
                #endif
                
                await MainActor.run {
                    self.lastRecommendationTrigger = .postPractice
                    self.displayDualRecommendation(dualRec)
                    logger.aiChat("🤔 [POST_SESSION_PROMPT] ✅ Dual recommendation shown after YES response")
                }
            }
        } else {
            // User doesn't want more — show gentle dismissal
            // No user message echo needed; the highlighted button is sufficient feedback.
            #if DEBUG
            print("[PostSessionPrompt] User said NO - showing dismissal")
            #endif
            logger.aiChat("🤔 [POST_SESSION_PROMPT] User said NO - showing dismissal")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.conversationState.addAIMessage(text: "I'll be here whenever you're ready.")
                if shouldRetryDeferredTimely {
                    self.checkAndShowRecommendation()
                }
            }
        }
    }
    
    /// Builds structured post-practice content from report
    private func buildPostPracticeContent(from report: PostPracticeReport) -> ChatPostPracticeContent {
        // Build heart rate graph data if available (need 2+ samples for graph)
        let heartRateGraphData: ChatHeartRateData? = {
            guard let samples = report.metadata.heartRateSamples,
                  samples.count >= 2,
                  let start = report.metadata.heartRateStartBPM,
                  let end = report.metadata.heartRateEndBPM else {
                return nil
            }
            let minInt = report.metadata.heartRateMinBPM
            return ChatHeartRateData(
                startBPM: Double(start),
                endBPM: Double(end),
                samples: samples,
                minBPM: minInt.flatMap { $0 > 0 ? Double($0) : nil }
            )
        }()
        
        // Resolve Path steps from IDs if this is a Path session
        let completedPathStep: PathStep? = report.metadata.completedPathStepId.flatMap { id in
            PathProgressManager.shared.pathSteps.first { $0.id == id }
        }
        let nextPathStep: PathStep? = report.metadata.nextPathStepId.flatMap { id in
            PathProgressManager.shared.pathSteps.first { $0.id == id }
        }
        
        // Log Path-specific info
        if report.metadata.isPathSession {
            logger.aiChat("🧠 AI_DEBUG PATH_POST_PRACTICE buildContent step=\(report.metadata.completedPathStepId ?? "nil") next=\(report.metadata.nextPathStepId ?? "nil") pathComplete=\(report.metadata.isPathComplete)")
        }
        
        return ChatPostPracticeContent(
            completionPraise: report.completionPraise,
            streakMessage: report.streakMessage,
            heartRateMessage: report.heartRateMessage,
            heartRateGraphData: heartRateGraphData,
            completedPathStep: completedPathStep,
            nextPathStep: nextPathStep,
            isPathComplete: report.metadata.isPathComplete
        )
    }

    // MARK: - Thinking message helpers
    @State private var thinkingMessageId: UUID? = nil
    
    // MARK: - Customization phase state
    @State private var pendingCustomFollowUp: Bool = false
    
    // MARK: - Post-session prompt state
    @State private var pendingPostSessionPrompt: Bool = false
    @State private var pendingPostSessionPromptIsPathComplete: Bool = false
    @State private var postSessionPromptTask: Task<Void, Never>? = nil
    @State private var hasDeferredTimelyRecommendationCheck: Bool = false
    
    // MARK: - Timely recommendation state
    @State private var isTimelyRecommendationInFlight: Bool = false
    @State private var timelyRecommendationTask: Task<Void, Never>? = nil
    
    // MARK: - Recommendation trigger tracking (for analytics)
    /// Tracks what triggered the most recent recommendation so play actions can report it.
    @State private var lastRecommendationTrigger: RecommendationTrigger = .none

    private func handleLoadingChange(_ loading: Bool) {
        if loading {
            // Insert a temporary "Thinking..." AI message (no typing animation)
            if thinkingMessageId == nil {
                // Insert a placeholder message that renders like a normal AI bubble
                let msg = ChatMessage(content: "", isUser: false)
                thinkingMessageId = msg.id
                conversationState.conversation.append(msg)
                logger.aiChat("🧠 AI_DEBUG [THINKING]: Inserted thinking message id=\(msg.id)")
            }
        } else {
            // Remove the temporary message on completion
            logger.aiChat("🧠 AI_DEBUG [THINKING]: Loading finished, removing thinking message")
            removeThinkingMessageIfNeeded()
            // Keyboard suppression is handled by aiResponseComplete when typing finishes
        }
    }

    private func removeThinkingMessageIfNeeded() {
        if let id = thinkingMessageId, let idx = conversationState.conversation.firstIndex(where: { $0.id == id }) {
            logger.aiChat("🧠 AI_DEBUG [THINKING]: Removing thinking message id=\(id) at index=\(idx)")
            conversationState.conversation.remove(at: idx)
        } else if thinkingMessageId != nil {
            logger.aiChat("🧠 AI_DEBUG [THINKING]: Thinking message already removed id=\(thinkingMessageId!)")
        }
        thinkingMessageId = nil
    }

    private func clearChat() {
        HapticManager.shared.impact(.light)
        // Clear temporary UI states
        removeThinkingMessageIfNeeded()
        manager.clearResult()
        resetDeferredRecommendationState()
        // Clear conversation and persist
        conversationState.clearConversation()
        hasQueuedOnboarding = false
        activeActionMessageId = nil
        pendingOnboardingStepIndex = nil
        pendingOnboardingMessageId = nil
        showLastStepThinking = false
        
        // Note: Do NOT change keyboard state when clearing chat.
        // The keyboard should remain in whatever state it was in before.
        
        // Reset onboarding step index to 0 if onboarding is not complete
        // This ensures onboarding restarts from the beginning on each clear
        if !SenseiOnboardingState.shared.isComplete {
            SenseiOnboardingState.shared.resetStepIndexForNewChat()
        }
        
        // Queue onboarding if needed (only for new/incomplete users)
        let queued = queueOnboardingIfNeeded(force: true)
        if queued {
            // Only suppress keyboard if onboarding is starting - this is necessary for onboarding UX
            keyboardController.suppressForOnboarding()
        }
        // If no onboarding, leave keyboard state unchanged
        
        logger.aiChat("🧠 AI_DEBUG clear_chat completed")
    }

    private func resetDeferredRecommendationState() {
        postSessionPromptTask?.cancel()
        postSessionPromptTask = nil
        timelyRecommendationTask?.cancel()
        timelyRecommendationTask = nil
        pendingPostSessionPrompt = false
        pendingPostSessionPromptIsPathComplete = false
        hasDeferredTimelyRecommendationCheck = false
        TimelyRecommendationGate.shared.isInFlight = false
        isTimelyRecommendationInFlight = false
    }
}
