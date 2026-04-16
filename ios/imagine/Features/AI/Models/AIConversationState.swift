import SwiftUI

// MARK: - Conversation State Management

@MainActor
class AIConversationState: ObservableObject {
    @Published var conversation: [ChatMessage] = [] {
        didSet { persistConversation() }
    }
    @Published var userInput = ""
    @Published var latestAIMessageId: UUID?
    @Published var latestUserMessageId: UUID?
    @Published var isTyping: Bool = false
    @Published var isTypingComplete: Bool = false
    @Published var visibleButtons: Set<String> = []
    
    private let storageKey: UserStorageKey = .aiChatHistory
    private var hasLoadedFromStorage = false
    private let maxPersistedMessages = 30
    
    func addUserMessage(_ content: String) {
        let message = ChatMessage(content: content, isUser: true)
        conversation.append(message)
        latestUserMessageId = message.id
    }
    
    /// Adds a meditation message with optional acknowledgment text displayed above the card
    func addAIMessage(meditation: AITimerResponse, acknowledgment: String = "") {
        let message = ChatMessage(content: acknowledgment, isUser: false, meditation: meditation)
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
    }
    
    func addAIMessage(text: String) {
        let message = ChatMessage(content: text, isUser: false)
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
    }

    /// Adds a message and returns its id, for replacement flows
    func addAIMessageReturningId(text: String) -> UUID {
        let message = ChatMessage(content: text, isUser: false)
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        return message.id
    }
    
    /// Adds a message with heart rate data and returns its id (legacy)
    func addAIMessageReturningId(text: String, heartRateData: ChatHeartRateData?) -> UUID {
        let message = ChatMessage(content: text, isUser: false, heartRateData: heartRateData)
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        return message.id
    }
    
    /// Adds a post-practice message with structured content sections
    func addPostPracticeMessage(content: ChatPostPracticeContent) -> UUID {
        let message = ChatMessage(
            content: content.combinedText,
            isUser: false,
            postPracticeContent: content,
            heartRateData: content.heartRateGraphData
        )
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        logger.aiChat("📋 [POST_PRACTICE] addPostPracticeMessage: Created new bubble=\(message.id) content_len=\(content.combinedText.count) isTyping=true")
        return message.id
    }
    
    /// Replace post-practice message content (for polish upgrade)
    /// This does NOT restart typing animation - it updates content silently
    func replacePostPracticeMessage(id: UUID, withContent content: ChatPostPracticeContent) -> UUID? {
        if let idx = conversation.firstIndex(where: { $0.id == id && !$0.isUser }) {
            // Keep the same ID to avoid re-triggering typing animation
            let existingId = conversation[idx].id
            let replaced = ChatMessage(
                id: existingId,  // Preserve original ID
                content: content.combinedText,
                isUser: false,
                postPracticeContent: content,
                heartRateData: content.heartRateGraphData
            )
            conversation[idx] = replaced
            // Do NOT set latestAIMessageId or isTyping - this is a silent content update
            logger.aiChat("📋 [POST_PRACTICE] replacePostPracticeMessage: Updated content in place for bubble=\(existingId)")
            return existingId
        }
        logger.aiChat("📋 [POST_PRACTICE] replacePostPracticeMessage: Could not find bubble=\(id) to replace")
        return nil
    }
    
    /// Adds a path recommendation message with text and path step card
    @discardableResult
    func addPathRecommendation(text: String, pathStep: PathStep) -> UUID {
        let message = ChatMessage(
            pathStep: pathStep,
            recommendationText: text
        )
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        return message.id
    }
    
    /// Adds an explore recommendation message with text and audio file card
    @discardableResult
    func addExploreRecommendation(text: String, audioFile: AudioFile) -> UUID {
        let message = ChatMessage(
            exploreSession: audioFile,
            recommendationText: text
        )
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        logger.aiChat("🧠 AI_DEBUG [EXPLORE] addExploreRecommendation id=\(message.id) session=\(audioFile.id) title=\(audioFile.title)")
        return message.id
    }
    
