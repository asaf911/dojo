//
//  SessionHistoryQuery.swift
//  Dojo
//
//  Queryable interface for session history - designed for AI integration.
//  Provides structured queries and human-readable summaries.
//

import Foundation

// MARK: - Query Response

struct HistoryQueryResponse {
    let success: Bool
    let sessions: [MeditationSession]
    let summary: String  // Human-readable summary for AI context
    let metadata: [String: Any]
    
    static func empty(message: String) -> HistoryQueryResponse {
        HistoryQueryResponse(
            success: true,
            sessions: [],
            summary: message,
            metadata: [:]
        )
    }
    
    static func error(_ message: String) -> HistoryQueryResponse {
        HistoryQueryResponse(
            success: false,
            sessions: [],
            summary: message,
            metadata: ["error": true]
        )
    }
}

// MARK: - Query Service

final class SessionHistoryQuery {
    static let shared = SessionHistoryQuery()
    
    private var historyManager: SessionHistoryManager {
        SessionHistoryManager.shared
    }
    
    private init() {}
    
    // MARK: - Heart Rate Queries
    
    /// Get average starting heart rate across all sessions
    func averageStartHeartRate() -> HistoryQueryResponse {
        print("🧠 AI_DEBUG HISTORY averageStartHeartRate called")
        let allSessions = historyManager.getAllSessions()
        print("🧠 AI_DEBUG HISTORY totalSessions=\(allSessions.count)")
        let sessionsWithHR = historyManager.getSessionsWithHeartRate()
        print("🧠 AI_DEBUG HISTORY sessionsWithHR=\(sessionsWithHR.count)")
        
        guard !sessionsWithHR.isEmpty else {
            return .empty(message: "You don't have any sessions with heart rate data yet. Complete a meditation with your Apple Watch connected to start tracking your heart rate.")
        }
        
        let startBPMs = sessionsWithHR.compactMap { $0.heartRate?.startBPM }
        guard !startBPMs.isEmpty else {
            return .empty(message: "No starting heart rate data found in your sessions. Make sure heart rate tracking is enabled during your meditations.")
        }
        
        let avgStart = startBPMs.reduce(0, +) / Double(startBPMs.count)
        
        let summary = "Your average heart rate at the start of sessions is \(Int(avgStart)) bpm, based on \(startBPMs.count) session(s) with heart rate data."
        
        return HistoryQueryResponse(
            success: true,
            sessions: sessionsWithHR,
            summary: summary,
            metadata: ["avgStartBPM": avgStart, "sessionCount": startBPMs.count]
        )
    }
    
    /// Get average ending heart rate across all sessions
    func averageEndHeartRate() -> HistoryQueryResponse {
        let sessionsWithHR = historyManager.getSessionsWithHeartRate()
        
        guard !sessionsWithHR.isEmpty else {
            return .empty(message: "You don't have any sessions with heart rate data yet. Complete a meditation with your Apple Watch connected to start tracking your heart rate.")
        }
        
        let endBPMs = sessionsWithHR.compactMap { $0.heartRate?.endBPM }
        guard !endBPMs.isEmpty else {
            return .empty(message: "No ending heart rate data found in your sessions. Make sure heart rate tracking is enabled during your meditations.")
        }
        
        let avgEnd = endBPMs.reduce(0, +) / Double(endBPMs.count)
        
        let summary = "Your average heart rate at the end of sessions is \(Int(avgEnd)) bpm, based on \(endBPMs.count) session(s) with heart rate data."
        
        return HistoryQueryResponse(
            success: true,
            sessions: sessionsWithHR,
            summary: summary,
            metadata: ["avgEndBPM": avgEnd, "sessionCount": endBPMs.count]
        )
    }
    
