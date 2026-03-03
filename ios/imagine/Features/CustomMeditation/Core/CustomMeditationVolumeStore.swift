//
//  CustomMeditationVolumeStore.swift
//  Dojo
//
//  Created by Assistant on 2025-10-03
//

import Foundation
import Combine

final class CustomMeditationVolumeStore: ObservableObject {
    static let shared = CustomMeditationVolumeStore()

    @Published var instructions: Float
    @Published var ambience: Float
    @Published var binaural: Float

    private let instructionsKey = "customMeditation.volume.instructions"
    private let ambienceKey = "customMeditation.volume.ambience"
    private let binauralKey = "customMeditation.volume.binaural"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let defaults = UserDefaults.standard
        // Start centered at 0.5 for all channels so the dots begin in the middle
        instructions = defaults.object(forKey: instructionsKey) as? Float ?? 0.5
        ambience = defaults.object(forKey: ambienceKey) as? Float ?? 0.5
        binaural = defaults.object(forKey: binauralKey) as? Float ?? 0.5

        $instructions.dropFirst().sink { [weak self] value in
            guard let self = self else { return }
            UserDefaults.standard.set(value, forKey: self.instructionsKey)
            logger.eventMessage("🧠 AI_DEBUG volumes instructions=\(value)")
        }.store(in: &cancellables)

        $ambience.dropFirst().sink { [weak self] value in
            guard let self = self else { return }
            UserDefaults.standard.set(value, forKey: self.ambienceKey)
            logger.eventMessage("🧠 AI_DEBUG volumes ambience=\(value)")
        }.store(in: &cancellables)

        $binaural.dropFirst().sink { [weak self] value in
            guard let self = self else { return }
            UserDefaults.standard.set(value, forKey: self.binauralKey)
            logger.eventMessage("🧠 AI_DEBUG volumes binaural=\(value)")
        }.store(in: &cancellables)
    }
}


