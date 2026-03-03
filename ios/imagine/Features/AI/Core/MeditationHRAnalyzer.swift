import Foundation
import HealthKit

/// Computes meditation HR effectiveness metrics from a sequence of HRSample values.
final class MeditationHRAnalyzer {
    static func analyze(sessionId: String, samples: [HRSample], postSessionEnd: Date, healthStore: HKHealthStore? = nil, completion: @escaping (MeditationHRResult) -> Void) {
        guard !samples.isEmpty else {
            completion(MeditationHRResult(sessionId: sessionId, baselineBPM: 0, minBPM: 0, deltaFromBaseline: 0, relaxationScore: 0, stabilityScore: 0, recoveryIndex: 0, hrvSDNNms: nil))
            return
        }

        // Baseline: first 30 seconds
        let startTs = samples.first!.timestamp
        let baselineWindowEnd = startTs + 30
        let baseline = samples.filter { $0.timestamp <= baselineWindowEnd }.map { $0.bpm }.average()

        let minBPM = samples.map { $0.bpm }.min() ?? baseline
        let delta = baseline - minBPM

        // Simple relaxation score: normalized drop vs baseline
        let relaxationScore = max(0, min(1, delta / max(5, baseline * 0.1)))

        // Stability: inverse of variance normalized
        let variance = samples.map { pow($0.bpm - samples.map { $0.bpm }.average(), 2.0) }.average()
        let stabilityScore = 1.0 / (1.0 + variance / 25.0)

        // Recovery: slope over last 60s (approx - lower slope is calmer)
        let lastWindowStart = (samples.last!.timestamp - 60)
        let tail = samples.filter { $0.timestamp >= lastWindowStart }
        let recoveryIndex = slope(tail)

        // Optionally fetch post-session HRV SDNN if available (non-blocking - compute quickly if no store)
        if let store = healthStore,
           let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let predicate = HKQuery.predicateForSamples(withStart: Date(timeIntervalSince1970: samples.first!.timestamp), end: postSessionEnd, options: .strictEndDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, results, _ in
                let sdnn = (results?.first as? HKQuantitySample)?.quantity.doubleValue(for: .secondUnit(with: .milli))
                let result = MeditationHRResult(sessionId: sessionId, baselineBPM: baseline, minBPM: minBPM, deltaFromBaseline: delta, relaxationScore: relaxationScore, stabilityScore: stabilityScore, recoveryIndex: recoveryIndex, hrvSDNNms: sdnn)
                completion(result)
            }
            store.execute(query)
        } else {
            let result = MeditationHRResult(sessionId: sessionId, baselineBPM: baseline, minBPM: minBPM, deltaFromBaseline: delta, relaxationScore: relaxationScore, stabilityScore: stabilityScore, recoveryIndex: recoveryIndex, hrvSDNNms: nil)
            completion(result)
        }
    }

    private static func slope(_ samples: [HRSample]) -> Double {
        guard samples.count >= 2 else { return 0 }
        // Simple linear regression slope (bpm per second)
        let xs = samples.map { $0.timestamp - samples.first!.timestamp }
        let ys = samples.map { $0.bpm }
        let xMean = xs.average()
        let yMean = ys.average()
        var num: Double = 0
        var den: Double = 0
        for i in 0..<samples.count {
            let dx = xs[i] - xMean
            num += dx * (ys[i] - yMean)
            den += dx * dx
        }
        return den == 0 ? 0 : num / den
    }
}

private extension Array where Element == Double {
    func average() -> Double {
        guard !isEmpty else { return 0 }
        let total = reduce(0, +)
        return total / Double(count)
    }
}



