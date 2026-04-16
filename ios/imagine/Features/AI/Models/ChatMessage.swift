import SwiftUI

// MARK: - Heart Rate Data for Chat Messages

/// Heart rate graph data for display in chat
struct ChatHeartRateData: Codable, Equatable {
    let startBPM: Double
    let endBPM: Double
    let samples: [HeartRateSamplePoint]
    /// When non-nil, graph card shows MIN + BPM delta; omitted in persisted legacy messages.
    let minBPM: Double?

    init(startBPM: Double, endBPM: Double, samples: [HeartRateSamplePoint], minBPM: Double? = nil) {
        self.startBPM = startBPM
        self.endBPM = endBPM
        self.samples = samples
        self.minBPM = minBPM
    }

    var changePercent: Double {
        guard startBPM > 0 else { return 0 }
        return ((endBPM - startBPM) / startBPM) * 100
    }
}

// MARK: - Post-Practice Message Content

/// Structured post-practice message content with separate sections
struct ChatPostPracticeContent: Codable, Equatable {
    /// Section 1: Praise for completing the session
    /// Example: "Asaf, beautiful work completing this 5-minute practice."
    let completionPraise: String
    
    /// Section 2: Streak information
    /// Example: "That was day 3 in a row..."
    let streakMessage: String
    
    /// Section 3: Heart rate analysis text (shown after graph)
    /// Example: "Your heart rate eased from 88 to 71 BPM..."
    let heartRateMessage: String?
    
    /// Heart rate graph data (for the visual card)
    let heartRateGraphData: ChatHeartRateData?
    
    // MARK: - Path-specific fields
    
    /// The Path step that was just completed (nil for non-Path sessions)
    let completedPathStep: PathStep?
    
    /// The next recommended Path step (nil if path complete or non-Path session)
    let nextPathStep: PathStep?
    
    /// Whether the entire Path journey is now complete
    let isPathComplete: Bool
    
    /// Convenience check: is this a Path post-practice message?
    var isPathPostPractice: Bool {
        completedPathStep != nil
    }
    
    /// Combined text for typing animation (backward compatibility)
    var combinedText: String {
        [completionPraise, streakMessage, heartRateMessage]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
    
    // MARK: - Initializers
    
    /// Full initializer with all fields
    init(
        completionPraise: String,
        streakMessage: String,
        heartRateMessage: String?,
        heartRateGraphData: ChatHeartRateData?,
        completedPathStep: PathStep? = nil,
        nextPathStep: PathStep? = nil,
        isPathComplete: Bool = false
    ) {
        self.completionPraise = completionPraise
        self.streakMessage = streakMessage
        self.heartRateMessage = heartRateMessage
        self.heartRateGraphData = heartRateGraphData
        self.completedPathStep = completedPathStep
        self.nextPathStep = nextPathStep
        self.isPathComplete = isPathComplete
    }
}

// MARK: - Message Model

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let meditation: AITimerResponse?
    let senseiMessage: SenseiOnboardingMessage?
    let senseiQuestion: SenseiOnboardingQuestion?
    let senseiPromptEducation: SenseiOnboardingPromptEducation?
    
    /// Structured post-practice content (new approach)
    let postPracticeContent: ChatPostPracticeContent?
    
    /// Legacy: Heart rate data (for backward compatibility)
    let heartRateData: ChatHeartRateData?
    
    /// Path step recommendation from Sensei
    let pathRecommendation: PathStep?
    
    /// Explore session recommendation from Sensei (pre-recorded sessions)
    let exploreRecommendation: AudioFile?
    
    /// Current product path: one Sensei recommendation card with journey metadata.
    let singleRecommendation: SingleRecommendation?
    
    /// Legacy persisted transcripts may still contain two-card dual recommendations.
    let dualRecommendation: DualRecommendation?
    
    /// Post-session prompt asking if the user wants to meditate more
    let postSessionPrompt: PostSessionPrompt?
    
    let timestamp: Date
    
