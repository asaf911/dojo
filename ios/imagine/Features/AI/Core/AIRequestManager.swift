import Foundation
import SwiftUI

@MainActor
class AIRequestManager: ObservableObject {
    @Published var isLoading = false
    @Published var generatedMeditation: AITimerResponse?
    /// Acknowledgment text to display above the meditation card (e.g., "I've designed a meditation to help you relax...")
    @Published var generatedMeditationAcknowledgment: String?
    @Published var conversationalResponse: String?
    @Published var error: String?
    @Published var showResult = false
    
    // Classified intent for context-aware thinking animation
    @Published var classifiedIntent: String? = nil
    
    struct AIRequestContext {
        let request_id: String
        let user_prompt: String
        let prompt_length: Int
        let request_type: String // meditation | conversation | explain | history
        let history_len: Int
    }
    
    @Published private(set) var lastRequestContext: AIRequestContext?
    
    // Unified AI: single server call via POST /ai/request
    // History query router for handling meditation history questions
    private let historyQueryRouter = HistoryQueryRouter.shared
    // Rotate alternative suggestions to avoid repetition on "another idea"
    private var lastAlternativeSuggestionIndex: Int? = nil
    // Persist the last concrete idea we proposed so a "Yes" reply produces that exact session
    private var lastSuggestedIdea: String? = nil
    private let alternativeSuggestions: [String] = [
        "How about a 8 min relaxation with a short body scan?",
        "How about a 10 min calm-breathing reset?",
        "How about a 12 min mantra focus to reset attention?",
        "How about a 15 min visualization for clarity and motivation?",
        "How about a 9 min open-heart compassion practice?",
        "How about a 11 min mindfulness with nature background?",
        "How about a 13 min retrospection to reflect on your day?",
        "How about a 10 min relaxation with body scan and mantra?",
        "How about a 14 min focus reset with breathwork and visualization?",
        "How about a 7 min quick calm with body scan?"
    ]
    
    // Download/preload state for play button gating
    @Published var isPreparingPlayback: Bool = false
    @Published var preparationProgress: Double = 0.0 // 0.0 - 1.0
    // Awaiting user confirmation to generate a contextual meditation after an explain/conversation reply
    @Published var awaitingMeditationConfirmation: Bool = false
    // Persist last meditation so short follow-ups can modify it even across new prompts
    private var lastMeditation: AITimerResponse?
    /// Last N background sound IDs (max 5, FIFO); sent to server for weighted random variety
    private var recentBackgroundSoundIds: [String] = []
    
