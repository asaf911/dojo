//
//  FractionalModules+Models.swift
//  Dojo
//

import Foundation

enum FractionalModules {}

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
