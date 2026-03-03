import Foundation

/// Thin wrapper around SimplifiedAIService for meditation generation.
/// No post-processing rules - AI output is trusted with validation.
final class AIMeditationGenerator {
    private let simplified = SimplifiedAIService()

    struct Request {
        let prompt: String
        let history: [ChatMessage]
        var maxDuration: Int? = nil
    }

    func generate(_ req: Request) async throws -> AIMeditationResult {
        logger.aiChat("🧠 AI_DEBUG GEN start prompt_len=\(req.prompt.count) hist=\(req.history.count) maxDuration=\(req.maxDuration?.description ?? "nil")")
        
        // Generate meditation directly - no post-processing rules
        let result = try await simplified.generateMeditation(
            prompt: req.prompt,
            conversationHistory: req.history,
            maxDuration: req.maxDuration
        )
        
        switch result {
        case .meditation(let response):
            logger.aiChat("🧠 AI_DEBUG GEN complete dur=\(response.meditationConfiguration.duration) bg=\(response.meditationConfiguration.backgroundSound.id) cues=\(response.meditationConfiguration.cueSettings.count)")
            
            // Avoid repeating the last-used soundscape
            var finalResponse = response
            let lastKey = "imagine.lastSoundscapeId"
            if let lastId = UserDefaults.standard.string(forKey: lastKey),
               response.meditationConfiguration.backgroundSound.id == lastId {
                if let alt = BackgroundSoundManager.shared.sounds.first(where: { $0.id != lastId && $0.id != "None" }) {
                    let newConfig = MeditationConfiguration(
                        duration: response.meditationConfiguration.duration,
                        backgroundSound: alt,
                        cueSettings: response.meditationConfiguration.cueSettings,
                        title: response.meditationConfiguration.title,
                        binauralBeat: response.meditationConfiguration.binauralBeat
                    )
                    finalResponse = AITimerResponse(
                        meditationConfiguration: newConfig,
                        deepLink: response.deepLink,
                        description: response.description
                    )
                    logger.aiChat("🧠 AI_DEBUG GEN soundscape_swap \(lastId) -> \(alt.id)")
                }
            }
            
            // Persist the choice
            if finalResponse.meditationConfiguration.backgroundSound.id != "None" {
                UserDefaults.standard.set(finalResponse.meditationConfiguration.backgroundSound.id, forKey: lastKey)
            }
            
            return .meditation(finalResponse)
            
        case .conversationalResponse:
            logger.aiChat("🧠 AI_DEBUG GEN routed_to=conversation")
            return result
        }
    }

    /// Converts an AITimerResponse back to AIGeneratedTimer for compatibility
    static func toAIGeneratedTimer(from response: AITimerResponse) -> AIGeneratedTimer {
        let bgId = response.meditationConfiguration.backgroundSound.id
        let bbId = response.meditationConfiguration.binauralBeat?.id
        let cues: [AIGeneratedTimer.AICue] = response.meditationConfiguration.cueSettings.map { setting in
            let trig: String
            switch setting.triggerType {
            case .start: trig = "start"
            case .end: trig = "end"
            case .minute: trig = String(setting.minute ?? 1)
            }
            return .init(id: setting.cue.id, trigger: trig)
        }
        return AIGeneratedTimer(
            duration: response.meditationConfiguration.duration,
            backgroundSoundId: bgId,
            binauralBeatId: bbId,
            cues: cues,
            segments: nil,
            title: response.meditationConfiguration.title ?? "",
            description: response.description
        )
    }
}