    func generateMeditation(prompt: String, conversationHistory: [ChatMessage] = [], variationSeed: Int? = nil, maxDuration: Int? = nil) {
        var trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Log max duration constraint if provided (currently unused - duration parsed from prompt)
        if let max = maxDuration {
            logger.aiChat("🧠 AI_DEBUG REQ maxDuration=\(max)")
        }
        
        logger.eventMessage("🤖 AI_MEDITATION_UI: === USER INITIATED MEDITATION GENERATION ===")
        logger.eventMessage("🤖 AI_MEDITATION_UI: Raw prompt: '\(prompt)'")
        logger.eventMessage("🤖 AI_MEDITATION_UI: Trimmed prompt: '\(trimmedPrompt)'")
        logger.eventMessage("🤖 AI_MEDITATION_UI: Conversation context: \(conversationHistory.count) messages")
        
        guard !trimmedPrompt.isEmpty else {
            logger.errorMessage("🤖 AI_MEDITATION_UI: Empty prompt provided")
            error = "Please enter a meditation request"
            return
        }
        
        // Always send user's raw prompt to AI — no keyword-based replacement.
        // AI interprets intent (meditation vs conversation) and extracts duration from prompt or conversation history.
        awaitingMeditationConfirmation = false

        // History queries are now handled via AI classification (intent == "history")

        logger.eventMessage("🤖 AI_MEDITATION_UI: Setting UI state to loading...")
        isLoading = true
        error = nil
        conversationalResponse = nil
        showResult = false
        classifiedIntent = nil  // Reset intent for new request
        
        logger.eventMessage("🤖 AI_MEDITATION_UI: Starting meditation generation for: '\(trimmedPrompt)'")
        logger.aiChat("🧠 AI_DEBUG FLOW start route=simplified request_type=pending history=\(conversationHistory.count)")
        logger.eventMessage("🤖 AI_MEDITATION_UI: Prompt length: \(trimmedPrompt.count) characters")
        
        // Log analytics event
        // Build request context for unified analytics
        let ctx = AIRequestContext(
            request_id: UUID().uuidString,
            user_prompt: trimmedPrompt,
            prompt_length: trimmedPrompt.count,
            request_type: "pending",
            history_len: conversationHistory.count
        )
        self.lastRequestContext = ctx
        // Set skip/steps state before marking complete (for direct chat path)
        if !SenseiOnboardingState.shared.isComplete {
            let totalSteps = 6
            let currentStepIndex = SenseiOnboardingState.shared.currentStepIndex(totalSteps: totalSteps)
            SenseiOnboardingState.shared.stepsCompletedBeforeExit = currentStepIndex + 1
            SenseiOnboardingState.shared.didSkipEarly = SenseiOnboardingState.shared.arrivedAtFinalViaSkip
        }
        // Flip Sensei onboarding completion when the first prompt is submitted
        SenseiOnboardingState.shared.markCompleted(source: "chat", requestId: ctx.request_id, userPrompt: trimmedPrompt)
        // AI chat debug: request start
        logger.aiChat("🧠 AI_DEBUG REQ id=\(ctx.request_id) type=pending hist=\(ctx.history_len) prompt=\(trimmedPrompt)")
        logger.aiChat("🧠 AI_DEBUG STATE before_call loading=\(self.isLoading) showResult=\(self.showResult) awaitingConfirm=\(self.awaitingMeditationConfirmation)")
        // Unified analytics: request stage
        var reqParams: [String: Any] = baseParams(from: ctx)
        reqParams["stage"] = "request"
        AnalyticsManager.shared.logEvent("ai_interaction", parameters: reqParams)
        
        // Fire the request analytics asynchronously so it never blocks UI
        let requestParamsForAnalytics: [String: Any] = {
            var p = baseParams(from: ctx)
            p["stage"] = "request"
            return p
        }()
        Task.detached(priority: .background) {
            AnalyticsManager.shared.logEvent("ai_interaction", parameters: requestParamsForAnalytics)
        }

        // Run AI work off the main actor for immediate responsiveness
        let trimmedPromptCopy = trimmedPrompt
        let historyCopy = conversationHistory
        let historyRouter = self.historyQueryRouter
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let strongSelf = self else { return }
            do {
                // Offline gate: no AI when offline
                guard ConnectivityHelper.isConnectedToInternet() else {
                    print("[Server][AI] AIRequestManager: offline - skipping AI request")
                    await MainActor.run {
                        strongSelf.error = "You're offline. AI features need a connection."
                        strongSelf.isLoading = false
                    }
                    return
                }

                logger.eventMessage("🤖 AI_MEDITATION_UI: Calling AI service...")

                // Build context for path/explore guidance; capture step/session for notifications
                let (pathInfo, exploreInfo, capturedNextStep, capturedSession, pathAllCompleted, lastMeditationSnapshot, recentBackgroundSounds, exploreMeditationThemes, exploreBlueprintId) = await MainActor.run { () -> (AIServerRequestContext.PathInfo?, AIServerRequestContext.ExploreInfo?, PathStep?, AudioFile?, Bool, AIServerRequestContext.LastMeditationSnapshot?, [String]?, [String]?, String?) in
                    ExploreRecommendationManager.shared.loadAudioFiles()
                    let pm = PathProgressManager.shared
                    let em = ExploreRecommendationManager.shared
                    var path: AIServerRequestContext.PathInfo?
                    var nextStep: PathStep?
                    if pm.shouldRecommendPath(), let step = pm.nextStep {
                        path = AIServerRequestContext.PathInfo(
                            nextStepTitle: step.title,
                            completedCount: pm.completedStepCount,
                            totalCount: pm.totalStepCount,
                            allCompleted: pm.allStepsCompleted
                        )
                        nextStep = step
                    }
                    var explore: AIServerRequestContext.ExploreInfo?
                    var session: AudioFile?
                    var meditationThemes: [String]?
                    var blueprintId: String?
                    if em.shouldRecommendExplore() || strongSelf.isExplicitPreRecordedRequest(trimmedPromptCopy),
                       let s = em.getTimeAppropriateSession() {
                        explore = AIServerRequestContext.ExploreInfo(
                            sessionTitle: s.title,
                            timeOfDay: em.getCurrentTimeOfDayName()
                        )
                        session = s
                        let slot = ExploreRecommendationManager.TimeOfDay.current()
                        meditationThemes = slot.senseiMeditationThemeTags
                        blueprintId = slot.senseiMeditationBlueprintId.rawValue
                        if slot == .night,
                           Self.promptSignalsExplicitMorning(trimmedPromptCopy) {
                            meditationThemes = nil
                            blueprintId = nil
                        }
                    }
                    let snapshot = ChatMessage.lastCustomMeditationSnapshot(in: historyCopy)
                    let recent: [String]? = strongSelf.recentBackgroundSoundIds.isEmpty ? nil : strongSelf.recentBackgroundSoundIds
                    return (path, explore, nextStep, session, pm.allStepsCompleted, snapshot, recent, meditationThemes, blueprintId)
                }

                let context = AIServerRequestContext(
                    pathInfo: pathInfo,
                    exploreInfo: exploreInfo,
                    lastMeditationDuration: nil,
                    lastMeditationSnapshot: lastMeditationSnapshot,
                    recentBackgroundSounds: recentBackgroundSounds,
                    meditationThemes: exploreMeditationThemes,
                    blueprintId: exploreBlueprintId
                )
                let historyItems = historyCopy.map { msg in
                    ConversationHistoryItem(
                        role: msg.isUser ? "user" : "assistant",
                        content: msg.isUser ? msg.content : msg.aiRequestAssistantContent
                    )
                }

                if let snap = lastMeditationSnapshot {
                    logger.aiChat("🧠 AI_DEBUG [MEDITATION_TURN_CTX] snapshot durationMin=\(snap.durationMinutes) title=\(snap.title ?? "-") snippetChars=\(snap.descriptionSnippet?.count ?? 0)")
                } else {
                    logger.aiChat("🧠 AI_DEBUG [MEDITATION_TURN_CTX] snapshot=nil")
                }
                let tailSummary = historyItems.suffix(2).map { item -> String in
                    let flat = item.content.replacingOccurrences(of: "\n", with: " ")
                    let preview = flat.count > 220 ? String(flat.prefix(220)) + "…" : flat
                    return "\(item.role) len=\(item.content.count) preview=\(preview)"
                }.joined(separator: " || ")
                logger.aiChat("🧠 AI_DEBUG [MEDITATION_TURN_CTX] promptLen=\(trimmedPromptCopy.count) historyLen=\(historyItems.count) last2=[\(tailSummary)]")

                let response = try await AIRequestService.shared.processAIRequest(
                    prompt: trimmedPromptCopy,
                    conversationHistory: historyItems,
                    context: context,
                    triggerContext: "AIRequestManager|processUserMessage"
                )

                let rspSummary: String
                switch response.content {
                case .meditation:
                    rspSummary = "content=meditation"
                case .text(let t):
                    let flat = t.replacingOccurrences(of: "\n", with: " ")
                    let preview = flat.count > 600 ? String(flat.prefix(600)) + "…" : flat
                    rspSummary = "content=text len=\(t.count) preview=\(preview)"
                case .history(let q):
                    rspSummary = "content=history historyQueryType=\(q ?? "nil")"
                }
                logger.aiChat("🧠 AI_DEBUG [MEDITATION_TURN_RSP] intent=\(response.intent) \(rspSummary)")

                let intent = response.intent
                let updatedCtx = AIRequestContext(request_id: ctx.request_id, user_prompt: ctx.user_prompt, prompt_length: ctx.prompt_length, request_type: intent, history_len: ctx.history_len)
                await MainActor.run {
                    strongSelf.lastRequestContext = updatedCtx
                    strongSelf.classifiedIntent = intent
                }

                // Subscription gate: block meditation for unsubscribed users who already created first AI meditation
                if intent == "meditation" {
                    // Check both the live subscription status AND the persisted value for robustness
                    let liveSubscribed = SubscriptionManager.shared.isUserSubscribed
                    let persistedSubscribed = SharedUserStorage.retrieve(forKey: .isUserSubscribed, as: Bool.self) ?? false
                    let isSubscribed = liveSubscribed || persistedSubscribed
                    
                    let hasCreatedFirstAIMeditation = SharedUserStorage.retrieve(forKey: .hasCreatedFirstAIMeditation, as: Bool.self) ?? false
                    
                    logger.aiChat("🧠 AI_DEBUG SUBSCRIPTION_CHECK live=\(liveSubscribed) persisted=\(persistedSubscribed) combined=\(isSubscribed) hasCreatedFirst=\(hasCreatedFirstAIMeditation)")
                    
                    if !isSubscribed && hasCreatedFirstAIMeditation {
                        logger.aiChat("🧠 AI_DEBUG SUBSCRIPTION_GATE blocked intent=meditation subscribed=false hasCreatedFirst=true")
                        AnalyticsManager.shared.logEvent("ai_meditation_gated", parameters: [
                            "user_prompt": trimmedPromptCopy,
                            "request_id": ctx.request_id
                        ])
                        await MainActor.run {
                            strongSelf.isLoading = false
                            NotificationCenter.default.post(name: .aiTriggerSubscription, object: nil)
                        }
                        return
                    }
                }

                // Handle history: server returns intent + optional historyQueryType (AI-interpreted); client runs local query
                if intent == "history" {
                    let historyQueryType: String?
                    if case .history(let qType) = response.content {
                        historyQueryType = qType
                        logger.aiChat("🧠 AI_DEBUG HISTORY intent from server: \(trimmedPromptCopy) historyQueryType=\(qType ?? "nil")")
                    } else {
                        historyQueryType = nil
                        logger.aiChat("🧠 AI_DEBUG HISTORY intent from server: \(trimmedPromptCopy)")
                    }
                    let queryResult = historyRouter.executeQuery(for: trimmedPromptCopy, historyQueryType: historyQueryType)
                    let formattedResponse = historyRouter.formatForAIResponse(queryResult)
                    AnalyticsManager.shared.logEvent("ai_history_query", parameters: [
                        "user_prompt": trimmedPromptCopy,
                        "success": queryResult.success,
                        "session_count": queryResult.sessions.count,
                        "request_id": ctx.request_id
                    ])
                    await MainActor.run {
                        strongSelf.conversationalResponse = formattedResponse
                        strongSelf.showResult = false
                        strongSelf.awaitingMeditationConfirmation = false
                        strongSelf.isLoading = false
                    }
                    return
                }
                
                // Handle path guidance: server returns text; use captured step for notification
                if intent == "path_guidance" {
                    logger.aiChat("🧠 AI_DEBUG PATH_GUIDANCE intent: \(trimmedPromptCopy)")
                    if pathAllCompleted {
                        await MainActor.run {
                            strongSelf.conversationalResponse = "You've completed the entire Path - amazing work! You now have a solid meditation foundation. Would you like me to create a personalized meditation for you?"
                            strongSelf.isLoading = false
                        }
                        return
                    }
                    if let nextStep = capturedNextStep {
                        let message: String
                        if case .text(let t) = response.content { message = t }
                        else { message = "Here's your next step." }
                        AnalyticsManager.shared.logEvent("path_guidance_recommended", parameters: [
                            "step_id": nextStep.id,
                            "step_order": nextStep.order,
                            "completed_count": pathInfo?.completedCount ?? 0,
                            "user_prompt": trimmedPromptCopy
                        ])
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .aiPathGuidanceRecommendation,
                                object: nil,
                                userInfo: ["message": message, "step": nextStep]
                            )
                            strongSelf.isLoading = false
                        }
                        return
                    }
                    if case .text(let t) = response.content {
                        await MainActor.run {
                            strongSelf.conversationalResponse = t
                            strongSelf.isLoading = false
                        }
                        return
                    }
                }
                
