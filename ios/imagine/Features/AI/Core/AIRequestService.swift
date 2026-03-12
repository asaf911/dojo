//
//  AIRequestService.swift
//  imagine
//
//  Unified AI request: POST /ai/request — classify, route, respond.
//  QA: Filter console logs by "[Server][AI]" to trace.
//

import Foundation

private let kTag = "[Server][AI]"

/// Context sent with AI request for path/explore guidance and meditation modifications
struct AIServerRequestContext: Encodable {
    var pathInfo: PathInfo?
    var exploreInfo: ExploreInfo?
    /// Duration of last meditation; used when user modifies (e.g. "remove breathwork") so server preserves duration
    var lastMeditationDuration: Int?
    /// Last N background sound IDs used; server down-weights these for variety
    var recentBackgroundSounds: [String]?

    struct PathInfo: Encodable {
        let nextStepTitle: String
        let completedCount: Int
        let totalCount: Int
        let allCompleted: Bool
    }

    struct ExploreInfo: Encodable {
        let sessionTitle: String
        let timeOfDay: String
    }
}

/// Response from POST /ai/request
struct AIRequestResponse: Decodable {
    let intent: String
    let content: Content

    enum Content: Decodable {
        case meditation(MeditationPackage)
        case text(String)
        case history(historyQueryType: String?)

        enum CodingKeys: String, CodingKey {
            case type
            case meditation
            case text
            case historyQueryType
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "meditation":
                let pkg = try container.decode(MeditationPackage.self, forKey: .meditation)
                self = .meditation(pkg)
            case "text":
                let t = try container.decode(String.self, forKey: .text)
                self = .text(t)
            case "history":
                let historyQueryType = try container.decodeIfPresent(String.self, forKey: .historyQueryType)
                self = .history(historyQueryType: historyQueryType)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown content type: \(type)"
                )
            }
        }
    }
}

private struct AIRequestBody: Encodable {
    let prompt: String
    let voiceId: String?
    let conversationHistory: [[String: String]]
    let context: AIServerRequestContext?
}

/// Service for unified AI requests (classify + route + respond)
struct AIRequestService {
    static let shared = AIRequestService()

    private init() {}

    /// Process AI request via POST /ai/request. Requires network.
    func processAIRequest(
        prompt: String,
        conversationHistory: [ConversationHistoryItem],
        context: AIServerRequestContext?,
        triggerContext: String
    ) async throws -> AIRequestResponse {
        let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
        print("\(kTag) request start trigger=\(triggerContext) server=\(Config.serverLabel) promptLen=\(prompt.count) historyLen=\(conversationHistory.count) voiceId=\(voiceId)")
        var request = URLRequest(url: Config.aiRequestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(triggerContext, forHTTPHeaderField: "X-Trigger")
        let historyItems = conversationHistory.map { ["role": $0.role, "content": $0.content] }
        let body = AIRequestBody(
            prompt: prompt,
            voiceId: voiceId,
            conversationHistory: historyItems,
            context: context
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("\(kTag) request failure trigger=\(triggerContext) - invalid response type")
            throw NSError(domain: "AIRequestService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        if http.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            print("\(kTag) request failure trigger=\(triggerContext) status=\(http.statusCode) error=\(String(bodyStr.prefix(200)))")
            throw NSError(domain: "AIRequestService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error: \(http.statusCode)"])
        }
        do {
            let decoded = try JSONDecoder().decode(AIRequestResponse.self, from: data)
            print("\(kTag) request success trigger=\(triggerContext) server=\(Config.serverLabel) intent=\(decoded.intent)")
            if case .meditation(let pkg) = decoded.content {
                let cuePaths = pkg.cues.map { "\($0.id)=\($0.url.split(separator: "/").last.map(String.init) ?? $0.url)" }.joined(separator: " ")
                print("\(kTag) meditation received voiceId=\(voiceId) duration=\(pkg.duration) cues=[\(cuePaths)]")
            }
            return decoded
        } catch {
            print("\(kTag) request failure trigger=\(triggerContext) decode error - \(error.localizedDescription)")
            throw error
        }
    }
}