    /// Adds one Sensei recommendation (path, explore, or custom) with journey metadata.
    @discardableResult
    func addSingleRecommendation(_ recommendation: SingleRecommendation) -> UUID {
        let message = ChatMessage(singleRecommendation: recommendation)
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        logger.aiChat("🧠 AI_DEBUG [REC] addSingleRecommendation id=\(message.id) type=\(recommendation.item.type.analyticsType)")
        return message.id
    }
    
    /// Legacy dual-card message (primary + optional secondary).
    @available(*, deprecated, message: "Use addSingleRecommendation(_:).")
    @discardableResult
    func addDualRecommendation(_ recommendation: DualRecommendation) -> UUID {
        let message = ChatMessage(
            content: recommendation.primary.introMessage,
            isUser: false,
            singleRecommendation: nil,
            dualRecommendation: recommendation
        )
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        logger.aiChat("🧠 AI_DEBUG [DUAL_REC] addDualRecommendation id=\(message.id) primary=\(recommendation.primary.type.analyticsType) secondary=\(recommendation.secondary?.type.analyticsType ?? "none")")
        return message.id
    }
    
    /// Adds a post-session prompt message asking if the user wants to meditate more
    @discardableResult
    func addPostSessionPrompt(question: String, prompt: PostSessionPrompt) -> UUID {
        let message = ChatMessage(postSessionPrompt: prompt, question: question)
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        logger.aiChat("🤔 [POST_SESSION_PROMPT] addPostSessionPrompt id=\(message.id) isPathComplete=\(prompt.isPathComplete)")
        return message.id
    }
    
    /// Marks a post-session prompt as responded so buttons stay in their final state across re-renders.
    func markPostSessionPromptResponded(respondedYes: Bool) {
        // Find the most recent prompt message and update it
        if let idx = conversation.lastIndex(where: { $0.postSessionPrompt != nil }) {
            let old = conversation[idx]
            guard var prompt = old.postSessionPrompt, !prompt.responded else { return }
            prompt.responded = true
            prompt.respondedYes = respondedYes
            let updated = ChatMessage(
                id: old.id,
                content: old.content,
                isUser: false,
                postSessionPrompt: prompt,
                timestamp: old.timestamp
            )
            conversation[idx] = updated
            logger.aiChat("🤔 [POST_SESSION_PROMPT] Marked prompt as responded yes=\(respondedYes) id=\(old.id)")
        }
    }

    @discardableResult
    func addSenseiMessage(_ message: SenseiOnboardingMessage) -> UUID {
        let chatMessage = ChatMessage(message: message)
        conversation.append(chatMessage)
        latestAIMessageId = chatMessage.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        return chatMessage.id
    }
    
    @discardableResult
    func addSenseiQuestion(_ question: SenseiOnboardingQuestion) -> UUID {
        let message = ChatMessage(question: question)
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        return message.id
    }
    
    @discardableResult
    func addSenseiPromptEducation(_ promptEducation: SenseiOnboardingPromptEducation) -> UUID {
        let message = ChatMessage(promptEducation: promptEducation)
        conversation.append(message)
        latestAIMessageId = message.id
        isTyping = true
        isTypingComplete = false
        visibleButtons.removeAll()
        return message.id
    }

    /// Replace the content of an existing AI message by id. Returns the new message id if replaced.
    func replaceAIMessageAndReturnId(id: UUID, withText newText: String) -> UUID? {
        if let idx = conversation.firstIndex(where: { $0.id == id && !$0.isUser }) {
            let old = conversation[idx]
            let replaced = ChatMessage(content: newText, isUser: false, meditation: old.meditation)
            conversation.remove(at: idx)
            conversation.insert(replaced, at: idx)
            latestAIMessageId = replaced.id
            isTyping = true
            isTypingComplete = false
            visibleButtons.removeAll()
            return replaced.id
        }
        return nil
    }
    
    func handleTypingComplete() {
        latestAIMessageId = nil
        isTyping = false
        isTypingComplete = true
    }
    
    func clearInput() {
        userInput = ""
    }
    
    func resetButtonVisibility() {
        visibleButtons.removeAll()
    }

