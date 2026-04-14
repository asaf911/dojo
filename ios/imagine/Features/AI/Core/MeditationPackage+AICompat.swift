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
        let deepLink = Self.generateDeepLink(from: self)
        return AITimerResponse(
            meditationConfiguration: config,
            deepLink: deepLink,
            description: description ?? title ?? ""
        )
    }

    /// OneLink with `dlv=2` + portable `plan` so fractional / server clip ids replay without catalog rows.
    private static func generateDeepLink(from package: MeditationPackage) -> URL {
        do {
            let plan = PortableTimerDeepLinkPlanV1(package: package)
            return try TimerOneLinkShareURLBuilder.timerShareURL(
                durationMinutes: package.duration,
                backgroundSoundId: package.backgroundSound.id,
                binauralBeatId: package.binauralBeat?.id ?? "None",
                plan: plan,
                campaign: "ai",
                afSub1: package.title ?? "AI Meditation"
            )
        } catch {
            logger.errorMessage("MeditationPackage: portable OneLink encode failed: \(error.localizedDescription)")
            return URL(string: Config.oneLinkBaseURL)!
        }
    }
}
