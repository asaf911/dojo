//
//  ContextStateSnapshot.swift
//  imagine
//
//  Persisted state for the Adaptive Context Evolution Layer.
//  Stored via SharedUserStorage under .contextStateSnapshot.
//

import Foundation

// MARK: - Context State Snapshot

/// Rolling state for context evolution: recent sessions, primaries, override.
struct ContextStateSnapshot: Codable, Equatable {

    /// Last N completed sessions. (GoalContext.rawValue, completedAt). Max 20.
    var recentSessions: [SessionEntry]

    /// Last 5 primaries shown (for diversity guardrail). GoalContext.rawValue.
    var recentPrimaries: [String]

    /// Explicit user override: dominant for next N sessions.
    var explicitOverride: ExplicitOverride?

    /// Total sessions completed (for onboarding decay).
    var totalSessionsCompleted: Int

    /// Primaries shown since last exploration injection (for 1-in-3 rule).
    var primariesSinceExploration: Int

    init(
        recentSessions: [SessionEntry] = [],
        recentPrimaries: [String] = [],
        explicitOverride: ExplicitOverride? = nil,
        totalSessionsCompleted: Int = 0,
        primariesSinceExploration: Int = 0
    ) {
        self.recentSessions = recentSessions
        self.recentPrimaries = recentPrimaries
        self.explicitOverride = explicitOverride
        self.totalSessionsCompleted = totalSessionsCompleted
        self.primariesSinceExploration = primariesSinceExploration
    }

    static let maxRecentSessions = 20
    static let maxRecentPrimaries = 5
}

// MARK: - Session Entry

struct SessionEntry: Codable, Equatable {
    let goalRawValue: String
    let completedAt: TimeInterval
}

// MARK: - Explicit Override

struct ExplicitOverride: Codable, Equatable {
    let goalRawValue: String
    var sessionsRemaining: Int
}

// MARK: - Backward Compatibility

extension ContextStateSnapshot {
    enum CodingKeys: String, CodingKey {
        case recentSessions, recentPrimaries, explicitOverride, totalSessionsCompleted, primariesSinceExploration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recentSessions = try c.decode([SessionEntry].self, forKey: .recentSessions)
        recentPrimaries = try c.decode([String].self, forKey: .recentPrimaries)
        explicitOverride = try c.decodeIfPresent(ExplicitOverride.self, forKey: .explicitOverride)
        totalSessionsCompleted = try c.decode(Int.self, forKey: .totalSessionsCompleted)
        primariesSinceExploration = try c.decodeIfPresent(Int.self, forKey: .primariesSinceExploration) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recentSessions, forKey: .recentSessions)
        try c.encode(recentPrimaries, forKey: .recentPrimaries)
        try c.encodeIfPresent(explicitOverride, forKey: .explicitOverride)
        try c.encode(totalSessionsCompleted, forKey: .totalSessionsCompleted)
        try c.encode(primariesSinceExploration, forKey: .primariesSinceExploration)
    }
}