    /// Get average heart rate reduction across all sessions
    func averageHeartRateReduction() -> HistoryQueryResponse {
        let sessionsWithHR = historyManager.getSessionsWithHeartRate()
        
        guard !sessionsWithHR.isEmpty else {
            return .empty(message: "You don't have any sessions with heart rate data yet. Complete a meditation with your Apple Watch connected to start tracking your heart rate.")
        }
        
        let reductions = sessionsWithHR.compactMap { $0.heartRate?.bpmReduction }
        guard !reductions.isEmpty else {
            return .empty(message: "No heart rate reduction data available. Complete more sessions to see your average improvement.")
        }
        
        let avgReduction = reductions.reduce(0, +) / Double(reductions.count)
        let startBPMs = sessionsWithHR.compactMap { $0.heartRate?.startBPM }
        let endBPMs = sessionsWithHR.compactMap { $0.heartRate?.endBPM }
        let avgStart = startBPMs.isEmpty ? 0 : startBPMs.reduce(0, +) / Double(startBPMs.count)
        let avgEnd = endBPMs.isEmpty ? 0 : endBPMs.reduce(0, +) / Double(endBPMs.count)
        
        let summary = "On average, your heart rate drops by \(Int(avgReduction)) bpm per session (from ~\(Int(avgStart)) to ~\(Int(avgEnd)) bpm), based on \(reductions.count) session(s)."
        
        return HistoryQueryResponse(
            success: true,
            sessions: sessionsWithHR,
            summary: summary,
            metadata: [
                "avgReduction": avgReduction,
                "avgStartBPM": avgStart,
                "avgEndBPM": avgEnd,
                "sessionCount": reductions.count
            ]
        )
    }
    
    /// Find the session with the lowest heart rate during the session (session nadir - may differ from ending).
    /// Uses stored all-time lowest when available for quick lookup.
    func lowestSessionNadir() -> HistoryQueryResponse {
        // Quick path: use stored all-time lowest if we have the session
        if let stored = historyManager.getAllTimeLowestNadir(),
           let session = historyManager.getSession(by: stored.sessionId),
           session.hasHeartRateData {
            let minuteOffset = stored.minuteOffset
            var summary = "Your lowest recorded heart rate during a session was \(Int(stored.bpm)) bpm during '\(stored.sessionTitle)' on \(session.formattedDate)."
            if minuteOffset > 0 {
                summary += " It occurred around \(String(format: "%.1f", minuteOffset)) minutes into the session."
            }
            return HistoryQueryResponse(
                success: true,
                sessions: [session],
                summary: summary,
                metadata: ["nadirBPM": stored.bpm, "minuteOffset": minuteOffset, "title": stored.sessionTitle]
            )
        }
        
        let sessionsWithHR = historyManager.getSessionsWithHeartRate()
        guard !sessionsWithHR.isEmpty else {
            return .empty(message: "You don't have any sessions with heart rate data yet. Complete a meditation with your Apple Watch connected to start tracking your heart rate.")
        }
        
        // Prefer nadir.bpm, fallback to minBPM for older sessions without nadir
        let sorted = sessionsWithHR
            .compactMap { session -> (MeditationSession, Double)? in
                if let nadirBPM = session.heartRate?.nadir?.bpm, nadirBPM > 0 {
                    return (session, nadirBPM)
                }
                if let minBPM = session.heartRate?.minBPM, minBPM > 0 {
                    return (session, minBPM)
                }
                return nil
            }
            .sorted { $0.1 < $1.1 }
        
        guard let lowest = sorted.first else {
            return .empty(message: "No sessions with session minimum heart rate found. Complete more sessions with heart rate tracking to see your lowest HR during a session.")
        }
        
        let session = lowest.0
        let nadirBPM = lowest.1
        let hr = session.heartRate!
        let minuteOffset = hr.nadir?.minuteOffset ?? 0
        
        var summary = "Your lowest recorded heart rate during a session was \(Int(nadirBPM)) bpm during '\(session.title)' on \(session.formattedDate)."
        if minuteOffset > 0 {
            summary += " It occurred around \(String(format: "%.1f", minuteOffset)) minutes into the \(session.formattedDuration) session."
        }
        
        return HistoryQueryResponse(
            success: true,
            sessions: [session],
            summary: summary,
            metadata: ["nadirBPM": nadirBPM, "minuteOffset": minuteOffset, "title": session.title]
        )
    }
    
