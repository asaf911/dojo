import Foundation

public struct MeditationSensorSession: Codable, Equatable {
    public let id: String
    public let start: Date
    public var end: Date?
    public let deviceInfo: String

    public init(id: String, start: Date, end: Date? = nil, deviceInfo: String) {
        self.id = id
        self.start = start
        self.end = end
        self.deviceInfo = deviceInfo
    }
}



