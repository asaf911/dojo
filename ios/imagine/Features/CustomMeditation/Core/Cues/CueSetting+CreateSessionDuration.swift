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

    /// Sum of explicit fractional module lengths (minutes). `INT_FRAC` is excluded — its length comes from the session on the server.
    func sumFractionalPracticeMinutes(excludingIndex excluded: Int? = nil) -> Int {
        enumerated().reduce(0) { acc, pair in
            if let ex = excluded, pair.offset == ex { return acc }
            let cs = pair.element
            guard cs.isFractional, cs.cue.id != "INT_FRAC" else { return acc }
            let chunk = Swift.max(1, Swift.min(Self.createFlowMaxPracticeMinutes, cs.fractionalDuration ?? 1))
            return acc + chunk
        }
    }

    /// Practice minutes sent to `/meditations` and the player (intro prefix is added separately when `INT_FRAC` is present).
    func computedPracticeMinutesForCreateScreen() -> Int {
        let sum = sumFractionalPracticeMinutes()
        return Swift.min(Self.createFlowMaxPracticeMinutes, Swift.max(1, sum))
    }

    /// Keeps total fractional time within the cap, clamps minute triggers to valid slots, and coerces invalid rows when practice is very short.
    mutating func reconcileCreateScreenAutoSession() {
        shrinkFractionalSumIfOverCap()

        let practice = computedPracticeMinutesForCreateScreen()
        clampAndDedupeMinuteTriggers(practiceMinutes: practice)
    }

    // MARK: - Private

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
        for (i, cs) in enumerated() where cs.isFractional && cs.cue.id != "INT_FRAC" {
            let v = cs.fractionalDuration ?? 1
            if v > bestVal {
                bestVal = v
                bestIdx = i
            }
        }
        return bestIdx
    }

    private mutating func clampAndDedupeMinuteTriggers(practiceMinutes: Int) {
        let p = Swift.max(1, practiceMinutes)
        let maxMinuteSlot = p - 1

        if maxMinuteSlot < 1 {
            for i in indices where self[i].triggerType == .minute {
                coerceAwayFromMinuteTrigger(at: i)
            }
            return
        }

        for i in indices where self[i].triggerType == .minute {
            if self[i].minute == nil {
                self[i].minute = 1
            } else if let m = self[i].minute {
                self[i].minute = Swift.min(Swift.max(1, m), maxMinuteSlot)
            }
        }

        resolveDuplicateMinuteTriggers(maxMinuteSlot: maxMinuteSlot)
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

    private mutating func resolveDuplicateMinuteTriggers(maxMinuteSlot: Int) {
        var used = Set<Int>()
        for i in 0..<self.count {
            guard self[i].triggerType == .minute else { continue }
            var m = self[i].minute ?? 1
            m = Swift.min(Swift.max(1, m), maxMinuteSlot)
            while used.contains(m), m > 1 {
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