                // Handle explore guidance: server returns text; use captured session for notification
                if intent == "explore_guidance" {
                    logger.aiChat("🧠 AI_DEBUG [EXPLORE] intent: \(trimmedPromptCopy)")
                    if let session = capturedSession {
                        let message: String
                        if case .text(let t) = response.content { message = t }
                        else {
                            let tagsLower = session.tags.map { $0.lowercased() }
                            let timeOfDay = exploreInfo?.timeOfDay ?? "day"
                            if tagsLower.contains("morning") { message = "Here's a great way to start your \(timeOfDay):" }
                            else if tagsLower.contains("noon") { message = "This is a great \(timeOfDay) reset:" }
                            else if tagsLower.contains("evening") { message = "Here's a nice way to wind down your day:" }
                            else if tagsLower.contains("sleep") { message = "This will help you relax and prepare for rest:" }
                            else { message = "Here's a session for you." }
                        }
                        logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] session=\(session.id) title=\(session.title)")
                        AnalyticsManager.shared.logEvent("explore_guidance_recommended", parameters: [
                            "session_id": session.id,
                            "session_title": session.title,
                            "time_of_day": exploreInfo?.timeOfDay ?? "",
                            "is_premium": session.premium,
                            "user_prompt": trimmedPromptCopy
                        ])
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .aiExploreGuidanceRecommendation,
                                object: nil,
                                userInfo: ["message": message, "session": session]
                            )
                            strongSelf.isLoading = false
                        }
                        return
                    }
                    if case .text(let t) = response.content {
                        await MainActor.run {
                            strongSelf.conversationalResponse = t
                            strongSelf.isLoading = false
                        }
                        return
                    }
                }
                
                // Handle text content (explain, conversation, app_help, out_of_scope)
                if case .text(let text) = response.content {
                    logger.aiChat("🧠 AI_DEBUG FLOW result ok id=\(ctx.request_id) type=text")
                    await MainActor.run {
                        strongSelf.isLoading = false
                        strongSelf.conversationalResponse = text
                        strongSelf.lastSuggestedIdea = strongSelf.extractIdea(from: text)
                        var cparams: [String: Any] = strongSelf.baseParams(from: strongSelf.lastRequestContext ?? ctx)
                        cparams["stage"] = "response"
                        cparams["response_type"] = "conversation"
                        cparams["response_text"] = text
                        cparams["response_length"] = text.count
                        AnalyticsManager.shared.logEvent("ai_interaction", parameters: cparams)
                    }
                    return
                }

                // Handle meditation: server returns package; use keyword fallback for acknowledgment
                guard intent == "meditation", case .meditation(let package) = response.content else {
                    logger.aiChat("🧠 AI_DEBUG FLOW unexpected response intent=\(intent)")
                    await MainActor.run { strongSelf.isLoading = false }
                    return
                }

                let timerResponse = package.toAITimerResponse()
                let l = trimmedPromptCopy.lowercased()
                let acknowledgment: String
                if l.contains("scatter") || l.contains("focus") {
                    acknowledgment = "I've designed a meditation to help steady your attention."
                } else if l.contains("anxiety") || l.contains("stress") {
                    acknowledgment = "Here's a practice to help calm your nervous system."
                } else if l.contains("sleep") {
                    acknowledgment = "I've crafted a meditation to help you wind down for rest."
                } else if l.contains("meeting") || l.contains("presentation") {
                    acknowledgment = "Here's a practice to help you feel grounded and focused."
                } else {
                    acknowledgment = "I've put together a meditation tailored for you."
                }
                await MainActor.run {
                    strongSelf.generatedMeditationAcknowledgment = acknowledgment
                }

                logger.eventMessage("🤖 AI_MEDITATION_UI: AI service call completed successfully")
                logger.aiChat("🧠 AI_DEBUG FLOW result ok id=\(ctx.request_id) type=meditation")

                let finalResult: AIMeditationResult = .meditation(timerResponse)
                await MainActor.run {
                    strongSelf.isLoading = false
                    
                    switch finalResult {
                    case .meditation(let timerResponse):
                        logger.eventMessage("🤖 AI_MEDITATION_UI: Updating UI with meditation result")
                        logger.aiChat("🧠 AI_DEBUG FLOW response type=meditation id=\(strongSelf.lastRequestContext?.request_id ?? ctx.request_id)")
                        let cuesSummary = timerResponse.meditationConfiguration.cueSettings.map { setting -> String in
                            let trig: String
                            switch setting.triggerType {
                            case .minute: trig = String(setting.minute ?? 0)
                            case .start: trig = "start"
                            case .end: trig = "end"
                            case .second: trig = "s\(setting.minute ?? 0)"
                            }
                            return "\(setting.cue.id)@\(trig)"
                        }.joined(separator: ",")
                        logger.aiChat("🧠 AI_DEBUG RESP id=\(strongSelf.lastRequestContext?.request_id ?? ctx.request_id) type=meditation dur=\(timerResponse.meditationConfiguration.duration)m cues=\(cuesSummary) bg=\(timerResponse.meditationConfiguration.backgroundSound.id)")
                        strongSelf.generatedMeditation = timerResponse
                        strongSelf.lastMeditation = timerResponse
                        // Track recent background sounds for weighted random variety
                        let bgId = timerResponse.meditationConfiguration.backgroundSound.id
                        if !bgId.isEmpty && bgId != "None" {
                            strongSelf.recentBackgroundSoundIds.removeAll { $0 == bgId }
                            strongSelf.recentBackgroundSoundIds.append(bgId)
                            if strongSelf.recentBackgroundSoundIds.count > 5 {
                                strongSelf.recentBackgroundSoundIds.removeFirst()
                            }
                        }
                        strongSelf.showResult = true
                        
                        // Unified analytics: response (meditation) with original request inline
                        var params: [String: Any] = strongSelf.baseParams(from: strongSelf.lastRequestContext ?? ctx)
                        params["stage"] = "response"
                        params["response_type"] = "meditation"
                        // Ensure JSON-safe string for meditation_id
                        params["meditation_id"] = String(describing: timerResponse.meditationConfiguration.id)
                        params["duration_min"] = timerResponse.meditationConfiguration.duration
                        params["background_sound"] = timerResponse.meditationConfiguration.backgroundSound.name
                        params["cue_count"] = timerResponse.meditationConfiguration.cueSettings.count
                        params["title"] = timerResponse.meditationConfiguration.title ?? "Unknown"
                        // Include assistant response text (trim to a safe length for analytics)
                        let rawText = timerResponse.description
                        let maxLen = 4000
                        let trimmedText = rawText.count > maxLen ? String(rawText.prefix(maxLen)) : rawText
                        params["response_text"] = trimmedText
                        params["response_length"] = rawText.count
                        // Include full module/cue timeline details
                        params["cues_timeline"] = timerResponse.meditationConfiguration.cueSettings.map { setting -> [String: Any] in
                            var dict: [String: Any] = [
                                "cue_id": setting.cue.id,
                                "cue_name": setting.cue.name,
                                "trigger_type": setting.triggerType.rawValue
                            ]
                            if setting.triggerType == .minute, let m = setting.minute { dict["minute"] = m }
                            return dict
                        }
                        // Include onboarding context if available
                        let onboardingResponses = OnboardingResponseCollector.shared.responses
                        if !onboardingResponses.isEmpty {
                            params["onboarding_goals"] = onboardingResponses.goals
                            params["onboarding_feeling"] = onboardingResponses.currentFeeling
                            params["onboarding_experience"] = onboardingResponses.experience
                            params["onboarding_guidance_style"] = onboardingResponses.guidanceStyle ?? ""
                        }
                        AnalyticsManager.shared.logEvent("ai_interaction", parameters: params)
                        
                        // Mark that the user has created their first AI meditation (used for subscription gating)
                        if SharedUserStorage.retrieve(forKey: .hasCreatedFirstAIMeditation, as: Bool.self) != true {
                            SharedUserStorage.save(value: true, forKey: .hasCreatedFirstAIMeditation)
                            logger.aiChat("🧠 AI_DEBUG FIRST_AI_MEDITATION_CREATED marked hasCreatedFirstAIMeditation=true")
                        }
                        
                        logger.eventMessage("🤖 AI_MEDITATION_UI: === GENERATION COMPLETED SUCCESSFULLY ===")
                        logger.eventMessage("🤖 AI_MEDITATION_UI: Result summary: \(timerResponse.meditationConfiguration.duration)min, \(timerResponse.meditationConfiguration.backgroundSound.name), \(timerResponse.meditationConfiguration.cueSettings.count) cues")
                        
                    case .conversationalResponse(let response):
                        logger.eventMessage("🤖 AI_MEDITATION_UI: Updating UI with conversational response")
                        logger.aiChat("🧠 AI_DEBUG FLOW response type=conversation id=\(strongSelf.lastRequestContext?.request_id ?? ctx.request_id)")
                        let preview = String(response.prefix(280))
                        logger.aiChat("🧠 AI_DEBUG RESP id=\(strongSelf.lastRequestContext?.request_id ?? ctx.request_id) type=conversation text=\(preview)")
                        strongSelf.conversationalResponse = response
                        // Capture any concrete idea embedded in the response for the next Yes
                        strongSelf.lastSuggestedIdea = strongSelf.extractIdea(from: response)
                        
                        // Unified analytics: response (conversation) with original request inline
                        var cparams: [String: Any] = strongSelf.baseParams(from: strongSelf.lastRequestContext ?? ctx)
                        cparams["stage"] = "response"
                        cparams["response_type"] = "conversation"
                        cparams["response_text"] = response
                        cparams["response_length"] = response.count
                        AnalyticsManager.shared.logEvent("ai_interaction", parameters: cparams)
                        
                        logger.eventMessage("🤖 AI_MEDITATION_UI: === CONVERSATIONAL RESPONSE COMPLETED ===")
                    }
                }
            } catch {
                guard let strongSelf = self else { return }
                await MainActor.run {
                    logger.errorMessage("🤖 AI_MEDITATION_UI: === GENERATION FAILED ===")
                    logger.errorMessage("🤖 AI_MEDITATION_UI: Error: \(error)")
                    logger.errorMessage("🤖 AI_MEDITATION_UI: Error type: \(type(of: error))")
                    
                    let friendlyError = strongSelf.friendlyErrorMessage(from: error)
                    logger.eventMessage("🤖 AI_MEDITATION_UI: Friendly error message: '\(friendlyError)'")
                    logger.aiChatError("🧠 AI_DEBUG FLOW error id=\(strongSelf.lastRequestContext?.request_id ?? ctx.request_id) msg=\(friendlyError)")
                    
                    strongSelf.error = friendlyError
                    logger.aiChatError("🧠 AI_DEBUG ERROR id=\(strongSelf.lastRequestContext?.request_id ?? ctx.request_id) domain=\((error as NSError).domain) code=\((error as NSError).code) msg=\(friendlyError)")
                    strongSelf.isLoading = false
                    
                    // Unified analytics: error, include original request inline
                    var eparams: [String: Any] = strongSelf.baseParams(from: strongSelf.lastRequestContext ?? ctx)
                    eparams["stage"] = "error"
                    eparams["error_message"] = error.localizedDescription
                    eparams["error_domain"] = (error as NSError).domain
                    eparams["error_code"] = (error as NSError).code
                    AnalyticsManager.shared.logEvent("ai_interaction", parameters: eparams)
                }
            }
        }
    }
    
    func startMeditation(with response: AITimerResponse, navigationCoordinator: NavigationCoordinator) {
        // Do not mark onboarding completion on direct play. Only user prompt completes onboarding.
        logger.eventMessage("🤖 AI_MEDITATION_UI: === STARTING AI-GENERATED MEDITATION ===")
        logger.eventMessage("🤖 AI_MEDITATION_UI: Meditation details:")
        logger.eventMessage("🤖 AI_MEDITATION_UI: - Title: \(response.meditationConfiguration.title ?? "No title")")
        logger.eventMessage("🤖 AI_MEDITATION_UI: - Duration: \(response.meditationConfiguration.duration) minutes")
        logger.eventMessage("🤖 AI_MEDITATION_UI: - Background Sound: \(response.meditationConfiguration.backgroundSound.name)")
        logger.eventMessage("🤖 AI_MEDITATION_UI: - Cues: \(response.meditationConfiguration.cueSettings.count) cue(s)")
        logger.eventMessage("🤖 AI_MEDITATION_UI: - Deep Link: \(response.deepLink.absoluteString)")
        
        // Unified analytics: start, include original request inline when available
        var sparams: [String: Any]
        if let ctx = self.lastRequestContext {
            sparams = baseParams(from: ctx)
        } else {
            sparams = [
                "request_id": UUID().uuidString,
                "user_prompt": "",
                "prompt_length": 0,
                "request_type": "meditation",
                "history_len": 0
            ]
        }
        sparams["stage"] = "start"
        sparams["start_method"] = "customize"
        // Ensure JSON-safe string for meditation_id
        sparams["meditation_id"] = String(describing: response.meditationConfiguration.id)
        sparams["duration_min"] = response.meditationConfiguration.duration
        sparams["background_sound"] = response.meditationConfiguration.backgroundSound.name
        sparams["cue_count"] = response.meditationConfiguration.cueSettings.count
        sparams["title"] = response.meditationConfiguration.title ?? "Unknown"
        AnalyticsManager.shared.logEvent("ai_interaction", parameters: sparams)
        
        // Ensure catalogs are loaded to resolve binaural beat, then navigate
        // Asset download now happens on the Player screen for unified loading experience
        // Skip network fetches if offline or if catalogs are already loaded from cache
        let group = DispatchGroup()
        let isOnline = NetworkMonitor.shared.isConnected
        if isOnline && (CatalogsManager.shared.sounds.isEmpty || CatalogsManager.shared.cues.isEmpty || CatalogsManager.shared.beats.isEmpty) {
            group.enter()
            CatalogsManager.shared.fetchCatalogs(triggerContext: "AIRequestManager|preload for AI") { _ in group.leave() }
        }
        group.notify(queue: .main) {
            var appliedConfig = response.meditationConfiguration
            var fallbackBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
            if let components = URLComponents(url: response.deepLink, resolvingAgainstBaseURL: false),
               let rebuilt = MeditationConfiguration(queryItems: components.queryItems ?? []) {
                appliedConfig = rebuilt
                // Fallback: pull bb from deep link if config didn't parse it (legacy)
                if let bbId = components.queryItems?.first(where: { $0.name == "bb" })?.value,
                   let beat = CatalogsManager.shared.beats.first(where: { $0.id == bbId }) {
                    fallbackBeat = beat
                }
                logger.aiChat("🧠 AI_DEBUG [BB]: rebuilt_config bb=\(appliedConfig.binauralBeat?.name ?? fallbackBeat.name)")
            } else {
                logger.aiChat("🧠 AI_DEBUG [BB]: rebuild_config_failed using original config")
            }
            let resolvedBeat = appliedConfig.binauralBeat ?? (fallbackBeat.id != "None" ? fallbackBeat : BinauralBeat(id: "None", name: "None", url: "", description: nil))
            logger.eventMessage("🤖 AI_MEDITATION_UI: Navigating to Player - assets will be prepared on Player screen...")
            // Build timer config with cue URLs resolved for user's voice
            let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
            var timerConfig = appliedConfig.toTimerSessionConfig(voiceId: voiceId, isDeepLinked: true, description: response.description)
            // Override binaural beat if we have a resolved one from fallback
            if resolvedBeat.id != "None" {
                timerConfig = TimerSessionConfig(
                    minutes: timerConfig.minutes,
                    playbackDurationSeconds: timerConfig.playbackDurationSeconds,
                    backgroundSound: timerConfig.backgroundSound,
                    binauralBeat: resolvedBeat,
                    cueSettings: timerConfig.cueSettings,
                    isDeepLinked: timerConfig.isDeepLinked,
                    title: timerConfig.title,
                    description: timerConfig.description
                )
            }
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
            GeneralBackgroundMusicController.shared.fadeOutForPractice()
            navigationCoordinator.currentView = .main
            navigationCoordinator.showTimerPlayerSheet(timerConfig: timerConfig)
            logger.eventMessage("🤖 AI_MEDITATION_UI: Clearing UI result state")
            self.clearResult()
            logger.eventMessage("🤖 AI_MEDITATION_UI: === MEDITATION START COMPLETED ===")
        }
    }
    
    func clearResult() {
        generatedMeditation = nil
        conversationalResponse = nil
        showResult = false
        error = nil
    }
    
    func refreshRules() async {
        // No-op: rely on cached configuration via generateMeditation path
    }
    
    private func friendlyErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        
        logger.eventMessage("🤖 AI_MEDITATION_UI: Processing error - Domain: \(nsError.domain), Code: \(nsError.code)")
        logger.eventMessage("🤖 AI_MEDITATION_UI: Error description: \(nsError.localizedDescription)")
        
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection. Please check your network and try again."
        case NSURLErrorTimedOut:
            return "Request timed out. Please try again."
        case 401:
            if (nsError.domain == "AIService" || nsError.domain == "AIRequestService") && nsError.localizedDescription.contains("quota") {
                return "AI service quota exceeded. Please try again later or contact support."
            }
            return "Authentication error. Please try again."
        case 429:
            if nsError.domain == "AIService" || nsError.domain == "AIRequestService" {
                return nsError.localizedDescription
            }
            return "Too many requests. Please wait a moment and try again."
        case 500...599:
            return "AI service is temporarily unavailable. Please try again later."
        default:
            if nsError.domain == "AIService" || nsError.domain == "AIRequestService" {
                return nsError.localizedDescription
            }
            return "Unable to generate meditation. Please try again."
        }
    }
    
    // MARK: - Explore Guidance Helpers

    /// Matches server `extractThemesFromText` morning signals so clock `sleep` is not sent when the user asks for morning practice (e.g. at night local time).
    nonisolated private static func promptSignalsExplicitMorning(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        if lower.contains("morning") || lower.contains("moning") { return true }
        if lower.contains("wake up") || lower.contains("wake-up") { return true }
        if lower.contains("sunrise") { return true }
        if lower.contains("energize") || lower.contains("energise") { return true }
        if lower.contains("start my day") || lower.contains("start the day") { return true }
        return false
    }
    
    /// Checks if the user explicitly requested a pre-recorded session
    /// This bypasses the normal Path-first logic for testing purposes
    /// nonisolated to allow calling from async contexts
    nonisolated private func isExplicitPreRecordedRequest(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        let triggers = ["pre-recorded", "prerecorded", "pre recorded"]
        let isExplicit = triggers.contains { lower.contains($0) }
        return isExplicit
    }

}

