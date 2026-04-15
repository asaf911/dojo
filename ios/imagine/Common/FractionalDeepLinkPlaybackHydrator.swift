//
//  FractionalDeepLinkPlaybackHydrator.swift
//  imagine
//
//  Deep links often carry catalog surface ids (`INT_FRAC`, `PB_FRAC`, `BS_FRAC_DOWN`, …) with short placeholder URLs.
//  Playing from Timer after POST /meditations uses server-expanded atomic clips. This hydrator closes that gap
//  by calling `POST /postFractionalPlan` per collapsed module (dev / `useDevServer` + Blaze) and merging results.
//

import Foundation

enum FractionalDeepLinkPlaybackHydrator {

    /// Module rows that must be expanded for full playback (matches server `FRACTIONAL_MODULE_MAP` surface ids).
    private static let collapsedModuleIds: Set<String> = [
        "INT_FRAC",
        "PB_FRAC",
        "IM_FRAC",
        "NF_FRAC",
        "BS_FRAC",
        "BS_FRAC_UP",
        "BS_FRAC_DOWN",
        "MV_KM_FRAC",
        "MV_GR_FRAC",
        "EV_KM_FRAC",
        "EV_GR_FRAC",
    ]

    /// Returns the config unchanged when already atomic, offline-only, or expansion fails.
    static func hydrateIfNeeded(_ config: TimerSessionConfig) async -> TimerSessionConfig {
        let useDev = SharedUserStorage.retrieve(forKey: .useDevServer, as: Bool.self, defaultValue: false)
        let ids = config.cueSettings.map(\.cue.id).joined(separator: ",")
        logger.timerDeepLink(
            "hydrate_enter cues=\(config.cueSettings.count) useDevServer=\(useDev) server=\(Config.serverLabel) fractionalURLHost=\(Config.fractionalPlanURL.host ?? "?") ids=[\(ids)]"
        )

        guard config.isDeepLinked else {
            logger.timerDeepLink("hydrate_skip reason=not_deep_linked")
            return config
        }
        guard needsHydration(config.cueSettings) else {
            let hasCollapsed = config.cueSettings.contains { collapsedModuleIds.contains($0.cue.id) }
            if !hasCollapsed {
                logger.timerDeepLink("hydrate_skip reason=no_collapsed_frac_modules")
            } else {
                logger.timerDeepLink("hydrate_skip reason=already_atomic_timeline")
            }
            return config
        }

        let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
        let playbackCap = config.playbackDurationSeconds ?? (config.minutes * 60)
        let sorted = config.cueSettings.sorted { a, b in
            wallStartSeconds(a, playbackCap: playbackCap) < wallStartSeconds(b, playbackCap: playbackCap)
        }

        var kept: [CueSetting] = []
        kept.reserveCapacity(config.cueSettings.count)
        var expanded: [CueSetting] = []

        for setting in sorted {
            guard collapsedModuleIds.contains(setting.cue.id) else {
                kept.append(setting)
                continue
            }

            let startSec = wallStartSeconds(setting, playbackCap: playbackCap)
            let endSec = nextWallStartAfter(startSec, in: sorted, playbackCap: playbackCap)
            let spanUntilNext = max(60, endSec - startSec)
            // `postFractionalPlan` for INT_FRAC expects full practice length (see functions `index.ts`); other modules use the wall-time window.
            let durationSecForPlan: Int = {
                if setting.cue.id == "INT_FRAC" {
                    return min(1200, max(60, playbackCap))
                }
                return spanUntilNext
            }()
            let atTimelineStart = (startSec == 0)

            let bodyScan: (
                direction: String,
                introShort: Bool,
                introLong: Bool,
                includeEntry: Bool
            )? = {
                let id = setting.cue.id
                guard id == "BS_FRAC" || id == "BS_FRAC_UP" || id == "BS_FRAC_DOWN" else { return nil }
                let apiDirection: String = {
                    if id == "BS_FRAC_UP" { return "down" }
                    if id == "BS_FRAC_DOWN" { return "up" }
                    return "down"
                }()
                return (direction: apiDirection, introShort: true, introLong: false, includeEntry: true)
            }()

            do {
                let plan = try await FractionalModules.Service.live.fetchPlan(
                    setting.cue.id,
                    durationSecForPlan,
                    voiceId,
                    bodyScan,
                    atTimelineStart,
                    "FractionalDeepLinkPlaybackHydrator|hydrate"
                )
                expanded.append(contentsOf: cueSettings(from: plan, wallOffset: startSec))
                logger.timerDeepLink(
                    "hydrate_module_ok id=\(setting.cue.id) wallStart=\(startSec)s durationSec=\(durationSecForPlan) spanNext=\(spanUntilNext) planItems=\(plan.items.count) atTimelineStart=\(atTimelineStart)"
                )
            } catch {
                logger.timerDeepLinkError(
                    "hydrate_module_fail id=\(setting.cue.id) durationSec=\(durationSecForPlan) err=\(error.localizedDescription) — keeping collapsed row"
                )
                kept.append(setting)
            }
        }

        let merged = (kept + expanded).sorted { a, b in
            let ta = wallStartSeconds(a, playbackCap: playbackCap)
            let tb = wallStartSeconds(b, playbackCap: playbackCap)
            if ta != tb { return ta < tb }
            return a.cue.id < b.cue.id
        }

        logger.timerDeepLink("hydrate_done merged_cues=\(merged.count) (was \(config.cueSettings.count))")

        return TimerSessionConfig(
            minutes: config.minutes,
            playbackDurationSeconds: config.playbackDurationSeconds,
            backgroundSound: config.backgroundSound,
            binauralBeat: config.binauralBeat,
            cueSettings: merged,
            isDeepLinked: config.isDeepLinked,
            title: config.title,
            description: config.description
        )
    }

