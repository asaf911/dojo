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
            let polished = try await SimplifiedAIService().generatePolishedPostPracticeMessage(
                firstName: context.firstName,
                durationMinutes: context.durationMinutes,
                streak: context.streak,
                longestStreak: context.longestStreak,
                isNewRecord: context.isNewRecord,
                hrStartBPM: context.heartRateStartBPM,
                hrEndBPM: context.heartRateEndBPM,
                hrChangePercent: context.heartRateChangePercent,
                sessionContext: context.sessionContext
            )

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
}