    func removeMessage(withId id: UUID) {
        if let index = conversation.firstIndex(where: { $0.id == id }) {
            conversation.remove(at: index)
            if latestAIMessageId == id {
                latestAIMessageId = conversation.last(where: { !$0.isUser })?.id
            }
            if conversation.isEmpty {
                isTyping = false
                isTypingComplete = true
            }
        }
    }
    
    func showButton(_ buttonId: String) {
        visibleButtons.insert(buttonId)
    }
    
    // MARK: - Conversation Context Management
    
    /// Get recent conversation messages for API context
    /// Limits messages to prevent token overflow while maintaining context
    func getConversationContext(limit: Int = 6) -> [ChatMessage] {
        return Array(conversation.suffix(limit))
    }
    
    /// Clear conversation for "clear chat" functionality
    func clearConversation() {
        let previousCount = conversation.count
        logger.aiChat("🧠 AI_DEBUG [CHAT_CLEAR] Clearing conversation (had \(previousCount) messages)")
        
        conversation.removeAll()
        latestAIMessageId = nil
        latestUserMessageId = nil
        isTyping = false
        isTypingComplete = false
        visibleButtons.removeAll()
        persistConversation()
        
        logger.aiChat("🧠 AI_DEBUG [CHAT_CLEAR] Conversation cleared and persisted")
    }

    // MARK: - Persistence
    /// Load persisted conversation once per lifecycle
    func loadIfNeeded() {
        guard !hasLoadedFromStorage else { return }
        hasLoadedFromStorage = true
        
        // Try to get raw data first to diagnose issues
        guard let data = UserDefaults.standard.data(forKey: storageKey.rawValue) else {
            logger.aiChat("🧠 AI_DEBUG [CHAT_LOAD] No chat data found in storage - starting fresh")
            return
        }
        
        logger.aiChat("🧠 AI_DEBUG [CHAT_LOAD] Found chat data, size=\(data.count) bytes")
        
        // First try standard array decoding
        do {
            let saved = try JSONDecoder().decode([ChatMessage].self, from: data)
            logger.aiChat("🧠 AI_DEBUG [CHAT_LOAD] Successfully decoded \(saved.count) messages")
            
            // Filter out any empty placeholder AI bubbles and cap size
            let filtered = saved.filter { $0.isUser || !$0.content.isEmpty || $0.meditation != nil || $0.senseiMessage != nil || $0.senseiQuestion != nil || $0.senseiPromptEducation != nil || $0.postPracticeContent != nil || $0.pathRecommendation != nil || $0.exploreRecommendation != nil || $0.singleRecommendation != nil || $0.dualRecommendation != nil || $0.postSessionPrompt != nil }
            conversation = Array(filtered.suffix(maxPersistedMessages))
            
            // Ensure no typing animation is triggered for restored messages
            latestAIMessageId = nil
            isTyping = false
            isTypingComplete = true
            visibleButtons.removeAll()
            
            logger.aiChat("🧠 AI_DEBUG [CHAT_LOAD] Restored \(conversation.count) messages after filtering")
            
        } catch {
            // Standard decoding failed - log the error and try resilient recovery
            logger.aiChat("🧠 AI_DEBUG [CHAT_LOAD] ❌ DECODE FAILED: \(error.localizedDescription)")
            print("❌ [AIConversationState] Chat decode error: \(error)")
            
            // Attempt resilient recovery - try to decode individual messages
            let recoveredMessages = recoverMessagesFromData(data)
            if !recoveredMessages.isEmpty {
                logger.aiChat("🧠 AI_DEBUG [CHAT_LOAD] Recovered \(recoveredMessages.count) messages via resilient decoding")
                conversation = Array(recoveredMessages.suffix(maxPersistedMessages))
                latestAIMessageId = nil
                isTyping = false
                isTypingComplete = true
                visibleButtons.removeAll()
                
                // Re-persist the cleaned conversation to fix corrupted data
                persistConversation()
                logger.aiChat("🧠 AI_DEBUG [CHAT_LOAD] Re-persisted cleaned conversation")
            } else {
                logger.aiChat("🧠 AI_DEBUG [CHAT_LOAD] ❌ Resilient recovery also failed - starting fresh")
            }
        }
    }
    
