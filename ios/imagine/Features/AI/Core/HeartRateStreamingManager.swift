import Foundation
import Combine

/// Bridges watch heart rate messages (forwarded by PhoneConnectivityManager) into a typed stream of HRSample values.
final class HeartRateStreamingManager: NSObject, ObservableObject {
    static let shared = HeartRateStreamingManager()

    private let samplesSubject = PassthroughSubject<HRSample, Never>()
    private var currentSessionId: String?

    var samplesPublisher: AnyPublisher<HRSample, Never> {
        samplesSubject.eraseToAnyPublisher()
    }

    func begin(sessionId: String) -> AnyPublisher<HRSample, Never> {
        currentSessionId = sessionId
        return samplesPublisher
    }

    func end(sessionId: String) {
        if currentSessionId == sessionId { currentSessionId = nil }
    }

    func ingest(bpm: Double, timestamp: TimeInterval) {
        samplesSubject.send(HRSample(timestamp: timestamp, bpm: bpm))
    }
}


