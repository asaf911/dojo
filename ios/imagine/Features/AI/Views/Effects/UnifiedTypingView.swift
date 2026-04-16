import SwiftUI

// MARK: - Unified Typing View Component

struct UnifiedTypingView: View {
    let content: ContentType
    @Binding var isTyping: Bool
    let conversationCount: Int
    let onComplete: () -> Void
    
    @State private var displayedText = ""
    @State private var currentIndex = 0
    @State private var isComplete = false
    @State private var typingTimer: Timer?
    /// When true, timer callbacks must not call `onComplete` (view was removed mid-animation).
    @State private var typingCancelled = false

    enum ContentType {
        case text(String)
        case meditation(AITimerResponse)
    }
    
    private var fullText: String {
        switch content {
        case .text(let text):
            return text
        case .meditation(let meditation):
            return buildMeditationResponseText(for: meditation)
        }
    }
    
    var body: some View {
        Text(displayedText + (isComplete ? "" : "▋"))
            .nunitoFont(size: 16, style: .medium)
            .foregroundColor(.white)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading) // Minimum height prevents jump when replacing thinking message
            .onAppear {
                startTypingAnimation()
            }
            .onChange(of: displayedText) { oldText, newText in
                // Trigger scroll as text is being typed (every few characters to avoid spam)
                if newText.count > oldText.count && newText.count % 10 == 0 {
                    NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                }
            }
            .onChange(of: isComplete) { oldValue, newValue in
                // Trigger scroll when typing completes
                if newValue && !oldValue {
                    logger.aiChat("🧠 AI_SCROLL: UnifiedTypingView typing completed")
                    NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
                }
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: MessageHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                }
            )
            .onDisappear {
                // Critical: without this, the timer keeps firing after SwiftUI removes the view
                // (e.g. a newer AI message becomes latest), and onComplete can clear conversation typing state.
                typingCancelled = true
                typingTimer?.invalidate()
                typingTimer = nil
                if !isComplete {
                    isTyping = false
                }
            }
    }
    
    private func startTypingAnimation() {
        typingTimer?.invalidate()
        typingTimer = nil
        typingCancelled = false
        displayedText = ""
        currentIndex = 0
        isComplete = false
        isTyping = true
        
        // Typing animation slowed by 30% for smoother experience
        typingTimer = Timer.scheduledTimer(withTimeInterval: AnimationConstants.typingInterval, repeats: true) { timer in
            if typingCancelled {
                timer.invalidate()
                return
            }
            if currentIndex < fullText.count {
                let index = fullText.index(fullText.startIndex, offsetBy: currentIndex)
                let character = fullText[index]
                displayedText += String(character)
                currentIndex += 1
                
                // Haptic feedback for certain characters
                if character == " " && currentIndex % 8 == 0 {
                    HapticManager.shared.impact(.soft)
                }
            } else {
                timer.invalidate()
                typingTimer = nil
                guard !typingCancelled else { return }
                isComplete = true
                isTyping = false
                onComplete()
            }
        }
    }
    
    private func buildMeditationResponseText(for meditation: AITimerResponse) -> String {
        var text = "I've crafted your meditation session:\n\n"
        
        // Title and duration
        text += "**\(meditation.meditationConfiguration.title ?? "Custom Meditation")**\n"
        text += "Duration: \(meditation.meditationConfiguration.duration) minutes\n\n"
        
        // Soundscape
        if meditation.meditationConfiguration.backgroundSound.name != "None" {
            text += "Soundscape: \(meditation.meditationConfiguration.backgroundSound.name)\n\n"
        }
        
        // Cues
        if !meditation.meditationConfiguration.cueSettings.isEmpty {
            text += "Sound Cues:\n"
            for cueSetting in meditation.meditationConfiguration.cueSettings {
                let timing = cueTimingText(for: cueSetting)
                text += "• \(cueSetting.cue.name) \(timing)\n"
            }
            text += "\n"
        }
        
        // Description
        if !meditation.description.isEmpty {
            text += meditation.description
        }
        
        return text
    }
    
    private func cueTimingText(for cueSetting: CueSetting) -> String {
        switch cueSetting.triggerType {
        case .start:
            return "at start"
        case .minute:
            if let minute = cueSetting.minute {
                return "at \(minute)min"
            } else {
                return "at start"
            }
        case .end:
            return "at end"
        case .second:
            if let sec = cueSetting.minute {
                return "at \(sec)s"
            } else {
                return "at start"
            }
        }
    }
}

