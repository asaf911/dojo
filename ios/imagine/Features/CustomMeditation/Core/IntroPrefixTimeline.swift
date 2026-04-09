//
//  IntroPrefixTimeline.swift
//  imagine
//
//  Matches `introWindowSecFromSessionDurationSec` in functions/src/introFractionalPlan.ts:
//  intro is a **prefix** before practice; practice duration drives the curve (1m → ~18s … 10m+ → 90s).
//

import Foundation

enum IntroPrefixTimeline {
    private static let minSec = 17
    private static let maxSec = 90
    private static let minTargetAtOneMinute = 18

    /// Intro block length in seconds for a given **practice** length (not including intro).
    static func introPrefixSeconds(practiceDurationSec: Int) -> Int {
        let sessionMin = max(Double(practiceDurationSec) / 60.0, 1.0)
        let cappedMin = min(sessionMin, 10.0)
        let t = (cappedMin - 1.0) / 9.0
        let raw = Double(minTargetAtOneMinute) + t * Double(maxSec - minTargetAtOneMinute)
        let rounded = Int(raw.rounded())
        return Swift.max(minSec, Swift.min(maxSec, rounded))
    }

    /// Total playback seconds = practice + intro prefix when `INT_FRAC` is present.
    static func playbackSeconds(practiceMinutes: Int, hasIntroFrac: Bool) -> Int {
        let practiceSec = practiceMinutes * 60
        let intro = hasIntroFrac ? introPrefixSeconds(practiceDurationSec: practiceSec) : 0
        return practiceSec + intro
    }
}

extension Array where Element == CueSetting {

    /// Maps practice-relative minute triggers to absolute session seconds after the intro prefix. Idempotent if cues already use `.second` for all non-start rows (e.g. server-expanded).
    func applyingIntroPrefixIfNeeded(practiceMinutes: Int) -> [CueSetting] {
        let hasIntroFrac = contains { $0.cue.id == "INT_FRAC" && $0.triggerType == .start }
        guard hasIntroFrac else { return self }

        let introSec = IntroPrefixTimeline.introPrefixSeconds(practiceDurationSec: practiceMinutes * 60)

        return map { setting in
            if setting.cue.id == "INT_FRAC" {
                return CueSetting(
                    id: setting.id,
                    triggerType: .start,
                    minute: nil,
                    cue: setting.cue,
                    fractionalDuration: setting.fractionalDuration
                )
            }
            switch setting.triggerType {
            case .minute:
                let m = setting.minute ?? 0
                let absoluteSec = introSec + m * 60
                return CueSetting(
                    id: setting.id,
                    triggerType: .second,
                    minute: absoluteSec,
                    cue: setting.cue,
                    fractionalDuration: setting.fractionalDuration
                )
            case .start:
                // Non-intro "Start" means practice begins (00:00) — same session time as intro end.
                return CueSetting(
                    id: setting.id,
                    triggerType: .second,
                    minute: introSec,
                    cue: setting.cue,
                    fractionalDuration: setting.fractionalDuration
                )
            case .second:
                // Practice-relative seconds (0 = meditation 00:00, 60 = +1 min, …) must be shifted by the
                // intro prefix. Already-absolute triggers from the server are >= introSec and pass through.
                let sec = setting.minute ?? 0
                let absoluteSec = sec < introSec ? introSec + sec : sec
                return CueSetting(
                    id: setting.id,
                    triggerType: .second,
                    minute: absoluteSec,
                    cue: setting.cue,
                    fractionalDuration: setting.fractionalDuration
                )
            case .end:
                return setting
            }
        }
    }
}
