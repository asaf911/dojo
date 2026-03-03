//
//  DataServiceProtocol.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

/// Protocol defining data persistence service capabilities.
/// Implementations can wrap Firestore, CoreData, or any other data backend.
protocol DataServiceProtocol {
    /// Updates the user's subscription data.
    /// - Parameter data: Dictionary containing subscription details.
    func updateSubscriptionData(_ data: [String: Any])
    
    /// Fetches meditation stats for the last 7 days.
    /// - Parameter completion: Closure returning array of daily stats.
    func fetchLast7DaysStats(completion: @escaping ([DailyStat]) -> Void)
    
    /// Updates daily meditation stats with a new session duration.
    /// - Parameter duration: The duration to add to today's total.
    func updateDailyStats(with duration: TimeInterval)
    
    /// Updates the meditation streak in the backend.
    /// - Parameter streak: The current streak value.
    func updateMeditationStreak(_ streak: Int)
    
    /// Fetches the meditation streak from the backend.
    /// - Parameter completion: Closure returning the current streak.
    func fetchMeditationStreak(completion: @escaping (Int) -> Void)
    
    /// Updates the longest meditation streak in the backend.
    /// - Parameter longestStreak: The longest streak value.
    func updateLongestMeditationStreak(_ longestStreak: Int)
    
    /// Fetches the longest meditation streak from the backend.
    /// - Parameter completion: Closure returning the longest streak.
    func fetchLongestMeditationStreak(completion: @escaping (Int) -> Void)
    
    /// Updates the cumulative meditation time in the backend.
    /// - Parameter totalTime: The total meditation time.
    func updateCumulativeMeditationTime(_ totalTime: Double)
    
    /// Fetches the cumulative meditation time from the backend.
    /// - Parameter completion: Closure returning the total time.
    func fetchCumulativeMeditationTime(completion: @escaping (Double) -> Void)
    
    /// Updates session count in the backend.
    /// - Parameter count: The session count.
    func updateSessionCount(_ count: Int)
    
    /// Fetches session count from the backend.
    /// - Parameter completion: Closure returning the count.
    func fetchSessionCount(completion: @escaping (Int) -> Void)
}

