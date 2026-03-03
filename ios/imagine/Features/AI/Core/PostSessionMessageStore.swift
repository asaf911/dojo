import Foundation
import Combine

// MARK: - Post-practice Message Model

struct PostPracticeReport: Codable, Equatable {
    enum Status: String, Codable {
        case readyFallback
        case waitingForPolish
        case readyPolished
        case completed
    }

    struct Metadata: Codable, Equatable {
        // Session info
        var durationMinutes: Int?
        var userFirstName: String?
        
        // Streak data
        var currentStreak: Int
        var longestStreak: Int
        var isNewRecord: Bool
        
        // Heart rate graph data
        var heartRateSamples: [HeartRateSamplePoint]?
        var heartRateStartBPM: Int?
        var heartRateEndBPM: Int?
        var heartRateChangePercent: Double?
        
        // State
        var expectsPolish: Bool
        
        // Path-specific data
        var completedPathStepId: String?
        var nextPathStepId: String?
        var isPathComplete: Bool
        
        /// Convenience check: is this a Path session report?
        var isPathSession: Bool {
            completedPathStepId != nil
        }
    }

    let sessionId: String
    var createdAt: TimeInterval
    var status: Status
    var bubbleId: UUID?
    
    // Separated content sections for flexible display
    /// Section 1: Praise for completing the session
    var completionPraise: String
    /// Section 2: Streak information
    var streakMessage: String
    /// Section 3: Heart rate analysis text (shown after graph)
    var heartRateMessage: String?
    
    var metadata: Metadata

    var isReadyForDisplay: Bool {
        status == .readyFallback || status == .readyPolished
    }
    
