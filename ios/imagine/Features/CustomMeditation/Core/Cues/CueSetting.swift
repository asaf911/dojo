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
}

/// Represents a cue (sound) paired with when it should play.
/// If triggerType is `.minute`, then `minute` holds the value.
struct CueSetting: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var triggerType: CueTriggerType = .minute
    var minute: Int? = 1  // Used only if triggerType == .minute
    var cue: Cue
    
    static func == (lhs: CueSetting, rhs: CueSetting) -> Bool {
        lhs.id == rhs.id &&
        lhs.triggerType == rhs.triggerType &&
        lhs.minute == rhs.minute &&
        lhs.cue.id == rhs.cue.id
    }
}
