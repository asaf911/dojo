//
//  CueSetting+CreateSessionDuration.swift
//  imagine
//
//  Create screen: practice length is derived from fractional module durations (not user-picked).
//

import Foundation

extension Array where Element == CueSetting {

    /// Hard cap for a single create-session practice (matches legacy wheel max).
    static var createFlowMaxPracticeMinutes: Int { 60 }

    /// Sum of sequential step lengths (minutes): fractional modules + monolithic body scans (`BS1`…). Intro excluded.
    func sumFractionalPracticeMinutes(excludingIndex excluded: Int? = nil) -> Int {
        enumerated().reduce(0) { acc, pair in
            if let ex = excluded, pair.offset == ex { return acc }
            let cs = pair.element
            guard cs.isCreateSequentialModule else { return acc }
            let chunk = Swift.max(1, Swift.min(Self.createFlowMaxPracticeMinutes, Self.createSequentialModuleDurationMinutes(cs)))
            return acc + chunk
        }
    }

    /// Practice minutes sent to `/meditations` and the player (intro prefix is added separately when `INT_FRAC` is present).
    func computedPracticeMinutesForCreateScreen() -> Int {
        let sum = sumFractionalPracticeMinutes()
        return Swift.min(Self.createFlowMaxPracticeMinutes, Swift.max(1, sum))
    }

    /// Keeps total fractional time within the cap, assigns timed fractional modules to a **sequential** practice timeline,
    /// then clamps **non-fractional** minute triggers to valid slots.
    mutating func reconcileCreateScreenAutoSession() {
        shrinkFractionalSumIfOverCap()

        let practice = computedPracticeMinutesForCreateScreen()
        applySequentialTimedFractionalTriggers()
        clampAndDedupeNonFractionalMinuteTriggers(practiceMinutes: practice)
    }

    // MARK: - Private

    /// Minutes one sequential create step occupies (fractional `fractionalDuration`, or catalog / id for `BS*` monoliths).
    /// Shared with `CueConfigurationView` for stepper caps and monolithic labels.
    static func createSequentialModuleDurationMinutes(_ cs: CueSetting) -> Int {
        guard cs.isCreateSequentialModule else { return 0 }
        if cs.isFractional {
            return Swift.max(1, cs.fractionalDuration ?? 1)
        }
        if let fd = cs.fractionalDuration {
            return Swift.max(1, fd)
        }
        if let d = CatalogsManager.shared.bodyScanDurations[cs.cue.id] {
            return Swift.max(1, d)
        }
        if cs.cue.isMonolithicBodyScanCatalogCue, let n = Int(cs.cue.id.dropFirst(2)), n > 0 {
            return Swift.min(createFlowMaxPracticeMinutes, n)
        }
        return 1
    }

    /// Places each sequential create step immediately after the previous one on the practice timeline (order = list order).
    private mutating func applySequentialTimedFractionalTriggers() {
        var cumulativePracticeMinutes = 0

        for i in indices {
            guard self[i].isCreateSequentialModule else { continue }

            let durationMin = Swift.max(1, Self.createSequentialModuleDurationMinutes(self[i]))

            if cumulativePracticeMinutes == 0 {
                let startTakenElsewhere = containsStartTrigger(excludingIndex: i)
                if !startTakenElsewhere {
                    self[i].triggerType = .start
                    self[i].minute = nil
                } else {
                    self[i].triggerType = .minute
                    self[i].minute = 0
                }
            } else {
                self[i].triggerType = .minute
                self[i].minute = cumulativePracticeMinutes
            }

            cumulativePracticeMinutes += durationMin
        }
    }

    private mutating func shrinkFractionalSumIfOverCap() {
        var safety = 0
        while sumFractionalPracticeMinutes() > Self.createFlowMaxPracticeMinutes && safety < 500 {
            safety += 1
            guard let idx = indexOfLargestSplittableFractionalDuration() else { break }
            if let fd = self[idx].fractionalDuration, fd > 1 {
                self[idx].fractionalDuration = fd - 1
            } else {
                break
            }
        }
    }

    private func indexOfLargestSplittableFractionalDuration() -> Int? {
        var bestIdx: Int?
        var bestVal = 0
        for (i, cs) in enumerated() where cs.isFractional && cs.cue.id != "INT_FRAC" && !cs.cue.isMonolithicBodyScanCatalogCue {
            let v = cs.fractionalDuration ?? 1
            if v > bestVal {
                bestVal = v
                bestIdx = i
            }
        }
        return bestIdx
    }

    private mutating func clampAndDedupeNonFractionalMinuteTriggers(practiceMinutes: Int) {
        let p = Swift.max(1, practiceMinutes)
        let maxMinuteSlot = p - 1

        if maxMinuteSlot < 1 {
            for i in indices where self[i].triggerType == .minute && !self[i].isCreateSequentialModule {
                coerceAwayFromMinuteTrigger(at: i)
            }
            return
        }

        for i in indices where self[i].triggerType == .minute && !self[i].isCreateSequentialModule {
            if self[i].minute == nil {
                self[i].minute = 1
            } else if let m = self[i].minute {
                self[i].minute = Swift.min(Swift.max(1, m), maxMinuteSlot)
            }
        }

        resolveDuplicateNonFractionalMinuteTriggers(maxMinuteSlot: maxMinuteSlot)
    }

    private mutating func coerceAwayFromMinuteTrigger(at index: Int) {
        let startTakenElsewhere = containsStartTrigger(excludingIndex: index)
        let endTakenElsewhere = containsEndTrigger(excludingIndex: index)

        if !startTakenElsewhere {
            self[index].triggerType = .start
            self[index].minute = nil
        } else if !endTakenElsewhere {
            self[index].triggerType = .end
            self[index].minute = nil
        } else {
            self[index].minute = 1
            self[index].triggerType = .minute
        }
    }

    private func containsStartTrigger(excludingIndex: Int?) -> Bool {
        enumerated().contains { pair in
            if let ex = excludingIndex, pair.offset == ex { return false }
            return pair.element.triggerType == .start
        }
    }

    private func containsEndTrigger(excludingIndex: Int?) -> Bool {
        enumerated().contains { pair in
            if let ex = excludingIndex, pair.offset == ex { return false }
            return pair.element.triggerType == .end
        }
    }

    private mutating func resolveDuplicateNonFractionalMinuteTriggers(maxMinuteSlot: Int) {
        var used = Set<Int>()
        for i in 0..<self.count {
            guard self[i].isCreateSequentialModule else { continue }
            switch self[i].triggerType {
            case .minute:
                if let m = self[i].minute {
                    used.insert(Swift.min(Swift.max(0, m), maxMinuteSlot))
                }
            case .start:
                used.insert(0)
            default:
                break
            }
        }

        for i in 0..<self.count {
            guard self[i].triggerType == .minute, !self[i].isCreateSequentialModule else { continue }
            var m = self[i].minute ?? 1
            m = Swift.min(Swift.max(1, m), maxMinuteSlot)
            while used.contains(m) && m > 1 {
                m -= 1
            }
            if used.contains(m) {
                coerceAwayFromMinuteTrigger(at: i)
            } else {
                used.insert(m)
                self[i].minute = m
            }
        }
    }
}
