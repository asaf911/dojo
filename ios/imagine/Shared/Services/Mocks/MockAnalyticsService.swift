//
//  MockAnalyticsService.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

#if DEBUG
/// Mock analytics service for SwiftUI Previews and testing.
/// All operations are no-ops to prevent network calls and side effects.
final class MockAnalyticsService: AnalyticsServiceProtocol {
    /// @deprecated Use SessionContextManager.shared instead for session tracking.
    var currentPracticeSource: String?
    
    /// Captured events for testing verification (optional).
    private(set) var loggedEvents: [(name: String, parameters: [String: Any]?)] = []
    
    func logEvent(_ name: String, parameters: [String: Any]?) {
        // Capture for testing if needed
        loggedEvents.append((name, parameters))
        // No-op for previews - uncomment for debugging:
        // print("[MockAnalytics] \(name): \(parameters ?? [:])")
    }
    
    /// Clears captured events (for testing).
    func clearEvents() {
        loggedEvents.removeAll()
    }
}
#endif

