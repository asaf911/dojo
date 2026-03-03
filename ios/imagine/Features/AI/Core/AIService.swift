import Foundation

// MARK: - Service Response Types (shared by AIRequestManager, MeditationPackage+AICompat)

enum AIMeditationResult {
    case meditation(AITimerResponse)
    case conversationalResponse(String)
}

struct AITimerResponse: Equatable, Codable {
    let meditationConfiguration: MeditationConfiguration
    let deepLink: URL
    let description: String

    static func == (lhs: AITimerResponse, rhs: AITimerResponse) -> Bool {
        lhs.meditationConfiguration.id == rhs.meditationConfiguration.id &&
        lhs.deepLink.absoluteString == rhs.deepLink.absoluteString &&
        lhs.description == rhs.description
    }
}
