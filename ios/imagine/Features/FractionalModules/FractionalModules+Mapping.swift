//
//  FractionalModules+Mapping.swift
//  Dojo
//
//  Maps `Plan` JSON → `TimerSessionConfig` (second-based cue triggers for fractional playback).
//

import Foundation

extension FractionalModules.Plan {

    private static let moduleTitles: [String: String] = [
        "NF_FRAC": "Nostril Focus",
        "IM_FRAC": "I AM Mantra",
        "BS_FRAC": "Body Scan",
        "BS_FRAC_UP": "Body Scan Up",
        "BS_FRAC_DOWN": "Body Scan Down",
    ]

    func toTimerSessionConfig(
        backgroundSound: BackgroundSound = BackgroundSound(id: "None", name: "None", url: ""),
        binauralBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
    ) -> TimerSessionConfig {
        let tag = "🧠 AI_DEBUG [Fractional][Mapping]"
        print("\(tag) toTimerSessionConfig: planId=\(planId) durationSec=\(durationSec) items=\(items.count)")

        let cueSettings = items.map { item in
            let cue = Cue(id: item.clipId, name: item.text, url: item.url)
            if item.atSec == 0 {
                print("\(tag)   cue \(item.clipId) -> .start (atSec=0) role=\(item.role)")
                return CueSetting(triggerType: .start, minute: nil, cue: cue)
            }
            print("\(tag)   cue \(item.clipId) -> .second(atSec=\(item.atSec)) role=\(item.role)")
            return CueSetting(triggerType: .second, minute: item.atSec, cue: cue)
        }

        let title = Self.moduleTitles[moduleId] ?? moduleId
        let minutes = Int(ceil(Double(durationSec) / 60.0))
        print("\(tag) result: minutes=\(minutes) cueSettings=\(cueSettings.count) title=\(title)")

        return TimerSessionConfig(
            minutes: minutes,
            backgroundSound: backgroundSound,
            binauralBeat: binauralBeat,
            cueSettings: cueSettings,
            title: title
        )
    }
}
