//
//  MockStatsService.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

#if DEBUG
/// Mock stats service for SwiftUI Previews and testing.
/// Returns configurable statistics without storage dependency.
final class MockStatsService: StatsServiceProtocol {
    
    // Configurable mock values
    var totalSessionDuration: TimeInterval = 3600 * 8   // 8 hours
    var sessionCount: Int = 42
    var longestSessionDuration: TimeInterval = 3600     // 1 hour
    var meditationStreak: Int = 7
    var longestMeditationStreak: Int = 21
    
    /// Creates a mock stats service with default values suitable for previews.
    init(
        totalDuration: TimeInterval = 3600 * 8,
        sessionCount: Int = 42,
        longestSession: TimeInterval = 3600,
        streak: Int = 7,
        longestStreak: Int = 21
    ) {
        self.totalSessionDuration = totalDuration
        self.sessionCount = sessionCount
        self.longestSessionDuration = longestSession
        self.meditationStreak = streak
        self.longestMeditationStreak = longestStreak
    }
    
    func getTotalSessionDuration() -> TimeInterval {
        totalSessionDuration
    }
    
    func getSessionCount() -> Int {
        sessionCount
    }
    
    func getAverageSessionDuration() -> TimeInterval {
        guard sessionCount > 0 else { return 0 }
        return totalSessionDuration / Double(sessionCount)
    }
    
    func getLongestSessionDuration() -> TimeInterval {
        longestSessionDuration
    }
    
    func getMeditationStreak() -> Int {
        meditationStreak
    }
    
    func getLongestMeditationStreak() -> Int {
        longestMeditationStreak
    }
}
#endif