// MARK: - Quick Intent Helpers
extension AIRequestManager {
    // Minimal classifier: meditation | explain | conversation
    // Enhanced duration detection and explain override
    fileprivate func classifyRequestType(_ prompt: String) -> String {
        let lower = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Explain/benefit overrides (never misclassify Q&A as meditation)
        let isQuestion = lower.hasSuffix("?")
        let explainStarts = ["what is","how do","how does","why","explain","tell me about"]
        let benefitSignals = ["will this","is this","does this","can this","will it","is it","does it","help","benefit","good for","work for","reduce","improve","anxiety","stress","sleep"]
        if isQuestion && (explainStarts.contains { lower.hasPrefix($0) } || benefitSignals.contains { lower.contains($0) }) {
            return "explain"
        }

        // 2) Meditation intent signals
        let hasDuration = hasDurationSignal(lower)
        let verbs = ["create","make","build","craft","generate","start","do","guide","run","begin"]
        let hasVerb = verbs.contains { lower.contains($0) }
        let sessionWords = ["session","practice","timer","meditation","meditate"]
        let hasSession = sessionWords.contains { lower.contains($0) }

        if hasDuration && (hasSession || hasVerb) { return "meditation" }

        // Allow very short duration-only commands (e.g., "15 minutes") to count as meditation
        if hasDuration && lower.count <= 24 { return "meditation" }

        // 3) Fallbacks
        if hasVerb && hasSession { return "meditation" }
        return "conversation"
    }

