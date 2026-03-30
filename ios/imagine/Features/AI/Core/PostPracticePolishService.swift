import Foundation

// MARK: - Polish Service

final class PostPracticePolishService {
    static let shared = PostPracticePolishService()

    private init() {}

    func schedulePolish(for report: PostPracticeReport, context: PostPracticePolishContext) {
        logger.aiChat("📋 [POST_PRACTICE] POLISH_START sessionId=\(report.sessionId)")
        Task.detached(priority: .utility) {
            await self.performPolish(for: report, context: context)
        }
    }

    private func performPolish(for report: PostPracticeReport, context: PostPracticePolishContext) async {
        do {
            logger.aiChat("📋 [POST_PRACTICE] POLISH_API_CALL sessionId=\(report.sessionId)")
            let polished = try await generatePolishedMessage(context: context)

            await MainActor.run {
                logger.aiChat("📋 [POST_PRACTICE] POLISH_SUCCESS sessionId=\(report.sessionId) polished_len=\(polished.count)")
                var metadata = report.metadata
                metadata.expectsPolish = false

                // Parse polished content into sections (split by double newlines)
                let sections = polished.components(separatedBy: "\n\n").filter { !$0.isEmpty }

                logger.aiChat("📋 [POST_PRACTICE] POLISH_PARSED section_count=\(sections.count)")

                // The AI should return 3 sections: praise, streak, heart rate
                // If it returns fewer sections, the polished response is incomplete/malformed
                // In that case, we cancel polish and keep the original fallback content
                guard sections.count >= 2 else {
                    logger.aiChat("📋 [POST_PRACTICE] POLISH_MALFORMED expected 3 sections, got \(sections.count) - keeping fallback")
                    PostSessionMessageStore.shared.cancelPolish(sessionId: report.sessionId)
                    return
                }

                let polishedPraise = sections[0]
                let polishedStreak = sections[1]
                let polishedHeartRate = sections.count > 2 ? sections[2] : nil

                logger.aiChat("📋 [POST_PRACTICE] POLISH_SECTIONS praise_len=\(polishedPraise.count) streak_len=\(polishedStreak.count) hr_len=\(polishedHeartRate?.count ?? 0)")

                PostSessionMessageStore.shared.upgradeReport(
                    sessionId: report.sessionId,
                    polishedPraise: polishedPraise,
                    polishedStreak: polishedStreak,
                    polishedHeartRate: polishedHeartRate,
                    metadata: metadata
                )
            }
        } catch {
            await MainActor.run {
                logger.aiChat("📋 [POST_PRACTICE] POLISH_ERROR sessionId=\(report.sessionId) error=\(error.localizedDescription)")
                PostSessionMessageStore.shared.cancelPolish(sessionId: report.sessionId)
            }
        }
    }

    private func generatePolishedMessage(context: PostPracticePolishContext) async throws -> String {
        let name = (context.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }

        let streakText = buildStreakMessage(context.streak, context.longestStreak, context.isNewRecord)
        var hrLine: String?
        if let s = context.heartRateStartBPM,
           let min = context.heartRateMinBPM, min > 0 {
            hrLine = buildHRMessageMin(start: s, min: min)
        } else if let s = context.heartRateStartBPM,
                  let e = context.heartRateEndBPM,
                  let pct = context.heartRateChangePercent {
            hrLine = buildHRMessage(s, e, pct)
        }
        let streakSection = "🔥 \(streakText)"
        let hrSection: String? = hrLine.map { "❤️ \($0)" }
        let sessionContextText = buildSessionContextText(context.sessionContext)
        let praiseInstructions = buildPraiseInstructions(sessionContext: context.sessionContext)

        let prompt = """
        You are Dojo's Sensei. Write a SHORT, HUMAN post-practice message with 2-3 sections separated by blank lines.

        SECTION 1 - PRAISE (required, MAX 50 CHARS):
        \(praiseInstructions)
        - ONE short sentence, ~40-50 chars max
        - If name provided, use it once
        - No emojis. Warm and natural.

        SECTION 2 - STREAK (required):
        - Rephrase STREAK_SECTION to sound natural, not robotic
        - MUST include the word "streak"
        - Keep same info: days count, record info
        - ~40-50 chars, keep the 🔥 emoji at start

        SECTION 3 - HEART RATE (only if HR_SECTION provided):
        - Rephrase HR_SECTION to sound human and warm
        - Keep same numbers but vary wording
        - ~40-50 chars, keep the ❤️ emoji at start

        CRITICAL: Sound like a friendly coach, not a robot. Vary wording. Separate sections with ONE blank line.

        DATA:
        \([sessionContextText, name.map { "NAME: \($0)" }, "STREAK_SECTION: \(streakSection)", hrSection.map { "HR_SECTION: \($0)" }].compactMap { $0 }.joined(separator: "\n"))
        """

        let response = try await AIRequestService.shared.processAIRequest(
            prompt: prompt,
            conversationHistory: [],
            context: nil,
            triggerContext: "PostPracticePolishService|generatePolished"
        )
        guard case .text(let text) = response.content else {
            throw NSError(domain: "PostPracticePolishService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Expected text response"])
        }
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let sections = trimmed.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        if sections.count >= 2 && trimmed.count <= 600 {
            return trimmed
        }
        logger.aiChat("📋 [POST_PRACTICE] POLISH_AI_INVALID sections=\(sections.count) len=\(trimmed.count)")