    /// Find the session with the lowest ending heart rate
    func lowestEndHeartRate() -> HistoryQueryResponse {
        let sessionsWithHR = historyManager.getSessionsWithHeartRate()
        
        guard !sessionsWithHR.isEmpty else {
            return .empty(message: "You don't have any sessions with heart rate data yet. Complete a meditation with your Apple Watch connected to start tracking your heart rate.")
        }
        
        let sorted = sessionsWithHR
            .filter { $0.heartRate?.endBPM != nil }
            .sorted { ($0.heartRate?.endBPM ?? 999) < ($1.heartRate?.endBPM ?? 999) }
        
        guard let best = sorted.first, let hr = best.heartRate, let endBPM = hr.endBPM else {
            return .empty(message: "No sessions with valid ending heart rate found. Make sure you complete your meditation sessions with your Apple Watch connected.")
        }
        
        let summary = "Your lowest ending heart rate was \(Int(endBPM)) bpm during '\(best.title)' on \(best.formattedDate). It was recorded at the end of the \(best.formattedDuration) session."
        
        return HistoryQueryResponse(
            success: true,
            sessions: [best],
            summary: summary,
            metadata: ["endBPM": endBPM, "title": best.title]
        )
    }
    
    /// Find the session with the highest starting heart rate
    func highestStartHeartRate() -> HistoryQueryResponse {
        let sessionsWithHR = historyManager.getSessionsWithHeartRate()
        
        guard !sessionsWithHR.isEmpty else {
            return .empty(message: "You don't have any sessions with heart rate data yet. Complete a meditation with your Apple Watch connected to start tracking your heart rate.")
        }
        
        let sorted = sessionsWithHR
            .filter { $0.heartRate?.startBPM != nil }
            .sorted { ($0.heartRate?.startBPM ?? 0) > ($1.heartRate?.startBPM ?? 0) }
        
        guard let result = sorted.first, let hr = result.heartRate, let startBPM = hr.startBPM else {
            return .empty(message: "No sessions with valid starting heart rate found. Make sure you start your meditation sessions with your Apple Watch connected.")
        }
        
        let summary = "Your highest starting heart rate was \(Int(startBPM)) bpm before '\(result.title)' on \(result.formattedDate)."
        
        return HistoryQueryResponse(
            success: true,
            sessions: [result],
            summary: summary,
            metadata: ["startBPM": startBPM, "title": result.title]
        )
    }
    
    /// Find the session with the largest heart rate reduction (start to end)
    func largestHeartRateReduction() -> HistoryQueryResponse {
        let sessionsWithHR = historyManager.getSessionsWithHeartRate()
        
        guard !sessionsWithHR.isEmpty else {
            return .empty(message: "You don't have any sessions with heart rate data yet. Complete a meditation with your Apple Watch connected to start tracking your heart rate.")
        }
        
        let sorted = sessionsWithHR
            .filter { $0.heartRate?.bpmReduction != nil }
            .sorted { ($0.heartRate?.bpmReduction ?? 0) > ($1.heartRate?.bpmReduction ?? 0) }
        
        guard let best = sorted.first,
              let hr = best.heartRate,
              let reduction = hr.bpmReduction,
              let startBPM = hr.startBPM,
              let endBPM = hr.endBPM else {
            return .empty(message: "No sessions with measurable heart rate reduction found yet. Complete a few more sessions to see your progress.")
        }
        
        let percentReduction = (reduction / startBPM) * 100
        let summary = "Your largest heart rate reduction was \(Int(reduction)) bpm (\(Int(percentReduction))%) during '\(best.title)' on \(best.formattedDate). HR went from \(Int(startBPM)) to \(Int(endBPM)) bpm."
        
        return HistoryQueryResponse(
            success: true,
            sessions: [best],
            summary: summary,
            metadata: [
                "reduction": reduction,
                "percentReduction": percentReduction,
                "startBPM": startBPM,
                "endBPM": endBPM
            ]
        )
    }
    
