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

    struct PlanItem: Codable {
        let atSec: Int
        let clipId: String
        let role: String
        let text: String
        let url: String
    }
}