        // Local fallback
        let praisePart = buildFallbackPraise(name: name, sessionContext: context.sessionContext)
        var fallbackSections = [praisePart, streakSection]
        if let hr = hrSection { fallbackSections.append(hr) }
        return fallbackSections.joined(separator: "\n\n")
    }

    private func buildStreakMessage(_ streak: Int, _ longest: Int, _ newRecord: Bool) -> String {
        if streak == 1 { return "Day 1 of your streak — keep going!" }
        if newRecord { return "New record! \(streak) day streak." }
        if streak == longest { return "\(streak) day streak — matches your best!" }
        let toRecord = max(0, longest - streak)
        if toRecord == 1 { return "\(streak) day streak — 1 more beats your record!" }
        return "\(streak) day streak — \(toRecord) more to beat your record."
    }

    private func buildHRMessage(_ start: Int, _ end: Int, _ pct: Double) -> String? {
        guard start > 0 && end > 0 else { return "HR data unavailable." }
        let absPct = abs(pct)
        if absPct < 3.0 { return "HR stayed steady around \(start) BPM." }
        if pct < 0 && absPct >= 10.0 { return "HR dropped from \(start) to \(end). Nice!" }
        if pct < 0 { return "HR eased from \(start) to \(end) BPM." }
        return "HR rose from \(start) to \(end) BPM."
    }

    private func buildHRMessageMin(start: Int, min: Int) -> String? {
        guard start > 0, min > 0 else { return "HR data unavailable." }
        let absBPM = abs(start - min)
        if absBPM < 3 { return "HR stayed steady around \(start) BPM." }
        if min < start {
            if absBPM >= 10 { return "HR dropped from \(start) to \(min) (~\(absBPM) BPM). Nice!" }
            return "HR eased from \(start) to \(min) BPM (~\(absBPM) BPM)."
        }
        return "HR low was \(min) BPM during the session."
    }

    private func buildSessionContextText(_ context: PostPracticePolishContext.SessionContext?) -> String? {
        guard let context = context else { return nil }
        switch context {
        case .path(let stepTitle, let stepOrder, let isPathComplete):
            if isPathComplete { return "SESSION_TYPE: PATH_COMPLETE (User just finished the entire Path learning journey!)" }
            if let title = stepTitle, let order = stepOrder { return "SESSION_TYPE: PATH_STEP (Step \(order): \"\(title)\")" }
            if let title = stepTitle { return "SESSION_TYPE: PATH_STEP (\"\(title)\")" }
            return "SESSION_TYPE: PATH_STEP"
        case .explore(let meditationTitle):
            if let title = meditationTitle { return "SESSION_TYPE: EXPLORE_MEDITATION (\"\(title)\")" }
            return "SESSION_TYPE: EXPLORE_MEDITATION"
        case .custom(let title):
            if let title = title { return "SESSION_TYPE: CUSTOM_MEDITATION (\"\(title)\")" }
            return "SESSION_TYPE: CUSTOM_MEDITATION"
        }
    }

    private func buildPraiseInstructions(sessionContext: PostPracticePolishContext.SessionContext?) -> String {
        guard let context = sessionContext else { return "- Brief praise for completing practice" }
        switch context {
        case .path(let stepTitle, let stepOrder, let isPathComplete):
            if isPathComplete { return "- Celebrate completing the Path (still keep it short!)" }
            if let title = stepTitle, let order = stepOrder { return "- Praise Step \(order): \"\(title)\" completion" }
            if let title = stepTitle { return "- Praise \"\(title)\" completion" }
            return "- Praise Path step completion"
        case .explore(let meditationTitle):
            if let title = meditationTitle { return "- Praise \"\(title)\" completion" }
            return "- Brief praise for meditation"
        case .custom(let title):
            if let title = title { return "- Praise \"\(title)\" completion" }
            return "- Brief praise for custom meditation"
        }
    }

    private func buildFallbackPraise(name: String?, sessionContext: PostPracticePolishContext.SessionContext?) -> String {
        if let context = sessionContext {
            switch context {
            case .path(let stepTitle, let stepOrder, let isPathComplete):
                if isPathComplete { return name.map { "\($0), Path complete!" } ?? "Path complete!" }
                if let title = stepTitle, let order = stepOrder { return name.map { "\($0), Step \(order) done." } ?? "Step \(order): \(title) done." }
                if let title = stepTitle { return name.map { "\($0), \"\(title)\" done." } ?? "\"\(title)\" done." }
                return name.map { "\($0), step complete." } ?? "Step complete."
            case .explore(let meditationTitle):
                if let title = meditationTitle { return name.map { "\($0), \"\(title)\" done." } ?? "\"\(title)\" done." }
            case .custom(let title):
                if let title = title { return name.map { "\($0), \"\(title)\" done." } ?? "\"\(title)\" done." }
            }
        }
        return name.map { "\($0), nice practice." } ?? "Nice practice."
    }
}