    /// Attempts to recover individual messages when array decoding fails
    /// This handles cases where a single corrupted message would otherwise lose the entire chat
    private func recoverMessagesFromData(_ data: Data) -> [ChatMessage] {
        // Try to decode as an array of JSON objects first
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            logger.aiChat("🧠 AI_DEBUG [CHAT_RECOVERY] Cannot parse as JSON array")
            return []
        }
        
        logger.aiChat("🧠 AI_DEBUG [CHAT_RECOVERY] Found \(jsonArray.count) JSON objects, attempting individual recovery")
        
        var recovered: [ChatMessage] = []
        let decoder = JSONDecoder()
        
        for (index, jsonObject) in jsonArray.enumerated() {
            do {
                let messageData = try JSONSerialization.data(withJSONObject: jsonObject)
                let message = try decoder.decode(ChatMessage.self, from: messageData)
                recovered.append(message)
            } catch {
                // Log which message failed but continue with others
                let contentPreview = (jsonObject["content"] as? String)?.prefix(50) ?? "unknown"
                logger.aiChat("🧠 AI_DEBUG [CHAT_RECOVERY] ⚠️ Message \(index) failed: \(error.localizedDescription) - content: '\(contentPreview)...'")
            }
        }
        
        return recovered
    }
    
    /// Persist a trimmed version of the conversation
    private func persistConversation() {
        // SAFETY: Don't overwrite saved data before we've loaded
        // This prevents race conditions where messages are added (e.g., post-practice)
        // before loadIfNeeded() completes, which would overwrite the stored conversation
        guard hasLoadedFromStorage else {
            logger.aiChat("🧠 AI_DEBUG [CHAT_SAVE] ⚠️ Skipping persist - haven't loaded from storage yet (would overwrite existing conversation)")
            return
        }
        
        // Exclude temporary "Thinking..." placeholders (empty AI content without meditation)
        let filtered = conversation.filter { $0.isUser || !$0.content.isEmpty || $0.meditation != nil || $0.senseiMessage != nil || $0.senseiQuestion != nil || $0.senseiPromptEducation != nil || $0.postPracticeContent != nil || $0.pathRecommendation != nil || $0.exploreRecommendation != nil || $0.singleRecommendation != nil || $0.dualRecommendation != nil || $0.postSessionPrompt != nil }
        let trimmed = Array(filtered.suffix(maxPersistedMessages))
        
        // Verify encoding works before saving
        do {
            let data = try JSONEncoder().encode(trimmed)
            UserDefaults.standard.set(data, forKey: storageKey.rawValue)
            logger.aiChat("🧠 AI_DEBUG [CHAT_SAVE] Persisted \(trimmed.count) messages (\(data.count) bytes)")
        } catch {
            logger.aiChat("🧠 AI_DEBUG [CHAT_SAVE] ❌ ENCODE FAILED: \(error.localizedDescription)")
            print("❌ [AIConversationState] Chat encode error: \(error)")
        }
    }
    
    // MARK: - Input Field Typing Animation
    
    nonisolated(unsafe) private var inputTypingTimer: Timer?
    
    /// Animates text into the userInput field character by character
    /// Replaces any existing content with the new text
    func typeIntoInput(_ text: String, completion: (() -> Void)? = nil) {
        // Cancel any existing typing animation
        inputTypingTimer?.invalidate()
        
        // Clear existing input first
        userInput = ""
        
        guard !text.isEmpty else {
            completion?()
            return
        }
        
        var currentIndex = 0
        
        inputTypingTimer = Timer.scheduledTimer(withTimeInterval: AnimationConstants.typingInterval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                if currentIndex < text.count {
                    let index = text.index(text.startIndex, offsetBy: currentIndex)
                    self.userInput += String(text[index])
                    currentIndex += 1
                } else {
                    timer.invalidate()
                    self.inputTypingTimer = nil
                    completion?()
                }
            }
        }
    }
    
    /// Clears input and cancels any typing animation in progress
    func clearInputAnimated() {
        inputTypingTimer?.invalidate()
        inputTypingTimer = nil
        userInput = ""
    }
}