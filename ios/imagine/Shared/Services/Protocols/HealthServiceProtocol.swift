//
//  HealthServiceProtocol.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

/// Protocol defining health data service capabilities.
/// Implementations can wrap HealthKit or any other health data provider.
protocol HealthServiceProtocol {
    /// Requests authorization to access health data.
    /// - Parameter completion: Closure with success flag and optional error.
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void)
    
    /// Saves a mindfulness session to health data.
    /// - Parameters:
    ///   - startDate: The session start time.
    ///   - endDate: The session end time.
    ///   - completion: Closure with success flag and optional error.
    func saveMindfulnessSession(startDate: Date, endDate: Date, completion: @escaping (Bool, Error?) -> Void)
    
    /// Checks if health data is available on this device.
    var isHealthDataAvailable: Bool { get }
}

