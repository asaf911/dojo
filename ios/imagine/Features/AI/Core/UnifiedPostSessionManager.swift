//
//  UnifiedPostSessionManager.swift
//  imagine
//
//  Unified post-practice message creation for all meditation types.
//  Routes completed sessions to AI chat with consistent messaging and AI polish.
//

import Foundation

/// Unified manager for all post-practice session handling.
/// Replaces AIExplorePostSessionManager, AIPathPostSessionManager, and AIPostSessionMessageManager.
final class UnifiedPostSessionManager {
    static let shared = UnifiedPostSessionManager()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Handle a completed meditation session of any type.
    /// This method is async to ensure report persistence completes before returning,
    /// which is critical when called from a background task context.
    /// - Parameters:
    ///   - type: The type of session with associated context
    ///   - durationMinutes: Duration of the session in minutes
    ///   - heartRateResults: Captured heart rate data from the session
    func handleCompletedSession(
        type: PostSessionType,
        durationMinutes: Int?,
        heartRateResults: HeartRateResults
    ) async {
        let sessionLabel = sessionTypeLabel(type)
        logger.aiChat("📋 [POST_PRACTICE] HANDLER_START type=\(sessionLabel)")
        logger.aiChat("📋 [POST_PRACTICE] ═══════════════════════════════════════════════")
        logger.aiChat("📋 [POST_PRACTICE] SESSION_START type=\(sessionLabel) duration=\(durationMinutes ?? 0)min")
        logger.aiChat("📋 [POST_PRACTICE] HR_DATA hasValid=\(heartRateResults.hasValidData) hasAny=\(heartRateResults.hasAnyData) samples=\(heartRateResults.sampleCount)")
        
        // Capture values synchronously before entering MainActor
        let sessionId = UUID().uuidString
        let streakData = StreakManager.shared.getStreakDisplayData()
        let firstName = resolveFirstName()
        let heartRate = HeartRateContext.from(heartRateResults)
        let heartRateSamples = HeartRateContext.samplesFrom(heartRateResults)
        let createdAt = Date().timeIntervalSince1970
        
        logger.aiChat("📋 [POST_PRACTICE] CONTEXT sessionId=\(sessionId) firstName=\(firstName ?? "nil") streak=\(streakData.currentStreak)")
        
        // Use await MainActor.run to ensure report persistence completes synchronously
        // before this function returns. This is critical for background task protection.
        await MainActor.run {
            logger.aiChat("📋 [POST_PRACTICE] HANDLER_MAINACTOR_ENTER sessionId=\(sessionId)")
            
            // Resolve path data if needed
            var resolvedType = type
            if case .path(let stepId, _, _, _) = type {
                // Refresh path progress to get updated next step
                PathProgressManager.shared.refreshProgress()
                
                let step = PathProgressManager.shared.pathSteps.first { $0.id == stepId }
                let nextStep = PathProgressManager.shared.nextStep
                let isPathComplete = PathProgressManager.shared.allStepsCompleted
                
                logger.aiChat("📋 [POST_PRACTICE] PATH_RESOLVED stepId=\(stepId) stepTitle=\(step?.title ?? "nil") nextStep=\(nextStep?.id ?? "nil") pathComplete=\(isPathComplete)")
                
                // Rebuild the session type with resolved path data
                resolvedType = PostSessionType.path(
                    stepId: stepId,
                    step: step,
                    nextStep: nextStep,
                    isPathComplete: isPathComplete
                )
            }
            
            // Build and enqueue report SYNCHRONOUSLY within MainActor context
            self.buildAndEnqueueReport(
                sessionId: sessionId,
                sessionType: resolvedType,
                firstName: firstName,
                durationMinutes: durationMinutes,
                streakData: streakData,
                heartRate: heartRate,
                heartRateSamples: heartRateSamples,
                createdAt: createdAt
            )

            ContextStateManager.shared.recordSessionComplete(sessionType: resolvedType, completedAt: createdAt)
            
            logger.aiChat("📋 [POST_PRACTICE] HANDLER_COMPLETE sessionId=\(sessionId)")
        }
    }
    
    // MARK: - Private Helpers
    
    @MainActor
    private func buildAndEnqueueReport(
        sessionId: String,
        sessionType: PostSessionType,
        firstName: String?,
        durationMinutes: Int?,
        streakData: StreakManager.StreakDisplayData,
        heartRate: HeartRateContext?,
        heartRateSamples: [HeartRateSamplePoint]?,
        createdAt: TimeInterval
    ) {
        let input = PostPracticeMessageInput(
            sessionId: sessionId,
            firstName: firstName,
            durationMinutes: durationMinutes,
            streak: streakData,
            heartRate: heartRate,
            heartRateSamples: heartRateSamples,
            createdAt: createdAt,
            sessionType: sessionType
        )
        
        let (report, polishContext) = PostPracticeMessageBuilder.buildReport(from: input)
        
        logger.aiChat("📋 [POST_PRACTICE] REPORT_BUILT sessionId=\(sessionId)")
        logger.aiChat("📋 [POST_PRACTICE]   praise_len=\(report.completionPraise.count) streak_len=\(report.streakMessage.count) hr_len=\(report.heartRateMessage?.count ?? 0)")
        logger.aiChat("📋 [POST_PRACTICE]   status=\(report.status.rawValue) expectsPolish=\(report.metadata.expectsPolish)")
        
        PostSessionMessageStore.shared.enqueueReport(report)
        
        logger.aiChat("📋 [POST_PRACTICE] POLISH_SCHEDULED sessionId=\(sessionId)")
        
        // Always schedule AI polish for consistent quality
        PostPracticePolishService.shared.schedulePolish(for: report, context: polishContext)
    }
    
    private func resolveFirstName() -> String? {
        let storedName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)
        return storedName?.split(separator: " ").first.map(String.init)
    }
    
    private func sessionTypeLabel(_ type: PostSessionType) -> String {
        switch type {
        case .explore(let file):
            return "explore(\(file.id))"
        case .path(let stepId, _, _, let isComplete):
            return "path(\(stepId), complete=\(isComplete))"
        case .custom(let title, _):
            return "custom(\(title ?? "untitled"))"
        }
    }
}