    /// Detects a wide variety of natural-language duration expressions
    fileprivate func hasDurationSignal(_ s: String) -> Bool {
        let lower = s.lowercased()
        let fullRange = NSRange(location: 0, length: lower.utf16.count)

        func match(_ pattern: String) -> Bool {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
            return re.firstMatch(in: lower, options: [], range: fullRange) != nil
        }

        // hh:mm (e.g., 1:30, 00:20)
        if match(#"\b([0-1]?\d|2[0-3]):[0-5]\d\b"#) { return true }

        // Mixed forms: 1h30, 1 h 30 m, 1hr 30min, 1.5h, 90min, 10m
        if match(#"\b\d+(?:\.\d+)?\s*h(?:\s*\d+\s*m(?:in)?s?)?\b"#) { return true }
        if match(#"\b\d+\s*m(?:in)?s?\b"#) { return true }

        // Hyphen/space variants and symbols: 10-minute, 10‑min, 10 min., 10′ / 10'
        if match(#"\b\d{1,3}[\s\-]*m(?:in(?:ute)?s?)?\.?\b"#) { return true }
        if match(#"\b\d{1,3}\s*['′]\b"#) { return true }

        // Hours: 1h, 1 hr, 1 hour, 2 hrs, 2 hours
        if match(#"\b\d{1,2}\s*h(?:r)?s?\b|\b\d{1,2}\s*hours?\b"#) { return true }

        // Ranges: 5–10 min, 5-10 minutes, 5 to 10 mins, 1-2h
        if match(#"\b\d{1,3}\s*(?:-|–|—|to)\s*\d{1,3}\s*(?:m|min|mins|minutes?|h|hrs?|hours?)\b"#) { return true }

        // Approximate: ~10min, approx 10 minutes, about 10 m, around 1h
        if match(#"(?:~|about|around|approx(?:\.|imately)?)\s*\d{1,3}\s*(?:m|min|mins|minutes?|h|hrs?|hours?)\b"#) { return true }

        // Spelled-out numbers + minutes
        if match(#"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty)(?:[\-\s](one|two|three|four|five|six|seven|eight|nine))?\s*(minutes?|mins?)\b"#) { return true }

        // Half / quarter hour
        if match(#"\b(half\s+an\s+hour|half\-hour|half hour|½\s*hour)\b"#) { return true }
        if match(#"\b(quarter\s+of\s+an\s+hour|quarter\-hour|quarter hour)\b"#) { return true }

        // A couple of minutes
        if match(#"\b(a\s+couple\s+of\s+minutes|couple\s+of\s+minutes)\b"#) { return true }

        // Lightly implied phrasing: for 10 minutes, a 10‑minute session, quick 10 min
        if match(#"\bfor\s+\d{1,3}\s*(?:m|min|mins|minutes?)\b"#) { return true }
        if match(#"\ba\s*\d{1,3}[\-\s]*(?:m|min|mins|minute|minutes)\b"#) { return true }

        return false
    }

    fileprivate func baseParams(from ctx: AIRequestContext) -> [String: Any] {
        let p: [String: Any] = [
            "request_id": ctx.request_id,
            "user_prompt": ctx.user_prompt,
            "prompt_length": ctx.prompt_length,
            "request_type": ctx.request_type,
            "history_len": ctx.history_len
        ]
        return p
    }

    /// Returns a rotated alternative suggestion and CTA, avoiding the immediate previous choice.
    fileprivate func nextAlternativeSuggestion() -> String {
        // Pick a random index different from the last used
        var newIndex: Int
        if alternativeSuggestions.isEmpty { return "No problem. Would you like me to create a short meditation now, or prefer another idea?" }
        repeat {
            newIndex = Int.random(in: 0..<alternativeSuggestions.count)
        } while lastAlternativeSuggestionIndex != nil && newIndex == lastAlternativeSuggestionIndex
        lastAlternativeSuggestionIndex = newIndex
        let idea = alternativeSuggestions[newIndex]
        // Save the concrete idea so a subsequent "Yes" will create this exact session
        self.lastSuggestedIdea = idea
        return "No problem. \(idea) Would you like me to create it now, or prefer another idea?"
    }

    /// Attempts to extract a concrete idea string from a conversational response
    /// Examples:
    /// - "Try this: 12 min mantra focus...\nWant me to create it now?" → returns "12 min mantra focus..."
    /// - "No problem. How about a 13 min retrospection ...? Would you like me to create it now ..." → returns "13 min retrospection ..."
    fileprivate func extractIdea(from response: String) -> String? {
        let s = response.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pattern 1: Try this: <idea> (until newline or question)
        if let range = s.range(of: "Try this:") {
            let after = s[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let stopChars: [Character] = ["\n", "?", "\r"]
            if let stop = after.firstIndex(where: { stopChars.contains($0) }) {
                return String(after[..<stop]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return after
        }
        // Pattern 1b: Normalize extend/lengthen + minutes → tag
        do {
            let l = s.lowercased()
            if let match = l.range(of: #"(extend|lengthen|make).{0,40}?(\d{1,3})\s*(m|min|minutes)"#, options: .regularExpression) {
                let slice = String(l[match])
                if let re = try? NSRegularExpression(pattern: #"(\d{1,3})\s*(m|min|minutes)"#, options: .caseInsensitive),
                   let r = re.firstMatch(in: slice, options: [], range: NSRange(location: 0, length: (slice as NSString).length)),
                   r.numberOfRanges >= 2,
                   let r1 = Range(r.range(at: 1), in: slice) {
                    let by = String(slice[r1])
                    return "extend_by:\(by)"
                }
            }
            if let match2 = l.range(of: #"to\s*(\d{1,3})\s*(m|min|minutes)"#, options: .regularExpression) {
                let slice = String(l[match2])
                if let re = try? NSRegularExpression(pattern: #"(\d{1,3})\s*(m|min|minutes)"#, options: .caseInsensitive),
                   let r = re.firstMatch(in: slice, options: [], range: NSRange(location: 0, length: (slice as NSString).length)),
                   r.numberOfRanges >= 2,
                   let r1 = Range(r.range(at: 1), in: slice) {
                    let to = String(slice[r1])
                    return "extend_to:\(to)"
                }
            }
        }
        // Pattern 2: How about a ... ?
        if let range = s.lowercased().range(of: "how about a ") {
            let start = s.index(s.startIndex, offsetBy: s.distance(from: s.startIndex, to: range.lowerBound) + "how about a ".count)
            let after = s[start...]
            if let q = after.firstIndex(of: "?") {
                return String(after[..<q]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Fallback: up to CTA lead-in
            if let w = after.range(of: "Would you like")?.lowerBound {
                return String(after[..<w]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(after).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    /// Returns the duration for given cue id (matches server catalog mapping)
    private func cueDuration(for cueId: String) -> Int {
        switch cueId {
        case "PB": return 2
        case "BS_FRAC", "BS_FRAC_UP", "BS_FRAC_DOWN": return 7
        case "BS1": return 1
        case "BS2": return 2
        case "BS3": return 3
        case "BS4": return 4
        case "BS5": return 5
        case "BS6": return 6
        case "BS7": return 7
        case "BS8": return 8
        case "BS9": return 9
        case "BS10": return 10
        case "BS": return 3
        case "INT_FRAC", "GB": return 1
        case "MV_KM_FRAC", "MV_GR_FRAC", "EV_KM_FRAC", "EV_GR_FRAC": return 4
        case let id where id.hasPrefix("IM"):
            return Int(id.dropFirst(2)) ?? 3
        case let id where id.hasPrefix("NF"):
            return Int(id.dropFirst(2)) ?? 3
        default: return 2
        }
    }

    // MARK: - Intent Parsing & Application Helpers

    private func extractMinute(from text: String) -> Int? {
        if let range = text.range(of: "minute ") {
            let tail = text[range.upperBound...]
            if let n = Int(tail.split(separator: " ").first ?? "") { return n }
        }
        if let range = text.range(of: " at ") {
            let tail = text[range.upperBound...]
            if let n = Int(tail.split(separator: " ").first ?? "") { return n }
        }
        // Also capture tags like extend_by:NN or extend_to:NN
        let l = text.lowercased()
        if let r = l.range(of: #"extend_by:(\d{1,3})"#, options: .regularExpression) {
            let slice = String(l[r])
            if let num = slice.split(separator: ":").last, let v = Int(num) { return v }
        }
        if let r2 = l.range(of: #"extend_to:(\d{1,3})"#, options: .regularExpression) {
            let slice = String(l[r2])
            if let num = slice.split(separator: ":").last, let v = Int(num) { return v }
        }
        return nil
    }

    // MARK: - Tagged idea helpers
    private func parseTaggedValue(prefix: String, in text: String) -> Int? {
        let l = text.lowercased()
        guard let range = l.range(of: prefix) else { return nil }
        let after = l[range.upperBound...]
        var digits: String = ""
        for ch in after {
            if ch.isNumber { digits.append(ch) } else { break }
        }
        if let value = Int(digits), value > 0 { return value }
        return nil
    }

    private func extractFirstNumber(in s: String) -> Int? {
        var digits: String = ""
        for ch in s {
            if ch.isNumber { digits.append(ch) } else if !digits.isEmpty { break }
        }
        if let value = Int(digits), value > 0 { return value }
        return nil
    }

    // Quick-intent helpers removed
}

extension AIRequestManager {
    /// Ensures background sound, binaural beats, and all cue audio files are cached before playback.
    func prepareAssetsIfNeeded(for config: MeditationConfiguration) async {
        // Build list of required remote URL strings
        var urlStrings: [String] = []
        if !config.backgroundSound.url.isEmpty {
            urlStrings.append(config.backgroundSound.url)
        }
        let bbURL: String = {
            let mirror = Mirror(reflecting: config)
            if let beatChild = mirror.children.first(where: { $0.label == "binauralBeat" }) {
                let beatMirror = Mirror(reflecting: beatChild.value)
                if let url = beatMirror.children.first(where: { $0.label == "url" })?.value as? String {
                    return url
                }
            }
            return ""
        }()
        if !bbURL.isEmpty {
            urlStrings.append(bbURL)
        }
        for setting in config.cueSettings {
            if !setting.cue.url.isEmpty {
                urlStrings.append(setting.cue.url)
            }
        }
        // Deduplicate
        let unique = Array(Set(urlStrings))
        guard !unique.isEmpty else { return }
        
        isPreparingPlayback = true
        preparationProgress = 0.0
        
        let total = Double(unique.count)
        var completed = 0.0
        
        await withTaskGroup(of: Void.self) { group in
            for urlString in unique {
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        FileManagerHelper.shared.ensureLocalFile(forRemoteURLString: urlString, setDownloading: { _ in }, completion: { _ in
                            continuation.resume()
                        })
                    }
                    await MainActor.run {
                        completed += 1.0
                        self.preparationProgress = min(1.0, completed / total)
                    }
                }
            }
            await group.waitForAll()
        }
        await MainActor.run {
            isPreparingPlayback = false
            preparationProgress = 1.0
        }
    }
} 