    init(
        id: UUID = UUID(),
        content: String,
        isUser: Bool,
        meditation: AITimerResponse? = nil,
        senseiMessage: SenseiOnboardingMessage? = nil,
        senseiQuestion: SenseiOnboardingQuestion? = nil,
        senseiPromptEducation: SenseiOnboardingPromptEducation? = nil,
        postPracticeContent: ChatPostPracticeContent? = nil,
        heartRateData: ChatHeartRateData? = nil,
        pathRecommendation: PathStep? = nil,
        exploreRecommendation: AudioFile? = nil,
        singleRecommendation: SingleRecommendation? = nil,
        dualRecommendation: DualRecommendation? = nil,
        postSessionPrompt: PostSessionPrompt? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.meditation = meditation
        self.senseiMessage = senseiMessage
        self.senseiQuestion = senseiQuestion
        self.senseiPromptEducation = senseiPromptEducation
        self.postPracticeContent = postPracticeContent
        self.heartRateData = heartRateData
        self.pathRecommendation = pathRecommendation
        self.exploreRecommendation = exploreRecommendation
        self.singleRecommendation = singleRecommendation
        self.dualRecommendation = dualRecommendation
        self.postSessionPrompt = postSessionPrompt
        self.timestamp = timestamp
    }
    
    /// Convenience check: is this a post-practice message?
    var isPostPracticeMessage: Bool {
        postPracticeContent != nil
    }
    
    /// Convenience check: is this a path recommendation message?
    var isPathRecommendation: Bool {
        pathRecommendation != nil
    }
    
    /// Convenience check: is this an explore recommendation message?
    var isExploreRecommendation: Bool {
        exploreRecommendation != nil
    }
    
    /// Convenience check: structured Sensei recommendation (single current path or legacy dual).
    var isStructuredSenseiRecommendation: Bool {
        singleRecommendation != nil || dualRecommendation != nil
    }
    
    /// Convenience check: is this a dual recommendation message?
    @available(*, deprecated, renamed: "isStructuredSenseiRecommendation")
    var isDualRecommendation: Bool {
        dualRecommendation != nil
    }
    
    /// Convenience check: is this a post-session prompt message?
    var isPostSessionPrompt: Bool {
        postSessionPrompt != nil
    }
    
    init(message: SenseiOnboardingMessage, id: UUID = UUID(), timestamp: Date = Date()) {
        let text = Self.formattedMessageText(for: message)
        self.init(id: id, content: text, isUser: false, meditation: nil, senseiMessage: message, senseiQuestion: nil, senseiPromptEducation: nil, postPracticeContent: nil, heartRateData: nil, pathRecommendation: nil, exploreRecommendation: nil, singleRecommendation: nil, dualRecommendation: nil, postSessionPrompt: nil, timestamp: timestamp)
    }
    
    init(question: SenseiOnboardingQuestion, id: UUID = UUID(), timestamp: Date = Date()) {
        self.init(id: id, content: question.question, isUser: false, meditation: nil, senseiMessage: nil, senseiQuestion: question, senseiPromptEducation: nil, postPracticeContent: nil, heartRateData: nil, pathRecommendation: nil, exploreRecommendation: nil, singleRecommendation: nil, dualRecommendation: nil, postSessionPrompt: nil, timestamp: timestamp)
    }
    
    init(promptEducation: SenseiOnboardingPromptEducation, id: UUID = UUID(), timestamp: Date = Date()) {
        self.init(id: id, content: promptEducation.preamble, isUser: false, meditation: nil, senseiMessage: nil, senseiQuestion: nil, senseiPromptEducation: promptEducation, postPracticeContent: nil, heartRateData: nil, pathRecommendation: nil, exploreRecommendation: nil, singleRecommendation: nil, dualRecommendation: nil, postSessionPrompt: nil, timestamp: timestamp)
    }
    
    /// Convenience initializer for path recommendation messages
    init(pathStep: PathStep, recommendationText: String, id: UUID = UUID(), timestamp: Date = Date()) {
        self.init(id: id, content: recommendationText, isUser: false, meditation: nil, senseiMessage: nil, senseiQuestion: nil, senseiPromptEducation: nil, postPracticeContent: nil, heartRateData: nil, pathRecommendation: pathStep, exploreRecommendation: nil, singleRecommendation: nil, dualRecommendation: nil, postSessionPrompt: nil, timestamp: timestamp)
    }
    
    /// Convenience initializer for explore recommendation messages
    init(exploreSession: AudioFile, recommendationText: String, id: UUID = UUID(), timestamp: Date = Date()) {
        self.init(id: id, content: recommendationText, isUser: false, meditation: nil, senseiMessage: nil, senseiQuestion: nil, senseiPromptEducation: nil, postPracticeContent: nil, heartRateData: nil, pathRecommendation: nil, exploreRecommendation: exploreSession, singleRecommendation: nil, dualRecommendation: nil, postSessionPrompt: nil, timestamp: timestamp)
    }
    
