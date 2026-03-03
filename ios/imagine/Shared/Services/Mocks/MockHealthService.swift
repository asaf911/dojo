//
//  MockHealthService.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

#if DEBUG
/// Mock health service for SwiftUI Previews and testing.
/// Simulates HealthKit operations without actual device access.
final class MockHealthService: HealthServiceProtocol {
    
    /// Whether authorization has been granted in the mock.
    var isAuthorized: Bool = true
    
    /// Whether health data is available (simulates device capability).
    var isHealthDataAvailable: Bool = true
    
    /// Saved sessions for testing verification.
    private(set) var savedSessions: [(startDate: Date, endDate: Date)] = []
    
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        // Simulate successful authorization for previews
        completion(isAuthorized, nil)
    }
    
    func saveMindfulnessSession(startDate: Date, endDate: Date, completion: @escaping (Bool, Error?) -> Void) {
        if isAuthorized {
            savedSessions.append((startDate, endDate))
            completion(true, nil)
        } else {
            let error = NSError(
                domain: "MockHealthService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not authorized"]
            )
            completion(false, error)
        }
    }
    
    /// Clears saved sessions (for testing).
    func clearSessions() {
        savedSessions.removeAll()
    }
}
#endif

