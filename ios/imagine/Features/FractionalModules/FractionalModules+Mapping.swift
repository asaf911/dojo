//
//  FractionalModules+Mapping.swift
//  Dojo
//
//  Maps `Plan` JSON → `TimerSessionConfig` (second-based cue triggers for fractional playback).
//

import Foundation

extension FractionalModules.Plan {

    func toTimerSessionConfig(
        backgroundSound: BackgroundSound = BackgroundSound(id: "None", name: "None", url: ""),
        binauralBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
    ) -> TimerSessionConfig {
        #if DEBUG
        let tag = "🧠 AI_DEBUG [Fractional][Mapping]"
        print("\(tag) toTimerSessionConfig: planId=\(planId) durationSec=\(durationSec) items=\(items.count)")
        #endif

        let cueSettings = items.map { item in
            let parallelSfx: ParallelSfxCue? = item.parallel.map {
                ParallelSfxCue(id: $0.clipId, name: $0.text ?? $0.clipId, url: $0.url)
            }
            let cue = Cue(id: item.clipId, name: item.text, url: item.url, parallelSfx: parallelSfx)
            if item.atSec == 0 {
                #if DEBUG
                print("\(tag)   cue \(item.clipId) -> .start (atSec=0) role=\(item.role)")
                #endif
                return CueSetting(triggerType: .start, minute: nil, cue: cue)
            }
            #if DEBUG
            print("\(tag)   cue \(item.clipId) -> .second(atSec=\(item.atSec)) role=\(item.role)")
            #endif
            return CueSetting(triggerType: .second, minute: item.atSec, cue: cue)
        }

        let title = FractionalModules.displayTitle(forModuleId: moduleId)
        let minutes = Int(ceil(Double(durationSec) / 60.0))
        #if DEBUG
        print("\(tag) result: minutes=\(minutes) cueSettings=\(cueSettings.count) title=\(title)")
        #endif

        return TimerSessionConfig(
            minutes: minutes,
            backgroundSound: backgroundSound,
            binauralBeat: binauralBeat,
            cueSettings: cueSettings,
            title: title
        )
    }
}
