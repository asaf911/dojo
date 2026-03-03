//
//  HeartRateResults.swift
//  Dojo
//
//  Heart rate data structure for capturing session results.
//

import Foundation

// MARK: - Heart Rate Results Data Structure

struct HeartRateResults {
    let hasValidData: Bool      // 2+ samples - can show graph
    let hasMinimalData: Bool    // exactly 1 sample - can show average only
    let hasAnyData: Bool
    let firstThreeAverage: Double
    let lastThreeAverage: Double
    let heartRateChange: Double
    let sampleCount: Int
    let samples: [HeartRateSamplePoint]  // Raw samples for graphing
    
    static let empty = HeartRateResults(
        hasValidData: false,
        hasMinimalData: false,
        hasAnyData: false,
        firstThreeAverage: 0,
        lastThreeAverage: 0,
        heartRateChange: 0,
        sampleCount: 0,
        samples: []
    )
    
    // Create from BPM tracker (captures current state)
    static func from(_ tracker: PracticeBPMTracker) -> HeartRateResults {
        return HeartRateResults(
            hasValidData: tracker.hasValidData,
            hasMinimalData: tracker.hasMinimalData,
            hasAnyData: tracker.hasAnyData,
            firstThreeAverage: tracker.bestFirstThreeAverage,
            lastThreeAverage: tracker.bestLastThreeAverage,
            heartRateChange: tracker.bestHeartRateChange,
            sampleCount: tracker.hasLockedResults ? tracker.finalSampleCount : tracker.sampleCount,
            samples: tracker.graphSamples
        )
    }
}