    /// Convenience initializer for single Sensei recommendation messages.
    init(singleRecommendation: SingleRecommendation, id: UUID = UUID(), timestamp: Date = Date()) {
        self.init(id: id, content: singleRecommendation.item.introMessage, isUser: false, meditation: nil, senseiMessage: nil, senseiQuestion: nil, senseiPromptEducation: nil, postPracticeContent: nil, heartRateData: nil, pathRecommendation: nil, exploreRecommendation: nil, singleRecommendation: singleRecommendation, dualRecommendation: nil, postSessionPrompt: nil, timestamp: timestamp)
    }
    
    /// Convenience initializer for legacy dual recommendation messages.
    @available(*, deprecated, message: "Use init(singleRecommendation:) for new messages.")
    init(dualRecommendation: DualRecommendation, id: UUID = UUID(), timestamp: Date = Date()) {
        self.init(id: id, content: dualRecommendation.primary.introMessage, isUser: false, meditation: nil, senseiMessage: nil, senseiQuestion: nil, senseiPromptEducation: nil, postPracticeContent: nil, heartRateData: nil, pathRecommendation: nil, exploreRecommendation: nil, singleRecommendation: nil, dualRecommendation: dualRecommendation, postSessionPrompt: nil, timestamp: timestamp)
    }
    
    /// Convenience initializer for post-session prompt messages
    init(postSessionPrompt: PostSessionPrompt, question: String, id: UUID = UUID(), timestamp: Date = Date()) {
        self.init(id: id, content: question, isUser: false, meditation: nil, senseiMessage: nil, senseiQuestion: nil, senseiPromptEducation: nil, postPracticeContent: nil, heartRateData: nil, pathRecommendation: nil, exploreRecommendation: nil, singleRecommendation: nil, dualRecommendation: nil, postSessionPrompt: postSessionPrompt, timestamp: timestamp)
    }
    
    private static func formattedMessageText(for message: SenseiOnboardingMessage) -> String {
        var text = ""
        if !message.title.isEmpty {
            text += message.title
            if !message.body.isEmpty {
                text += "\n\n"
            }
        }
        if !message.body.isEmpty {
            text += message.body
        }
        if let caption = message.caption, !caption.isEmpty {
            if !text.isEmpty {
                text += "\n\n"
            }
            text += caption
        }
        return text.isEmpty ? " " : text
    }
}

// MARK: - Unified AI request (history + last-session snapshot)

extension ChatMessage {
    /// Assistant `content` for POST /ai/request, including custom meditations embedded in recommendation cards.
    var aiRequestAssistantContent: String {
        if let meditation {
            return meditation.description
        }
        if let single = singleRecommendation {
            switch single.item.type {
            case .custom(let meditation):
                let intro = single.item.introMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                if intro.isEmpty { return meditation.description }
                return "\(intro)\n\n\(meditation.description)"
            case .path, .explore:
                return content
            }
        }
        if let dual = dualRecommendation {
            var parts: [String] = []
            let pIntro = dual.primary.introMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pIntro.isEmpty { parts.append(pIntro) }
            if case .custom(let m) = dual.primary.type { parts.append(m.description) }
            if let sec = dual.secondary {
                let sIntro = sec.introMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sIntro.isEmpty { parts.append(sIntro) }
                if case .custom(let m) = sec.type { parts.append(m.description) }
            }
            let joined = parts.joined(separator: "\n\n")
            return joined.isEmpty ? content : joined
        }
        return content
    }

    /// Most recent custom meditation in the transcript (chat card or Sensei recommendation), for server snapshot.
    static func lastCustomMeditationSnapshot(in messages: [ChatMessage]) -> AIServerRequestContext.LastMeditationSnapshot? {
        for message in messages.reversed() where !message.isUser {
            if let meditation = message.meditation {
                return snapshot(from: meditation)
            }
            if let single = message.singleRecommendation,
               case .custom(let meditation) = single.item.type {
                return snapshot(from: meditation)
            }
            if let dual = message.dualRecommendation {
                if let secondary = dual.secondary, case .custom(let meditation) = secondary.type {
                    return snapshot(from: meditation)
                }
                if case .custom(let meditation) = dual.primary.type {
                    return snapshot(from: meditation)
                }
            }
        }
        return nil
    }

    private static func snapshot(from meditation: AITimerResponse) -> AIServerRequestContext.LastMeditationSnapshot {
        let config = meditation.meditationConfiguration
        let desc = meditation.description
        let snippet = desc.count > 500 ? String(desc.prefix(500)) : desc
        let trimmedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIServerRequestContext.LastMeditationSnapshot(
            durationMinutes: config.duration,
            title: config.title,
            descriptionSnippet: trimmedSnippet.isEmpty ? nil : trimmedSnippet
        )
    }
}