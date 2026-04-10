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
    /// Also merges server-expanded rows: `INT_GRT_*` / `INT_ARR_*` → `INT_FRAC`, `BS_SYS_*` / `BS_MAC_*` → `BS_FRAC_*`, `PBV_*` → `PB_FRAC`.
    func collapsedFractionalCues(meditationMinutes: Int) -> [CueSetting] {
        var result: [CueSetting] = []
        var i = 0
        let totalSeconds = meditationMinutes * 60

        while i < count {
            let setting = self[i]

            guard let groupKey = FractionalCueID.editorCollapseGroupKey(of: setting.cue.id) else {
                result.append(setting)
                i += 1
                continue
            }

            let startSec = Self.triggerSeconds(of: setting)
            var j = i + 1
            while j < count,
                  FractionalCueID.editorCollapseGroupKey(of: self[j].cue.id) == groupKey {
                j += 1
            }

            let clipIds = self[i..<j].map { $0.cue.id }
            let moduleId = FractionalCueID.editorCollapsedModuleId(groupKey: groupKey, clipIds: clipIds)

            let endSec: Int
            if j < count {
                endSec = Self.triggerSeconds(of: self[j])
            } else {
                endSec = totalSeconds
            }

            let durationMinutes = Swift.max(1, Int(ceil(Double(endSec - startSec) / 60.0)))
            let fracCue = Self.editorModuleCue(moduleId: moduleId, fallbackURL: setting.cue.url)

            if moduleId == "INT_FRAC" {
                result.append(CueSetting(triggerType: .start, minute: nil, cue: fracCue, fractionalDuration: nil))
            } else if startSec == 0 {
                result.append(CueSetting(triggerType: .start, minute: nil, cue: fracCue, fractionalDuration: durationMinutes))
            } else {
                result.append(CueSetting(triggerType: .minute, minute: startSec / 60, cue: fracCue, fractionalDuration: durationMinutes))
            }

            i = j
        }

        return result
    }

    /// Catalog cue when available; otherwise stable parent title (not atomic clip text).
    private static func editorModuleCue(moduleId: String, fallbackURL: String) -> Cue {
        if let catalogEntry = CatalogsManager.shared.cues.first(where: { $0.id == moduleId }) {
            return catalogEntry
        }
        let title = FractionalModules.displayTitle(forModuleId: moduleId)
        return Cue(id: moduleId, name: title, url: fallbackURL)
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

// MARK: - Playback → Timer editor (module / minute level)

extension Array where Element == CueSetting {

    /// Strips expanded intro atomics, subtracts intro prelude from wall-clock `.second` triggers, sorts for `collapsedFractionalCues`.
    func normalizedPlaybackCuesForTimerEditor(introPrefixSeconds intro: Int, practiceMinutes: Int) -> [CueSetting] {
        var out: [CueSetting] = []
        out.reserveCapacity(count)

        for setting in self {
            if shouldDropExpandedIntroAtomic(setting, introPrefixSeconds: intro) {
                continue
            }
            if setting.cue.id == "INT_FRAC", setting.triggerType == .start {
                out.append(setting)
                continue
            }

            switch setting.triggerType {
            case .start, .end:
                out.append(setting)
            case .minute:
                out.append(setting)
            case .second:
                let absSec = setting.minute ?? 0
                let practiceSec = Swift.max(0, absSec - intro)
                out.append(
                    CueSetting(
                        id: setting.id,
                        triggerType: .second,
                        minute: practiceSec,
                        cue: setting.cue,
                        fractionalDuration: setting.fractionalDuration
                    )
                )
            }
        }

        if intro > 0 {
            let hasIntFracRow = out.contains { $0.cue.id == "INT_FRAC" && $0.triggerType == .start }
            if !hasIntFracRow, let introCue = CatalogsManager.shared.cues.first(where: { $0.id == "INT_FRAC" }) {
                out.insert(
                    CueSetting(triggerType: .start, minute: nil, cue: introCue, fractionalDuration: nil),
                    at: 0
                )
            }
        }

        return out.sorted { editorCollapseOrdering($0, $1, practiceMinutes: practiceMinutes) }
    }

    /// After fractional collapse, map remaining `.second` triggers on **non-fractional** cues to Start / minute (Create UI has no second picker).
    func convertingNonFractionalSecondTriggersForTimerEditor(practiceMinutes: Int) -> [CueSetting] {
        let capMinute = Swift.max(1, practiceMinutes - 1)
        return map { setting in
            guard setting.triggerType == .second, !setting.isFractional else { return setting }
            let pr = setting.minute ?? 0
            if pr <= 0 {
                return CueSetting(
                    id: setting.id,
                    triggerType: .start,
                    minute: nil,
                    cue: setting.cue,
                    fractionalDuration: setting.fractionalDuration
                )
            }
            let minuteSlot = Swift.min(capMinute, Swift.max(1, Int(ceil(Double(pr) / 60.0))))
            return CueSetting(
                id: setting.id,
                triggerType: .minute,
                minute: minuteSlot,
                cue: setting.cue,
                fractionalDuration: setting.fractionalDuration
            )
        }
    }

    private func shouldDropExpandedIntroAtomic(_ setting: CueSetting, introPrefixSeconds intro: Int) -> Bool {
        guard intro > 0, setting.triggerType == .second, let abs = setting.minute, abs < intro else { return false }
        let id = setting.cue.id
        if id == "INT_FRAC" { return false }
        return id.hasPrefix("INT_")
    }

    private func editorCollapseOrdering(_ a: CueSetting, _ b: CueSetting, practiceMinutes: Int) -> Bool {
        func key(_ s: CueSetting) -> Int {
            switch s.triggerType {
            case .start:
                return s.cue.id == "INT_FRAC" ? -2 : -1
            case .minute:
                return (s.minute ?? 0) * 60
            case .second:
                return s.minute ?? 0
            case .end:
                return practiceMinutes * 60 + 9_999_999
            }
        }
        return key(a) < key(b)
    }
}
