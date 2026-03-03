import Foundation

/// Protocol for heart rate data providers.
/// Each provider represents a different source of HR data (AirPods, Watch, HealthKit).
protocol HeartRateProvider: AnyObject {
    /// Priority for this provider (lower = higher priority).
    /// Used when multiple providers are available.
    var priority: Int { get }
    
    /// Whether this provider is currently available for use.
    var isAvailable: Bool { get }
    
    /// The date of the last sample received from this provider.
    var lastSampleDate: Date? { get }

    /// Whether the provider has an active physical BLE/transport connection this session.
    /// Used by the UI to show device-specific "waiting" prompts based on real-time state
    /// rather than static pairing status.
    var isBLEConnected: Bool { get }

    /// Start collecting heart rate data for the given session.
    func start(sessionId: String)
    
    /// Stop collecting heart rate data.
    func stop(sessionId: String)
}

extension HeartRateProvider {
    /// Default: not a BLE device, always false.
    var isBLEConnected: Bool { false }
}