    /// Get heart rate trend over recent sessions
    func heartRateTrend(lastN sessions: Int = 10) -> HistoryQueryResponse {
        let sessionsWithHR = historyManager.getSessionsWithHeartRate()
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(sessions)
        
        guard sessionsWithHR.count >= 2 else {
            if sessionsWithHR.isEmpty {
                return .empty(message: "You don't have any sessions with heart rate data yet. Complete a meditation with your Apple Watch connected to start tracking your heart rate.")
            }
            return .empty(message: "You need at least 2 sessions with heart rate data to see trends. Complete one more session to view your heart rate patterns.")
        }
        
        let reductions = sessionsWithHR.compactMap { $0.heartRate?.bpmReduction }
        let avgReduction = reductions.reduce(0, +) / Double(reductions.count)
        
        let avgStartBPM = sessionsWithHR.compactMap { $0.heartRate?.startBPM }.reduce(0, +) / Double(sessionsWithHR.count)
        let avgEndBPM = sessionsWithHR.compactMap { $0.heartRate?.endBPM }.reduce(0, +) / Double(sessionsWithHR.count)
        
        let summary = "Over your last \(sessionsWithHR.count) sessions: Average starting HR was \(Int(avgStartBPM)) bpm, ending HR was \(Int(avgEndBPM)) bpm. Average reduction: \(Int(avgReduction)) bpm per session."
        
        return HistoryQueryResponse(
            success: true,
            sessions: Array(sessionsWithHR),
            summary: summary,
            metadata: [
                "avgStartBPM": avgStartBPM,
                "avgEndBPM": avgEndBPM,
                "avgReduction": avgReduction,
                "sessionCount": sessionsWithHR.count
            ]
        )
    }
    
    // MARK: - Duration Queries
    
    /// Find the longest session
    func longestSession() -> HistoryQueryResponse {
        let allSessions = historyManager.getAllSessions()
        
        guard !allSessions.isEmpty else {
            return .empty(message: "No meditation sessions found.")
        }
        
        guard let longest = allSessions.max(by: { $0.actualDurationSeconds < $1.actualDurationSeconds }) else {
            return .empty(message: "Could not determine longest session.")
        }
        
        let summary = "Your longest meditation was '\(longest.title)' at \(longest.formattedDuration) on \(longest.formattedDate)."
        
        return HistoryQueryResponse(
            success: true,
            sessions: [longest],
            summary: summary,
            metadata: ["durationSeconds": longest.actualDurationSeconds]
        )
    }
    
    /// Find the shortest session
    func shortestSession() -> HistoryQueryResponse {
        let allSessions = historyManager.getAllSessions()
        
        guard !allSessions.isEmpty else {
            return .empty(message: "No meditation sessions found.")
        }
        
        guard let shortest = allSessions.min(by: { $0.actualDurationSeconds < $1.actualDurationSeconds }) else {
            return .empty(message: "Could not determine shortest session.")
        }
        
        let summary = "Your shortest meditation was '\(shortest.title)' at \(shortest.formattedDuration) on \(shortest.formattedDate)."
        
        return HistoryQueryResponse(
            success: true,
            sessions: [shortest],
            summary: summary,
            metadata: ["durationSeconds": shortest.actualDurationSeconds]
        )
    }
    
    // MARK: - Recency Queries
    
    /// Get the nadir (lowest HR during session) from the most recent session with heart rate data
    func lastSessionNadir() -> HistoryQueryResponse {
        let sessionsWithHR = historyManager.getSessionsWithHeartRate()
        
        guard let recent = sessionsWithHR.first else {
            return .empty(message: "You don't have any sessions with heart rate data yet. Complete a meditation with your Apple Watch connected to start tracking your heart rate.")
        }
        
        let nadirBPM: Double? = recent.heartRate?.nadir?.bpm ?? recent.heartRate?.minBPM
        guard let bpm = nadirBPM, bpm > 0 else {
            return .empty(message: "Your most recent session with heart rate data doesn't have nadir information. Complete a new session to see your lowest HR during the session.")
        }
        
        let hr = recent.heartRate!
        let minuteOffset = hr.nadir?.minuteOffset ?? 0
        
        var summary = "Your lowest heart rate in your last session was \(Int(bpm)) bpm during '\(recent.title)' on \(recent.formattedDate)."
        if minuteOffset > 0 {
            summary += " It occurred around \(String(format: "%.1f", minuteOffset)) minutes into the \(recent.formattedDuration) session."
        }
        
        return HistoryQueryResponse(
            success: true,
            sessions: [recent],
            summary: summary,
            metadata: ["nadirBPM": bpm, "minuteOffset": minuteOffset, "title": recent.title]
        )
    }
    
