//
//  FractionalModules+Models.swift
//  Dojo
//

import Foundation

enum FractionalModules {}

extension FractionalModules {

    /// Human-readable titles for fractional `moduleId` values (dev UI + `TimerSessionConfig.title`).
    static let moduleDisplayTitles: [String: String] = [
        "NF_FRAC": "Nostril Focus",
        "IM_FRAC": "I AM Mantra",
        "BS_FRAC": "Body Scan",
        "BS_FRAC_UP": "Body Scan Up",
        "BS_FRAC_DOWN": "Body Scan Down",
        "PB_FRAC": "Perfect Breath",
        "INT_FRAC": "Intro",
        "VC": "Vision Clarity",
        "RT": "Retrospection",
        "GB": "Gentle Bell",
        "OH": "Open Heart",
    ]

    static func displayTitle(forModuleId id: String) -> String {
        moduleDisplayTitles[id] ?? id
    }
}

// MARK: - Server Response Models

extension FractionalModules {

    struct Plan: Codable {
        let planId: String
        let moduleId: String
        let durationSec: Int
        let voiceId: String
        let items: [PlanItem]
    }

    struct PlanParallel: Codable {
        let clipId: String
        let url: String
        let text: String?
    }

    struct PlanItem: Codable {
        let atSec: Int
        let clipId: String
        let role: String
        let text: String
        let url: String
        let parallel: PlanParallel?

        init(
            atSec: Int,
            clipId: String,
            role: String,
            text: String,
            url: String,
            parallel: PlanParallel? = nil
        ) {
            self.atSec = atSec
            self.clipId = clipId
            self.role = role
            self.text = text
            self.url = url
            self.parallel = parallel
        }
    }
}
