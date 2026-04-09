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

    var isFractional: Bool {
        if cue.id == "PB_FRAC" { return true }
        if cue.id.hasSuffix("_FRAC") { return true }
        return cue.id.hasPrefix("BS_FRAC_")
    }

    /// Dev: `INT_FRAC` length is derived from total session duration on the server — no manual duration in create UI.
    var allowsManualFractionalDuration: Bool {
        isFractional && cue.id != "INT_FRAC"
    }

    static func == (lhs: CueSetting, rhs: CueSetting) -> Bool {
        lhs.id == rhs.id &&
        lhs.triggerType == rhs.triggerType &&
        lhs.minute == rhs.minute &&
        lhs.cue.id == rhs.cue.id &&
        lhs.fractionalDuration == rhs.fractionalDuration
    }
}

// MARK: - Fractional Cue Collapsing

extension Array where Element == CueSetting {

    /// Collapses expanded fractional clips (e.g. NF_C001, NF_C002 …) back into
    /// a single FRAC entry (NF_FRAC) suitable for the Timer editor.
    func collapsedFractionalCues(meditationMinutes: Int) -> [CueSetting] {
        var result: [CueSetting] = []
        var i = 0
        let totalSeconds = meditationMinutes * 60

        while i < count {
            let setting = self[i]

            guard let prefix = Self.fractionalClipPrefix(of: setting.cue.id) else {
                result.append(setting)
                i += 1
                continue
            }

            let startSec = Self.triggerSeconds(of: setting)
            var j = i + 1
            while j < count, Self.fractionalClipPrefix(of: self[j].cue.id) == prefix {
                j += 1
            }

            let endSec: Int
            if j < count {
                endSec = Self.triggerSeconds(of: self[j])
            } else {
                endSec = totalSeconds
            }

            let durationMinutes = Swift.max(1, Int(ceil(Double(endSec - startSec) / 60.0)))
            let fracId = "\(prefix)_FRAC"

            let fracCue: Cue
            if let catalogEntry = CatalogsManager.shared.cues.first(where: { $0.id == fracId }) {
                fracCue = catalogEntry
            } else {
                fracCue = Cue(id: fracId, name: setting.cue.name, url: setting.cue.url)
            }

            if startSec == 0 {
                result.append(CueSetting(triggerType: .start, minute: nil, cue: fracCue, fractionalDuration: durationMinutes))
            } else {
                result.append(CueSetting(triggerType: .minute, minute: startSec / 60, cue: fracCue, fractionalDuration: durationMinutes))
            }

            i = j
        }

        return result
    }

    /// Extracts the module prefix from a fractional clip ID (e.g. "NF" from "NF_C001", "PB" from "PBV_…").
    private static func fractionalClipPrefix(of cueId: String) -> String? {
        if cueId.hasPrefix("PBV_") || cueId.hasPrefix("PBS_") { return "PB" }
        guard let range = cueId.range(of: #"_C\d+$"#, options: .regularExpression) else { return nil }
        let prefix = String(cueId[cueId.startIndex..<range.lowerBound])
        return prefix.isEmpty ? nil : prefix
    }

    private static func triggerSeconds(of setting: CueSetting) -> Int {
        switch setting.triggerType {
        case .start: return 0
        case .minute: return (setting.minute ?? 0) * 60
        case .second: return setting.minute ?? 0
        case .end: return 0
        }
    }
}