    private static func needsHydration(_ settings: [CueSetting]) -> Bool {
        let hasCollapsed = settings.contains { collapsedModuleIds.contains($0.cue.id) }
        guard hasCollapsed else { return false }
        return !containsAtomicFractionalTimeline(settings)
    }

    private static func containsAtomicFractionalTimeline(_ settings: [CueSetting]) -> Bool {
        settings.contains { s in
            let id = s.cue.id
            if id == "INT_FRAC" { return false }
            if id.hasPrefix("PBV_") || id.hasPrefix("PBS_") { return true }
            if id.hasPrefix("NF_C") || id.hasPrefix("IM_C") { return true }
            if id.hasPrefix("BS_MAC_") || id.hasPrefix("BS_SYS_") { return true }
            if id.hasPrefix("INT_GRT_") || id.hasPrefix("INT_ARR_") || id.hasPrefix("INT_ORI_") { return true }
            if id.hasPrefix("MVK_") || id.hasPrefix("MVG_") { return true }
            return false
        }
    }

    private static func wallStartSeconds(_ setting: CueSetting, playbackCap: Int) -> Int {
        switch setting.triggerType {
        case .start:
            return 0
        case .minute:
            return (setting.minute ?? 0) * 60
        case .second:
            return setting.minute ?? 0
        case .end:
            return playbackCap
        }
    }

    private static func nextWallStartAfter(
        _ startSec: Int,
        in sorted: [CueSetting],
        playbackCap: Int
    ) -> Int {
        var best: Int? = nil
        for s in sorted {
            let t = wallStartSeconds(s, playbackCap: playbackCap)
            if t > startSec {
                best = best.map { min($0, t) } ?? t
            }
        }
        return best ?? playbackCap
    }

    private static func cueSettings(from plan: FractionalModules.Plan, wallOffset: Int) -> [CueSetting] {
        plan.items.map { item in
            let parallel = item.parallel.map {
                ParallelSfxCue(id: $0.clipId, name: $0.text ?? $0.clipId, url: $0.url)
            }
            let cue = Cue(id: item.clipId, name: item.text, url: item.url, parallelSfx: parallel)
            let wall = wallOffset + item.atSec
            return CueSetting(triggerType: .second, minute: wall, cue: cue)
        }
    }
}