    /// Get the most recent session
    func mostRecentSession() -> HistoryQueryResponse {
        let allSessions = historyManager.getAllSessions()
        
        guard let recent = allSessions.first else {
            return .empty(message: "No meditation sessions found.")
        }
        
        var summary = "Your most recent meditation was '\(recent.title)' (\(recent.formattedDuration)) on \(recent.formattedDate)."
        
        if let hr = recent.heartRate, hr.hasValidData, let start = hr.startBPM, let end = hr.endBPM {
            summary += " Your heart rate went from \(Int(start)) to \(Int(end)) bpm."
            if let nadir = hr.nadir {
                summary += " Your lowest during the session was \(Int(nadir.bpm)) bpm around \(String(format: "%.1f", nadir.minuteOffset)) minutes in."
            } else if let minBPM = hr.minBPM {
                summary += " Your lowest during the session was \(Int(minBPM)) bpm."
            }
        }
        
        return HistoryQueryResponse(
            success: true,
            sessions: [recent],
            summary: summary,
            metadata: ["date": recent.createdAt]
        )
    }
    
    /// Get sessions from a specific date
    func sessionsOnDate(_ date: Date) -> HistoryQueryResponse {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return .error("Invalid date")
        }
        
        let sessions = historyManager.getSessions(from: startOfDay, to: endOfDay)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let dateString = dateFormatter.string(from: date)
        
        if sessions.isEmpty {
            return .empty(message: "No meditation sessions found on \(dateString).")
        }
        
        let totalMinutes = sessions.reduce(0) { $0 + $1.actualDurationSeconds } / 60
        let summary = "On \(dateString), you completed \(sessions.count) session(s) totaling \(totalMinutes) minutes: \(sessions.map { $0.title }.joined(separator: ", "))."
        