    /// Combined text content for backward compatibility and typing animation
    var combinedTextContent: String {
        [completionPraise, streakMessage, heartRateMessage]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

// MARK: - Store

@MainActor
final class PostSessionMessageStore {
    static let shared = PostSessionMessageStore()

    private let storageKey: UserStorageKey = .aiPendingPostSessionMessage
    private let subject = CurrentValueSubject<PostPracticeReport?, Never>(nil)
    private var currentReport: PostPracticeReport?

    var publisher: AnyPublisher<PostPracticeReport, Never> {
        subject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    var latestReport: PostPracticeReport? {
        currentReport
    }

    private init() {
        if let stored: PostPracticeReport = SharedUserStorage.retrieve(forKey: storageKey, as: PostPracticeReport.self) {
            currentReport = stored
            subject.value = stored
            logger.aiChat("🧠 AI_DEBUG post_session_store init state=\(stored.status.rawValue) session=\(stored.sessionId)")
        } else if let legacyState: LegacyPostSessionMessageState = SharedUserStorage.retrieve(forKey: storageKey, as: LegacyPostSessionMessageState.self) {
            let migrated = convert(legacy: legacyState)
            setCurrent(migrated, reason: "migrated_legacy_state")
        } else if let legacyFallback: LegacyPendingMessage = SharedUserStorage.retrieve(forKey: storageKey, as: LegacyPendingMessage.self) {
            let migrated = convert(legacy: legacyFallback)
            setCurrent(migrated, reason: "migrated_legacy_fallback")
        }
    }

    func enqueueReport(_ report: PostPracticeReport) {
        logger.aiChat("📋 [POST_PRACTICE] STORE_ENQUEUE sessionId=\(report.sessionId) status=\(report.status.rawValue)")
        if let existing = currentReport, existing.sessionId == report.sessionId {
            var merged = existing
            merged.completionPraise = report.completionPraise
            merged.streakMessage = report.streakMessage
            merged.heartRateMessage = report.heartRateMessage
            merged.createdAt = report.createdAt
            merged.status = report.status
            merged.metadata = report.metadata
            logger.aiChat("📋 [POST_PRACTICE] STORE_ENQUEUE merging with existing report")
            setCurrent(merged, reason: "enqueue_update")
        } else {
            logger.aiChat("📋 [POST_PRACTICE] STORE_ENQUEUE creating new report")
            setCurrent(report, reason: "enqueue_new")
        }
    }

    func upgradeReport(sessionId: String, polishedPraise: String? = nil, polishedStreak: String? = nil, polishedHeartRate: String? = nil, metadata: PostPracticeReport.Metadata? = nil) {
        logger.aiChat("📋 [POST_PRACTICE] STORE_UPGRADE sessionId=\(sessionId) hasPraise=\(polishedPraise != nil) hasStreak=\(polishedStreak != nil) hasHR=\(polishedHeartRate != nil)")
        guard var report = currentReport, report.sessionId == sessionId else {
            logger.aiChat("📋 [POST_PRACTICE] STORE_UPGRADE FAILED - no matching report found")
            return
        }
        let oldStatus = report.status
        if let praise = polishedPraise {
            report.completionPraise = praise
        }
        if let streak = polishedStreak {
            report.streakMessage = streak
        }
        if let hr = polishedHeartRate {
            report.heartRateMessage = hr
        }
        report.status = .readyPolished
        if let metadata = metadata {
            report.metadata = metadata
        }
        logger.aiChat("📋 [POST_PRACTICE] STORE_UPGRADE status \(oldStatus.rawValue) -> \(report.status.rawValue)")
        setCurrent(report, reason: "upgrade_polished")
    }

    func markDisplayed(sessionId: String, bubbleId: UUID) {
        logger.aiChat("📋 [POST_PRACTICE] STORE_MARK_DISPLAYED sessionId=\(sessionId) bubbleId=\(bubbleId)")
        guard var report = currentReport, report.sessionId == sessionId else {
            logger.aiChat("📋 [POST_PRACTICE] STORE_MARK_DISPLAYED FAILED - no matching report found")
            return
        }
        let oldStatus = report.status
        report.bubbleId = bubbleId
        report.status = report.metadata.expectsPolish ? .waitingForPolish : .completed
        logger.aiChat("📋 [POST_PRACTICE] STORE_MARK_DISPLAYED status \(oldStatus.rawValue) -> \(report.status.rawValue) expectsPolish=\(report.metadata.expectsPolish)")
        setCurrent(report, reason: "mark_displayed")
        clearIfCompleted()
    }

    func markCompleted(sessionId: String) {
        logger.aiChat("📋 [POST_PRACTICE] STORE_MARK_COMPLETED sessionId=\(sessionId)")
        guard var report = currentReport, report.sessionId == sessionId else {
            logger.aiChat("📋 [POST_PRACTICE] STORE_MARK_COMPLETED FAILED - no matching report found")
            return
        }
        report.status = .completed
        setCurrent(report, reason: "mark_completed")
        clearIfCompleted()
    }

    func cancelPolish(sessionId: String) {
        logger.aiChat("📋 [POST_PRACTICE] STORE_CANCEL_POLISH sessionId=\(sessionId)")
        guard var report = currentReport, report.sessionId == sessionId else {
            logger.aiChat("📋 [POST_PRACTICE] STORE_CANCEL_POLISH FAILED - no matching report found")
            return
        }
        report.metadata.expectsPolish = false
        if report.status == .waitingForPolish {
            report.status = .completed
        }
        setCurrent(report, reason: "cancel_polish")
        clearIfCompleted()
    }

    func clear() {
        logger.aiChat("📋 [POST_PRACTICE] STORE_CLEAR manual")
        setCurrent(nil, reason: "manual_clear")
    }

    // MARK: - Private helpers

    private func clearIfCompleted() {
        guard let report = currentReport else { return }
        if report.status == .completed {
            logger.aiChat("📋 [POST_PRACTICE] STORE_AUTO_CLEAR sessionId=\(report.sessionId)")
            setCurrent(nil, reason: "auto_clear_completed")
        }
    }

    private func setCurrent(_ report: PostPracticeReport?, reason: String) {
        currentReport = report
        if let report {
            // Log BEFORE send to maintain correct order (send triggers synchronous subscriber callbacks)
            logger.aiChat("📋 [POST_PRACTICE] STORE_SET reason=\(reason) status=\(report.status.rawValue) sessionId=\(report.sessionId) bubbleId=\(report.bubbleId?.uuidString ?? "nil") isReadyForDisplay=\(report.isReadyForDisplay)")
            SharedUserStorage.save(value: report, forKey: storageKey)
            // CRITICAL: Always send to keep CurrentValueSubject's value in sync with currentReport.
            // If we skip sending, the subject's value becomes stale. When SwiftUI re-subscribes
            // (e.g., during view re-render), the stale value is emitted, causing duplicate
            // message insertions and potential infinite loops. The view handles non-ready
            // states via its guard check, so extra VIEW_SKIP events are harmless.
            subject.send(report)
        } else {
            logger.aiChat("📋 [POST_PRACTICE] STORE_SET reason=\(reason) cleared")
            SharedUserStorage.delete(forKey: storageKey)
            subject.send(nil)
        }
    }

    private func convert(legacy: LegacyPostSessionMessageState) -> PostPracticeReport {
        let status: PostPracticeReport.Status
        switch legacy.status {
        case .pending:
            status = .readyFallback
        case .fallbackInserted:
            status = .waitingForPolish
        case .readyPolished:
            status = .readyPolished
        case .polishedInserted:
            status = .completed
        }

        let metadata = PostPracticeReport.Metadata(
            durationMinutes: nil,
            userFirstName: nil,
            currentStreak: 0,
            longestStreak: 0,
            isNewRecord: false,
            heartRateSamples: nil,
            heartRateStartBPM: nil,
            heartRateEndBPM: nil,
            heartRateChangePercent: nil,
            expectsPolish: status != .completed,
            completedPathStepId: nil,
            nextPathStepId: nil,
            isPathComplete: false
        )

        let bubbleId = legacy.injectedMessageUUIDString.flatMap(UUID.init)

        // Legacy content goes into completionPraise as fallback
        return PostPracticeReport(
            sessionId: legacy.sessionId,
            createdAt: legacy.createdAt,
            status: status,
            bubbleId: bubbleId,
            completionPraise: legacy.content,
            streakMessage: "",
            heartRateMessage: nil,
            metadata: metadata
        )
    }

    private func convert(legacy: LegacyPendingMessage) -> PostPracticeReport {
        let metadata = PostPracticeReport.Metadata(
            durationMinutes: nil,
            userFirstName: nil,
            currentStreak: 0,
            longestStreak: 0,
            isNewRecord: false,
            heartRateSamples: nil,
            heartRateStartBPM: nil,
            heartRateEndBPM: nil,
            heartRateChangePercent: nil,
            expectsPolish: false,
            completedPathStepId: nil,
            nextPathStepId: nil,
            isPathComplete: false
        )

        // Legacy content goes into completionPraise as fallback
        return PostPracticeReport(
            sessionId: UUID().uuidString,
            createdAt: legacy.createdAt,
            status: .readyFallback,
            bubbleId: nil,
            completionPraise: legacy.content,
            streakMessage: "",
            heartRateMessage: nil,
            metadata: metadata
        )
    }
}

// MARK: - Legacy Support

private struct LegacyPostSessionMessageState: Codable, Equatable {
    enum Status: String, Codable {
        case pending
        case fallbackInserted
        case readyPolished
        case polishedInserted
    }

    let sessionId: String
    var content: String
    var createdAt: TimeInterval
    var status: Status
    var injectedMessageUUIDString: String?
}

private struct LegacyPendingMessage: Codable, Equatable {
    let content: String
    let createdAt: TimeInterval
}