// MARK: - Lightweight TypingText for inline sequences
struct TypingText: View {
    let text: String
    let font: Font
    let color: Color
    let onComplete: () -> Void
    
    @State private var displayed = ""
    @State private var index = 0
    
    var body: some View {
        Text(displayed)
            .font(font)
            .foregroundColor(color)
            .onAppear { start() }
    }
    
    private func start() {
        displayed = ""
        index = 0
        Timer.scheduledTimer(withTimeInterval: AnimationConstants.typingInterval, repeats: true) { timer in
            if index < text.count {
                let i = text.index(text.startIndex, offsetBy: index)
                displayed += String(text[i])
                index += 1
            } else {
                timer.invalidate()
                onComplete()
            }
        }
    }
}

// Row typing for two-column summary
struct RowTypingView: View {
    let left: String
    let right: String
    let onComplete: () -> Void
    
    @State private var leftDone = false
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TypingText(
                text: left,
                font: Font.nunito(size: 14, style: .medium),
                color: .white.opacity(0.9),
                onComplete: { leftDone = true }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if leftDone {
                // Keep typing direction LTR while visually right-aligning the value
                RightAnchoredTypingText(
                    text: right,
                    font: Font.nunito(size: 14, style: .medium),
                    color: .white,
                    onComplete: onComplete
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// Instruction row typing left then right, finishing with onComplete
struct InstructionRowTypingView: View {
    let left: String
    let right: String
    let onComplete: () -> Void
    
    @State private var leftDone = false
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TypingText(
                text: left,
                font: Font.nunito(size: 14, style: .medium),
                color: .white.opacity(0.9),
                onComplete: { leftDone = true }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if leftDone {
                RightAnchoredTypingText(
                    text: right,
                    font: Font.nunito(size: 14, style: .medium),
                    color: .white,
                    onComplete: onComplete
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// Right-anchored LTR typing: measures the full text width, types left-to-right within a fixed-width box aligned to the right
struct RightAnchoredTypingText: View {
    let text: String
    let font: Font
    let color: Color
    let onComplete: () -> Void

    @State private var displayed = ""
    @State private var index = 0
    @State private var measuredWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                // Measuring view (hidden)
                Text(text)
                    .font(font)
                    .foregroundColor(.clear)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.onAppear {
                                measuredWidth = proxy.size.width
                            }
                        }
                    )
                    .hidden()

                // Visible typing view
                Text(displayed)
                    .font(font)
                    .foregroundColor(color)
                    .frame(width: measuredWidth, alignment: .leading)
                    .onAppear { start() }
            }
        }
    }

    private func start() {
        displayed = ""
        index = 0
        Timer.scheduledTimer(withTimeInterval: AnimationConstants.typingInterval, repeats: true) { timer in
            if index < text.count {
                let i = text.index(text.startIndex, offsetBy: index)
                displayed += String(text[i])
                index += 1
            } else {
                timer.invalidate()
                onComplete()
            }
        }
    }
}

// MARK: - Sensei Message Typing View with Preserved Formatting

struct SenseiTypingView: View {
    let message: SenseiOnboardingMessage
    @Binding var isTyping: Bool
    let conversationCount: Int
    let onComplete: () -> Void
    
    // Typing state for each part
    @State private var titleDisplayed = ""
    @State private var titleIndex = 0
    @State private var titleComplete = false
    
    @State private var bodyDisplayed = ""
    @State private var bodyIndex = 0
    @State private var bodyComplete = false
    
    @State private var captionDisplayed = ""
    @State private var captionIndex = 0
    @State private var captionComplete = false
    
    @State private var isComplete = false
    @State private var currentTimer: Timer?
    
    // Determine which parts exist
    private var hasTitle: Bool { !message.title.isEmpty }
    private var hasBody: Bool { !message.body.isEmpty }
    private var hasCaption: Bool { message.caption != nil && !message.caption!.isEmpty }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title (22pt bold, kerning 0.32, selectedLightPurple)
            if hasTitle {
                if titleComplete {
                    Text(message.title)
                        .font(Font.custom("Nunito", size: 22).weight(.bold))
                        .kerning(0.32)
                        .foregroundColor(.selectedLightPurple)
                } else {
                    Text(titleDisplayed + (isComplete ? "" : "▋"))
                        .font(Font.custom("Nunito", size: 22).weight(.bold))
                        .kerning(0.32)
                        .foregroundColor(.selectedLightPurple)
                }
            }
            
            // Body (16pt medium, white)
            if hasBody {
                if bodyComplete {
                    Text(message.body)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                } else if titleComplete || !hasTitle {
                    Text(bodyDisplayed + (isComplete && !hasCaption ? "" : "▋"))
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
            
            // Caption (14pt regular, gray)
            if hasCaption, let caption = message.caption {
                if captionComplete {
                    Text(caption)
                        .nunitoFont(size: 14, style: .regular)
                        .foregroundColor(.gray)
                } else if bodyComplete || (!hasBody && titleComplete) || (!hasBody && !hasTitle) {
                    Text(captionDisplayed + (isComplete ? "" : "▋"))
                        .nunitoFont(size: 14, style: .regular)
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            startTypingAnimation()
        }
        .onDisappear {
            currentTimer?.invalidate()
        }
        .onChange(of: titleDisplayed) { oldText, newText in
            // Trigger scroll as text is being typed (every few characters to avoid spam)
            if newText.count > oldText.count && newText.count % 10 == 0 {
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
        .onChange(of: bodyDisplayed) { oldText, newText in
            // Trigger scroll as text is being typed (every few characters to avoid spam)
            if newText.count > oldText.count && newText.count % 10 == 0 {
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
        .onChange(of: captionDisplayed) { oldText, newText in
            // Trigger scroll as text is being typed (every few characters to avoid spam)
            if newText.count > oldText.count && newText.count % 10 == 0 {
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
        .onChange(of: isComplete) { oldValue, newValue in
            // Trigger scroll when typing completes
            if newValue && !oldValue {
                logger.aiChat("🧠 AI_SCROLL: SenseiTypingView typing completed")
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
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
    
    private func startTypingAnimation() {
        isTyping = true
        isComplete = false
        
        // Reset all states
        titleDisplayed = ""
        titleIndex = 0
        titleComplete = false
        bodyDisplayed = ""
        bodyIndex = 0
        bodyComplete = false
        captionDisplayed = ""
        captionIndex = 0
        captionComplete = false
        
        // Start typing sequence - slowed by 30% for smoother experience
        currentTimer = Timer.scheduledTimer(withTimeInterval: AnimationConstants.typingInterval, repeats: true) { timer in
            // Type title first (if present)
            if hasTitle && !titleComplete {
                if titleIndex < message.title.count {
                    let index = message.title.index(message.title.startIndex, offsetBy: titleIndex)
                    titleDisplayed += String(message.title[index])
                    titleIndex += 1
                } else {
                    titleComplete = true
                }
            }
            // Then type body (if present, after title completes or if no title)
            else if hasBody && (!hasTitle || titleComplete) && !bodyComplete {
                if bodyIndex < message.body.count {
                    let index = message.body.index(message.body.startIndex, offsetBy: bodyIndex)
                    bodyDisplayed += String(message.body[index])
                    bodyIndex += 1
                } else {
                    bodyComplete = true
                }
            }
            // Finally type caption (if present, after body completes or if no body)
            else if hasCaption && (!hasBody || bodyComplete) && !captionComplete {
                if let caption = message.caption {
                    if captionIndex < caption.count {
                        let index = caption.index(caption.startIndex, offsetBy: captionIndex)
                        captionDisplayed += String(caption[index])
                        captionIndex += 1
                    } else {
                        captionComplete = true
                    }
                }
            }
            
            // Check if all parts are complete
            let allComplete = (!hasTitle || titleComplete) && 
                             (!hasBody || bodyComplete) && 
                             (!hasCaption || captionComplete)
            
            if allComplete {
                timer.invalidate()
                isComplete = true
                isTyping = false
                onComplete()
            }
        }
    }
}

// MARK: - Sensei Question Typing View with Preamble + Question

struct SenseiQuestionTypingView: View {
    let question: SenseiOnboardingQuestion
    @Binding var isTyping: Bool
    let conversationCount: Int
    let onComplete: () -> Void
    
    // Typing state for each part
    @State private var preambleDisplayed = ""
    @State private var preambleIndex = 0
    @State private var preambleComplete = false
    
    @State private var questionDisplayed = ""
    @State private var questionIndex = 0
    @State private var questionComplete = false
    
    @State private var isComplete = false
    @State private var currentTimer: Timer?
    
    // Determine which parts exist
    private var hasPreamble: Bool { question.preamble != nil && !question.preamble!.isEmpty }
    private var hasQuestion: Bool { !question.question.isEmpty }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preamble (16pt medium, white)
            if hasPreamble {
                if preambleComplete {
                    Text(question.preamble!)
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                } else {
                    Text(preambleDisplayed + (isComplete ? "" : "▋"))
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
            
            // Question (22pt bold, white)
            if hasQuestion {
                if questionComplete {
                    Text(question.question)
                        .font(Font.custom("Nunito", size: 22).weight(.bold))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                } else if preambleComplete || !hasPreamble {
                    Text(questionDisplayed + (isComplete ? "" : "▋"))
                        .font(Font.custom("Nunito", size: 22).weight(.bold))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            startTypingAnimation()
        }
        .onDisappear {
            currentTimer?.invalidate()
        }
        .onChange(of: preambleDisplayed) { oldText, newText in
            if newText.count > oldText.count && newText.count % 10 == 0 {
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
        .onChange(of: questionDisplayed) { oldText, newText in
            if newText.count > oldText.count && newText.count % 10 == 0 {
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
        .onChange(of: isComplete) { oldValue, newValue in
            if newValue && !oldValue {
                logger.aiChat("🧠 AI_SCROLL: SenseiQuestionTypingView typing completed")
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
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
    
    private func startTypingAnimation() {
        isTyping = true
        isComplete = false
        
        // Reset all states
        preambleDisplayed = ""
        preambleIndex = 0
        preambleComplete = false
        questionDisplayed = ""
        questionIndex = 0
        questionComplete = false
        
        // Start typing sequence
        currentTimer = Timer.scheduledTimer(withTimeInterval: AnimationConstants.typingInterval, repeats: true) { timer in
            // Type preamble first (if present)
            if hasPreamble && !preambleComplete {
                if let preamble = question.preamble, preambleIndex < preamble.count {
                    let index = preamble.index(preamble.startIndex, offsetBy: preambleIndex)
                    preambleDisplayed += String(preamble[index])
                    preambleIndex += 1
                } else {
                    preambleComplete = true
                }
            }
            // Then type question (if present, after preamble completes or if no preamble)
            else if hasQuestion && (!hasPreamble || preambleComplete) && !questionComplete {
                if questionIndex < question.question.count {
                    let index = question.question.index(question.question.startIndex, offsetBy: questionIndex)
                    questionDisplayed += String(question.question[index])
                    questionIndex += 1
                } else {
                    questionComplete = true
                }
            }
            
            // Check if all parts are complete
            let allComplete = (!hasPreamble || preambleComplete) && (!hasQuestion || questionComplete)
            
            if allComplete {
                timer.invalidate()
                isComplete = true
                isTyping = false
                onComplete()
            }
        }
    }
}