        return HistoryQueryResponse(
            success: true,
            sessions: sessions,
            summary: summary,
            metadata: ["date": date, "totalMinutes": totalMinutes]
        )
    }
    
    /// Get sessions in the last N days
    func sessionsInLastDays(_ days: Int) -> HistoryQueryResponse {
        let sessions = historyManager.getSessionsInLastDays(days)
        
        if sessions.isEmpty {
            return .empty(message: "No meditation sessions in the last \(days) days.")
        }
        
        let totalMinutes = sessions.reduce(0) { $0 + $1.actualDurationSeconds } / 60
        let avgDuration = totalMinutes / sessions.count
        
        let summary = "In the last \(days) days, you completed \(sessions.count) session(s) totaling \(totalMinutes) minutes (avg \(avgDuration) min/session)."
        
        return HistoryQueryResponse(
            success: true,
            sessions: sessions,
            summary: summary,
            metadata: ["days": days, "totalMinutes": totalMinutes, "avgMinutes": avgDuration]
        )
    }
    
    // MARK: - Category / Tag Queries
    
    /// Get sessions by category or tag
    func sessionsWithTag(_ tag: String) -> HistoryQueryResponse {
        let lowercaseTag = tag.lowercased()
        let sessions = historyManager.getAllSessions().filter { session in
            session.tags.contains { $0.lowercased() == lowercaseTag } ||
            session.category?.lowercased() == lowercaseTag ||
            session.title.lowercased().contains(lowercaseTag)
        }
        
        if sessions.isEmpty {
            return .empty(message: "No sessions found related to '\(tag)'.")
        }
        
        let summary = "Found \(sessions.count) session(s) related to '\(tag)': \(sessions.prefix(5).map { $0.title }.joined(separator: ", "))\(sessions.count > 5 ? "..." : "")."
        
        return HistoryQueryResponse(
            success: true,
            sessions: sessions,
            summary: summary,
            metadata: ["tag": tag, "count": sessions.count]
        )
    }
    
    /// Get sessions by type
    func sessionsByType(_ type: MeditationSessionType) -> HistoryQueryResponse {
        let sessions = historyManager.getSessions(ofType: type)
        
        let typeName: String = {
            switch type {
            case .guided: return "guided"
            case .custom: return "custom"
            case .aiGenerated: return "AI-generated"
            }
        }()
        
        if sessions.isEmpty {
            return .empty(message: "No \(typeName) meditation sessions found.")
        }
        
        let totalMinutes = sessions.reduce(0) { $0 + $1.actualDurationSeconds } / 60
        let summary = "You've completed \(sessions.count) \(typeName) session(s) totaling \(totalMinutes) minutes."
        
        return HistoryQueryResponse(
            success: true,
            sessions: sessions,
            summary: summary,
            metadata: ["type": type.rawValue, "totalMinutes": totalMinutes]
        )
    }
    
    // MARK: - Aggregate Statistics
    
    /// Get overall statistics
    func totalStats() -> HistoryQueryResponse {
        let allSessions = historyManager.getAllSessions()
        
        guard !allSessions.isEmpty else {
            return .empty(message: "No meditation sessions recorded yet.")
        }
        
        let totalMinutes = allSessions.reduce(0) { $0 + $1.actualDurationSeconds } / 60
        let avgDuration = totalMinutes / allSessions.count
        
        let sessionsWithHR = allSessions.filter { $0.hasHeartRateData }
        let avgReduction: Double? = {
            let reductions = sessionsWithHR.compactMap { $0.heartRate?.bpmReduction }
            guard !reductions.isEmpty else { return nil }
            return reductions.reduce(0, +) / Double(reductions.count)
        }()
        
        var summary = "Total meditation stats: \(allSessions.count) sessions, \(totalMinutes) total minutes (avg \(avgDuration) min/session)."
        
        if let reduction = avgReduction {
            summary += " Average heart rate reduction: \(Int(reduction)) bpm per session."
        }
        
        return HistoryQueryResponse(
            success: true,
            sessions: [],
            summary: summary,
            metadata: [
                "totalSessions": allSessions.count,
                "totalMinutes": totalMinutes,
                "avgDuration": avgDuration,
                "avgHRReduction": avgReduction ?? 0
            ]
        )
    }
    
    // MARK: - Search
    
    /// Free-text search across session titles and descriptions
    func search(query: String) -> HistoryQueryResponse {
        let lowercaseQuery = query.lowercased()
        let sessions = historyManager.getAllSessions().filter { session in
            session.title.lowercased().contains(lowercaseQuery) ||
            (session.description?.lowercased().contains(lowercaseQuery) ?? false) ||
            session.tags.contains { $0.lowercased().contains(lowercaseQuery) }
        }
        
        if sessions.isEmpty {
            return .empty(message: "No sessions found matching '\(query)'.")
        }
        
        let summary = "Found \(sessions.count) session(s) matching '\(query)': \(sessions.prefix(5).map { $0.title }.joined(separator: ", "))\(sessions.count > 5 ? "..." : "")."
        
        return HistoryQueryResponse(
            success: true,
            sessions: sessions,
            summary: summary,
            metadata: ["query": query, "count": sessions.count]
        )
    }
    
    // MARK: - AI Context Generation
    
    /// Generate a concise context string for AI prompts
    func generateAIContext(maxSessions: Int = 10) -> String {
        let recentSessions = historyManager.getAllSessions().prefix(maxSessions)
        
        guard !recentSessions.isEmpty else {
            return "User has no meditation history yet."
        }
        
        var context = "User's recent meditation history (\(recentSessions.count) sessions):\n"
        
        for session in recentSessions {
            context += "- \(session.aiSummary())\n"
        }
        
        // Add aggregate stats
        let totalMinutes = historyManager.totalMeditationTimeSeconds / 60
        let totalSessions = historyManager.totalSessionCount
        context += "\nTotal: \(totalSessions) sessions, \(totalMinutes) minutes meditated."
        
        return context
    }
}

