//
//  FractionalModules+ViewModel.swift
//  Dojo
//

import Foundation

extension FractionalModules {

    enum Action {
        case playSession(TimerSessionConfig)
    }

    struct Dependencies {
        var service: Service = .live
    }

    @MainActor @Observable
    final class ViewModel {
        nonisolated(unsafe) var moduleId: String
        var selectedMinutes: Int = 3
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
            print("\(tag) play tapped moduleId=\(moduleId) duration=\(selectedMinutes)m")

            Task {
                do {
                    let voiceId = SharedUserStorage.retrieve(
                        forKey: .narrationVoiceId,
                        as: String.self,
                        defaultValue: "Asaf"
                    )
                    print("\(tag) fetchPlan: requesting moduleId=\(moduleId) durationSec=\(selectedMinutes * 60) voiceId=\(voiceId)")

                    let scanTier = moduleId == "BS_FRAC" ? "long" : nil
                    let plan = try await dependencies.service.fetchPlan(
                        moduleId,
                        selectedMinutes * 60,
                        voiceId,
                        scanTier,
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
