import Foundation

public struct HRSample: Codable, Equatable {
    public let timestamp: TimeInterval
    public let bpm: Double

    public init(timestamp: TimeInterval, bpm: Double) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}


