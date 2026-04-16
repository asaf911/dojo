//
//  SenseiMeditationBlueprintID.swift
//  imagine
//
//  Stable ids for Cloud Functions `meditationBlueprints.ts` (`BLUEPRINT_IDS`).
//  When adding a scenario on the server, add a case here and wire the client path
//  that should send `AIServerRequestContext.blueprintId`.
//

import Foundation

enum SenseiMeditationBlueprintID: String {
    case timelyMorning = "timely.morning"
    case timelyNoon = "timely.noon"
    case timelyEvening = "timely.evening"
    case timelyNight = "timely.night"
    case timelySleep = "timely.sleep"
    case scenarioPreImportantEvent = "scenario.pre_important_event"
}

extension ExploreRecommendationManager.TimeOfDay {
    /// Theme tags merged server-side with prompt-derived themes (`meditationThemes` request field).
    var senseiMeditationThemeTags: [String] {
        switch self {
        case .morning: return ["morning"]
        case .noon: return ["noon"]
        case .evening: return ["evening"]
        case .night: return ["night"]
        }
    }

    /// Optional explicit blueprint for `/ai/request` and `/meditations` AI path.
    var senseiMeditationBlueprintId: SenseiMeditationBlueprintID {
        switch self {
        case .morning: return .timelyMorning
        case .noon: return .timelyNoon
        case .evening: return .timelyEvening
        case .night: return .timelyNight
        }
    }
}
