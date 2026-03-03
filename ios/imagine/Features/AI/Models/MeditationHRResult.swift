import Foundation

public struct MeditationHRResult: Codable, Equatable {
    public let sessionId: String
    public let baselineBPM: Double
    public let minBPM: Double
    public let deltaFromBaseline: Double
    public let relaxationScore: Double
    public let stabilityScore: Double
    public let recoveryIndex: Double
    public let hrvSDNNms: Double?

    public init(
        sessionId: String,
        baselineBPM: Double,
        minBPM: Double,
        deltaFromBaseline: Double,
        relaxationScore: Double,
        stabilityScore: Double,
        recoveryIndex: Double,
        hrvSDNNms: Double?
    ) {
        self.sessionId = sessionId
        self.baselineBPM = baselineBPM
        self.minBPM = minBPM
        self.deltaFromBaseline = deltaFromBaseline
        self.relaxationScore = relaxationScore
        self.stabilityScore = stabilityScore
        self.recoveryIndex = recoveryIndex
        self.hrvSDNNms = hrvSDNNms
    }
}



