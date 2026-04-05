//
//  CueSetting.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-24
//

import Foundation

enum CueTriggerType: String, Codable, CaseIterable {
    case start
    case minute
    case end
    case second
}

/// Represents a cue (sound) paired with when it should play.
/// If triggerType is `.minute`, then `minute` holds the value.
struct CueSetting: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var triggerType: CueTriggerType = .minute
    var minute: Int? = 1
    var cue: Cue
    /// Explicit duration in minutes for fractional modules (nil = auto-fill gap).
    var fractionalDuration: Int?

    var isFractional: Bool { cue.id.hasSuffix("_FRAC") }

    static func == (lhs: CueSetting, rhs: CueSetting) -> Bool {
        lhs.id == rhs.id &&
        lhs.triggerType == rhs.triggerType &&
        lhs.minute == rhs.minute &&
        lhs.cue.id == rhs.cue.id &&
        lhs.fractionalDuration == rhs.fractionalDuration
    }
}
