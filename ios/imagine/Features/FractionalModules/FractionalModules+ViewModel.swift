//
//  FractionalModules+ViewModel.swift
//  Dojo
//
//  Dev/QA: composes fractional playback via POST /postFractionalPlan.
//  Sends atTimelineStart=true (module is first on the session timeline). See docs/fractional-module-intro-rule.md.
//  Body scan (BS_FRAC): server doc `docs/body-scan-tier-composer.md` — picker “Up”/“Down” maps to composer
//  direction (see `apiDirection`). State + `play()` only; no SwiftUI import (.cursorrules).
//

import Foundation

extension FractionalModules {

    enum Action {
        case playSession(TimerSessionConfig)
    }

    enum BodyScanDirection: String, CaseIterable {
        case up = "up"
        case down = "down"
    }

    struct Dependencies {
        var service: Service = .live
    }

    @MainActor @Observable
    final class ViewModel {
        nonisolated(unsafe) var moduleId: String
        var selectedMinutes: Int = 3
        var bodyScanDirection: BodyScanDirection = .up
        var includeIntroShort: Bool = true
        var includeIntroLong: Bool = false
        var includeBodyScanEntry: Bool = true
        var isLoading = false
        var errorMessage: String?

        var onAction: ((Action) -> Void)?

        private nonisolated(unsafe) let dependencies: Dependencies

        nonisolated init(moduleId: String = "NF_FRAC", dependencies: Dependencies = Dependencies()) {
            self.moduleId = moduleId
            self.dependencies = dependencies
        }

        func play() {
            guard !isLoading else { return }
            isLoading = true
            errorMessage = nil

            let tag = "🧠 AI_DEBUG [Fractional][ViewModel]"
            let sessionSec = selectedMinutes * 60
            print("\(tag) play tapped moduleId=\(moduleId) sessionDurationSec=\(sessionSec)")

            Task {
                do {
                    let voiceId = SharedUserStorage.retrieve(
                        forKey: .narrationVoiceId,
                        as: String.self,
                        defaultValue: "Asaf"
                    )
                    let durationSec = selectedMinutes * 60
                    print("\(tag) fetchPlan: requesting moduleId=\(moduleId) sessionDurationSec=\(durationSec) voiceId=\(voiceId)")

                    let bodyScan: (
                        direction: String,
                        introShort: Bool,
                        introLong: Bool,
                        includeEntry: Bool
                    )? = {
                        guard moduleId == "BS_FRAC" else { return nil }
                        // Picker Up = bottom→top → composer "down"; Down = top→bottom → composer "up"
                        let apiDirection = bodyScanDirection == .up ? "down" : "up"
                        return (
                            direction: apiDirection,
                            introShort: includeIntroShort,
                            introLong: includeIntroLong,
                            includeEntry: includeBodyScanEntry
                        )
                    }()
                    let plan = try await dependencies.service.fetchPlan(
                        moduleId,
                        durationSec,
                        voiceId,
                        bodyScan,
                        true,
                        "FractionalModules|play"
                    )

                    print("\(tag) fetchPlan: received planId=\(plan.planId) items=\(plan.items.count)")

                    let config = plan.toTimerSessionConfig()
                    print("\(tag) mapped to TimerSessionConfig: minutes=\(config.minutes) cueSettings=\(config.cueSettings.count)")

                    isLoading = false
                    onAction?(.playSession(config))
                    print("\(tag) action emitted -> navigating to player")
                } catch {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    print("\(tag) ERROR fetchPlan failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
