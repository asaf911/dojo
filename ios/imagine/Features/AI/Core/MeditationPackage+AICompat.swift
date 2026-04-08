//
//  MeditationPackage+AICompat.swift
//  imagine
//
//  Converts server MeditationPackage to AITimerResponse for AI chat flow.
//

import Foundation

extension MeditationPackage {
    /// Converts server response to AITimerResponse for AIRequestManager and chat UI.
    func toAITimerResponse() -> AITimerResponse {
        let backgroundSound = BackgroundSound(
            id: backgroundSound.id,
            name: backgroundSound.name,
            url: backgroundSound.url
        )
        let binauralBeat: BinauralBeat?
        if let bb = self.binauralBeat {
            binauralBeat = BinauralBeat(
                id: bb.id,
                name: bb.name,
                url: bb.url,
                description: bb.description
            )
        } else {
            binauralBeat = nil
        }
        let cueSettings = cues.map { mc -> CueSetting in
            let cue = Cue(id: mc.id, name: mc.name, url: mc.url, parallelSfx: mc.parallelSfx)
            switch mc.trigger {
            case .start:
                return CueSetting(triggerType: .start, minute: nil, cue: cue)
            case .end:
                return CueSetting(triggerType: .end, minute: nil, cue: cue)
            case .minute(let m):
                return CueSetting(triggerType: .minute, minute: m, cue: cue)
            case .second(let s):
                return CueSetting(triggerType: .second, minute: s, cue: cue)
            }
        }
        let config = MeditationConfiguration(
            duration: duration,
            backgroundSound: backgroundSound,
            cueSettings: cueSettings,
            title: title,
            binauralBeat: binauralBeat
        )
        let deepLink = Self.generateDeepLink(from: config)
        return AITimerResponse(
            meditationConfiguration: config,
            deepLink: deepLink,
            description: description ?? title ?? ""
        )
    }

    private static func generateDeepLink(from configuration: MeditationConfiguration) -> URL {
        let baseURL = Config.oneLinkBaseURL
        var components = URLComponents(string: baseURL)

        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ":,"))
        let durValue = "\(configuration.duration)".addingPercentEncoding(withAllowedCharacters: allowed)
        let bsEncoded = configuration.backgroundSound.id.addingPercentEncoding(withAllowedCharacters: allowed)

        let cuRawValue = configuration.cueSettings.compactMap { cueSetting -> String? in
            let id = cueSetting.cue.id
            let trigger: String
            switch cueSetting.triggerType {
            case .start: trigger = "S"
            case .end: trigger = "E"
            case .minute: trigger = "\(cueSetting.minute ?? 0)"
            case .second: trigger = "s\(cueSetting.minute ?? 0)"
            }
            return "\(id):\(trigger)"
        }.joined(separator: ",")

        let cuEncoded = cuRawValue.addingPercentEncoding(withAllowedCharacters: allowed)
        let bbId = configuration.binauralBeat?.id ?? "None"
        let bbEncoded = bbId.addingPercentEncoding(withAllowedCharacters: allowed)
        let meditationName = configuration.title ?? "AI Meditation"

        components?.queryItems = [
            URLQueryItem(name: "dur", value: durValue),
            URLQueryItem(name: "bs", value: bsEncoded),
            URLQueryItem(name: "bb", value: bbEncoded),
            URLQueryItem(name: "cu", value: cuEncoded),
            URLQueryItem(name: "c", value: "ai"),
            URLQueryItem(name: "af_sub1", value: meditationName),
        ]

        return components?.url ?? URL(string: baseURL)!
    }
}
