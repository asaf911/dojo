//
//  MockDataService.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

#if DEBUG
/// Mock data service for SwiftUI Previews and testing.
/// Returns sensible defaults without Firestore dependency.
final class MockDataService: DataServiceProtocol {
    
    // Configurable mock data
    var mockDailyStats: [DailyStat] = []
    var mockMeditationStreak: Int = 5
    var mockLongestStreak: Int = 12
    var mockCumulativeTime: Double = 3600 * 10 // 10 hours
    var mockSessionCount: Int = 25
    
    init() {
        // Generate mock stats for last 7 days
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        mockDailyStats = (0..<7).compactMap { dayOffset -> DailyStat? in
            guard let date = calendar.date(byAdding: .day, value: -6 + dayOffset, to: today) else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let id = formatter.string(from: date)
            // Random duration between 0 and 30 minutes
            let duration = Double.random(in: 0...1800)
            return DailyStat(id: id, date: date, totalDuration: duration)
        }
    }
    
    func updateSubscriptionData(_ data: [String: Any]) {
        // No-op for previews
    }
    
    func fetchLast7DaysStats(completion: @escaping ([DailyStat]) -> Void) {
        completion(mockDailyStats)
    }
    
    func updateDailyStats(with duration: TimeInterval) {
        // No-op for previews
    }
    
    func updateMeditationStreak(_ streak: Int) {
        mockMeditationStreak = streak
    }
    
    func fetchMeditationStreak(completion: @escaping (Int) -> Void) {
        completion(mockMeditationStreak)
    }
    
    func updateLongestMeditationStreak(_ longestStreak: Int) {
        mockLongestStreak = longestStreak
    }
    
    func fetchLongestMeditationStreak(completion: @escaping (Int) -> Void) {
        completion(mockLongestStreak)
    }
    
    func updateCumulativeMeditationTime(_ totalTime: Double) {
        mockCumulativeTime = totalTime
    }
    
    func fetchCumulativeMeditationTime(completion: @escaping (Double) -> Void) {
        completion(mockCumulativeTime)
    }
    
    func updateSessionCount(_ count: Int) {
        mockSessionCount = count
    }
    
    func fetchSessionCount(completion: @escaping (Int) -> Void) {
        completion(mockSessionCount)
    }
}
#endif

