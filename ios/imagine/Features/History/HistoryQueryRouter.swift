//
//  HistoryQueryRouter.swift
//  Dojo
//
//  Executes history queries based on natural language input.
//  Intent detection is handled by server (POST /ai/request); client runs local query when intent=history.
//

import Foundation

// MARK: - Query Router

final class HistoryQueryRouter {
    static let shared = HistoryQueryRouter()
    
    private let queryService = SessionHistoryQuery.shared
    
    private init() {}
    
    // MARK: - Query Execution
    
    /// Execute a history query based on natural language input
    func executeQuery(for prompt: String) -> HistoryQueryResponse {
        print("🧠 AI_DEBUG HISTORY executeQuery prompt='\(prompt)'")
        let lower = prompt.lowercased()
        
        // Average heart rate queries
        if containsAny(lower, ["average heart rate", "avg heart rate", "average hr", "avg hr", "average bpm", "avg bpm", "mean heart rate", "mean hr"]) {
            if containsAny(lower, ["start", "begin", "before", "when i start", "at the start", "starting"]) {
                return queryService.averageStartHeartRate()
            } else if containsAny(lower, ["end", "finish", "after", "when i end", "at the end", "ending"]) {
                return queryService.averageEndHeartRate()
            } else if containsAny(lower, ["reduction", "drop", "decrease", "change", "improve"]) {
                return queryService.averageHeartRateReduction()
            }
            return queryService.heartRateTrend()
        }
        
        // Heart rate extremes
        if containsAny(lower, ["lowest heart rate", "lowest hr", "lowest bpm", "lowest ending", "best relaxation"]) {
            return queryService.lowestEndHeartRate()
        }
        
        if containsAny(lower, ["highest heart rate", "highest hr", "highest bpm", "highest starting", "most stressed"]) {
            return queryService.highestStartHeartRate()
        }
        
        if containsAny(lower, ["best reduction", "biggest drop", "most reduced", "best hr change", "greatest decrease"]) {
            return queryService.bestHeartRateReduction()
        }
        
        if containsAny(lower, ["heart rate trend", "hr trend", "bpm trend", "heart rate over time", "heart rate progress"]) {
            return queryService.heartRateTrend()
        }
        
        // Generic heart rate query - show trend/averages
        if containsAny(lower, ["heart rate", "hr", "bpm"]) {
            return queryService.heartRateTrend()
        }
        
        // Duration queries
        if containsAny(lower, ["longest session", "longest meditation", "longest practice"]) {
            return queryService.longestSession()
        }
        
        if containsAny(lower, ["shortest session", "shortest meditation", "shortest practice"]) {
            return queryService.shortestSession()
        }
        
        // Recency queries
        if containsAny(lower, ["most recent", "last session", "latest meditation", "last meditation", "last practice"]) {
            return queryService.mostRecentSession()
        }
        
        // Time period queries
        if let days = extractDayCount(from: lower) {
            return queryService.sessionsInLastDays(days)
        }
        
        if lower.contains("today") {
            return queryService.sessionsOnDate(Date())
        }
        
        if lower.contains("yesterday") {
            if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
                return queryService.sessionsOnDate(yesterday)
            }
        }
        
        if lower.contains("this week") {
            return queryService.sessionsInLastDays(7)
        }
        
        if lower.contains("this month") {
            return queryService.sessionsInLastDays(30)
        }
        
        // Type queries
        if containsAny(lower, ["guided meditation", "guided session", "guided practice"]) {
            return queryService.sessionsByType(.guided)
        }
        
        if containsAny(lower, ["custom meditation", "custom session", "timer session"]) {
            return queryService.sessionsByType(.custom)
        }
        
        if containsAny(lower, ["ai meditation", "ai session", "ai generated", "ai-generated"]) {
            return queryService.sessionsByType(.aiGenerated)
        }
        
        // Stats queries
        if containsAny(lower, ["total", "statistics", "stats", "overall", "summary", "how many session", "how much time"]) {
            return queryService.totalStats()
        }
        
        // Category/tag queries
        if let topic = extractSearchTopic(from: lower) {
            return queryService.sessionsWithTag(topic)
        }
        
        // Search
        let searchTerms = extractSearchTerms(from: prompt)
        if !searchTerms.isEmpty {
            return queryService.search(query: searchTerms)
        }
        
        // Default: show overall stats
        print("🧠 AI_DEBUG HISTORY executeQuery fallback to totalStats")
        return queryService.totalStats()
    }
    
    /// Format a query response for display in chat
    func formatForAIResponse(_ response: HistoryQueryResponse) -> String {
        print("🧠 AI_DEBUG HISTORY formatForAIResponse success=\(response.success) sessionCount=\(response.sessions.count)")
        return response.summary
    }
    
    // MARK: - Private Helpers
    
    private func containsAny(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }
    
    private func extractDayCount(from text: String) -> Int? {
        let patterns = [
            #"last\s+(\d+)\s+days?"#,
            #"past\s+(\d+)\s+days?"#,
            #"(\d+)\s+days?\s+ago"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: text),
               let days = Int(text[range]) {
                return days
            }
        }
        return nil
    }
    
    private func extractSearchTopic(from text: String) -> String? {
        let patterns = [
            #"(?:session|meditation|practice)s?\s+(?:about|for|with|on)\s+(\w+)"#,
            #"(?:about|for|with|on)\s+(\w+)\s+(?:session|meditation|practice)"#,
            #"(\w+)\s+(?:session|meditation|practice)s?"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: text) {
                let topic = String(text[range])
                let skipWords = ["my", "the", "a", "an", "any", "some", "this", "that", "which", "what"]
                if !skipWords.contains(topic.lowercased()) {
                    return topic
                }
            }
        }
        return nil
    }
    
    private func extractSearchTerms(from text: String) -> String {
        var cleaned = text.lowercased()
        let removeWords = [
            "what", "when", "which", "how", "did", "do", "does", "was", "were", "is", "are",
            "my", "the", "a", "an", "i", "have", "had", "has", "about", "with", "for",
            "session", "sessions", "meditation", "meditations", "practice", "practices",
            "tell", "me", "show", "find", "?", "please"
        ]
        
        for word in removeWords {
            cleaned = cleaned.replacingOccurrences(of: "\\b\(word)\\b", with: " ", options: .regularExpression)
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
