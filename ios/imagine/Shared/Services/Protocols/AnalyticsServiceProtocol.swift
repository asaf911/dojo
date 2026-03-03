//
//  AnalyticsServiceProtocol.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

/// Protocol defining analytics service capabilities.
/// Implementations can wrap Mixpanel, Firebase Analytics, Amplitude, or any other analytics vendor.
protocol AnalyticsServiceProtocol {
    /// Logs an event with optional parameters.
    /// - Parameters:
    ///   - name: The event name to log.
    ///   - parameters: Optional dictionary of event parameters.
    func logEvent(_ name: String, parameters: [String: Any]?)
    
    /// Tracks the source of the current practice session (e.g., "ai", "explore", "path").
    /// @deprecated Use SessionContextManager.shared instead for session tracking.
    /// Kept for backward compatibility, will be removed in a future version.
    var currentPracticeSource: String? { get set }
}

