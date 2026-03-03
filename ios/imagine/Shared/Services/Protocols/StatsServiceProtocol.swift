//
//  StatsServiceProtocol.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

/// Protocol defining statistics service capabilities.
/// Provides access to user meditation statistics and metrics.
protocol StatsServiceProtocol {
    /// Returns the total duration of all meditation sessions.
    func getTotalSessionDuration() -> TimeInterval
    
    /// Returns the total number of completed sessions.
    func getSessionCount() -> Int
    
    /// Returns the average session duration.
    func getAverageSessionDuration() -> TimeInterval
    
    /// Returns the longest single session duration.
    func getLongestSessionDuration() -> TimeInterval
    
    /// Returns the current meditation streak (consecutive days).
    func getMeditationStreak() -> Int
    
    /// Returns the longest meditation streak ever achieved.
    func getLongestMeditationStreak() -> Int
}

