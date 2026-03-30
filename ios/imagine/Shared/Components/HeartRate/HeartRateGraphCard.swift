//
//  HeartRateGraphCard.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-17
//

import SwiftUI

/// Standalone card displaying heart rate graph with BPM summary.
/// Used in both regular meditation post-practice and AI meditation chat.
struct HeartRateGraphCard: View {
    let samples: [HeartRateSamplePoint]
    let startBPM: Double
    /// Still stored and used for legacy UI when `minBPM` is nil or invalid.
    let endBPM: Double
    /// When non-nil and > 0, header and badge use session minimum vs start (BPM delta); graph axis shows MIN.
    let minBPM: Double?

    init(samples: [HeartRateSamplePoint], startBPM: Double, endBPM: Double, minBPM: Double? = nil) {
        self.samples = samples
        self.startBPM = startBPM
        self.endBPM = endBPM
        self.minBPM = minBPM
    }

    /// Mirrors legacy percent threshold (~3%): treat BPM change smaller than this as steady.
    private let steadyBPMThreshold: Double = 3

    private var usesMinPresentation: Bool {
        guard let m = minBPM, m > 0 else { return false }
        return true
    }

    private var percentChange: Double {
        guard startBPM > 0 else { return 0 }
        return ((endBPM - startBPM) / startBPM) * 100
    }

    private var legacyIsDecrease: Bool {
        endBPM < startBPM
    }

    private var bpmDeltaStartToMin: Double {
        guard let m = minBPM else { return 0 }
        return startBPM - m
    }

    private var minPathIsSteady: Bool {
        abs(bpmDeltaStartToMin) < steadyBPMThreshold
    }

    private var minPathIsDecrease: Bool {
        !minPathIsSteady && (minBPM ?? 0) < startBPM
    }

    private var minPathIsIncrease: Bool {
        !minPathIsSteady && (minBPM ?? 0) > startBPM
    }

    private var showChangeBadge: Bool {
        guard startBPM > 0 else { return false }
        if usesMinPresentation {
            return (minBPM ?? 0) > 0
        }
        return endBPM > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: START + END, or START + MIN + END when min is measured
            headerRow

            // Graph
            if samples.count >= 2 {
                HeartRateGraphView(
                    samples: samples,
                    startBPM: startBPM,
                    endBPM: endBPM,
                    showMinimumMarker: usesMinPresentation
                )
            } else {
                // Fallback for insufficient data
                Text("Not enough data points to display graph")
                    .font(Font.custom("Nunito", size: 14).weight(.medium))
                    .foregroundColor(.foregroundLightGray)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            }

            // Bottom: Change badge
            if showChangeBadge {
                changeBadge
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.00),
                    Gradient.Stop(color: Color(red: 0.08, green: 0.08, blue: 0.14), location: 1.00),
                ],
                startPoint: UnitPoint(x: 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 1)
            )
        )
        .cornerRadius(16)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Image("heartIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundColor(.white)

            Text("HEART RATE")
                .font(Font.custom("Nunito", size: 14).weight(.semibold))
                .foregroundColor(.foregroundLightGray)
                .padding(.leading, 6)

            Spacer(minLength: 4)

            Text(headerBpmSummaryString)
                .font(Font.custom("Nunito", size: 10))
                .foregroundColor(.foregroundLightGray)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
    }

    /// e.g. `START 77 · MIN 59 · END 64 bpm` or `START 77 · END 64 bpm` (single `bpm` for the row).
    private var headerBpmSummaryString: String {
        let s = Int(round(startBPM))
        let e = Int(round(endBPM))
        if usesMinPresentation, let m = minBPM, m > 0 {
            let mi = Int(round(m))
            return "START \(s) · MIN \(mi) · END \(e) bpm"
        }
        return "START \(s) · END \(e) bpm"
    }

    // MARK: - Change Badge

    @ViewBuilder
    private var changeBadge: some View {
        if usesMinPresentation {
            minPresentationBadge
        } else {
            legacyPercentBadge
        }
    }

    @ViewBuilder
    private var minPresentationBadge: some View {
        let absBPM = abs(bpmDeltaStartToMin)
        let changeText: String = {
            if minPathIsSteady { return "No change in HR" }
            if minPathIsDecrease { return "below where you started" }
            if minPathIsIncrease { return "up from your start" }
            return "No change in HR"
        }()

        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.planTop)
                    .frame(width: 24, height: 24)

                if minPathIsDecrease {
                    Image("hrDown")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(Color.dojoTurquoise)
                        .frame(width: 8.28, height: 8.28)
                } else if minPathIsIncrease {
                    Image("hrUp")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(Color.hrHigh)
                        .frame(width: 8.28, height: 8.28)
                } else {
                    Rectangle()
                        .fill(Color.selectedLightPurple)
                        .frame(width: 8, height: 2)
                }
            }

            HStack(spacing: 4) {
                let changeColor: Color = minPathIsDecrease ? .dojoTurquoise : (minPathIsIncrease ? .hrHigh : .selectedLightPurple)
                Text(minPathIsSteady ? "0 BPM" : "\(String(format: "%.0f", absBPM)) BPM")
                    .font(Font.custom("Nunito", size: 16).weight(.semibold))
                    .foregroundColor(changeColor)

                Text(changeText)
                    .font(Font.custom("Nunito", size: 12).weight(.medium))
                    .foregroundColor(changeColor)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var legacyPercentBadge: some View {
        let absPercent = abs(percentChange)
        let changeText = legacyIsDecrease ? "HR Decrease" : (percentChange > 0 ? "HR Increase" : "HR Steady")

        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.planTop)
                    .frame(width: 24, height: 24)

                if legacyIsDecrease {
                    Image("hrDown")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(Color.dojoTurquoise)
                        .frame(width: 8.28, height: 8.28)
                } else if percentChange > 0 {
                    Image("hrUp")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(Color.hrHigh)
                        .frame(width: 8.28, height: 8.28)
                } else {
                    Rectangle()
                        .fill(Color.selectedLightPurple)
                        .frame(width: 8, height: 2)
                }
            }

            HStack(spacing: 4) {
                let changeColor: Color = legacyIsDecrease ? .dojoTurquoise : (percentChange > 0 ? .hrHigh : .selectedLightPurple)

                Text("\(String(format: "%.0f", absPercent))%")
                    .font(Font.custom("Nunito", size: 16).weight(.semibold))
                    .foregroundColor(changeColor)

                Text(changeText)
                    .font(Font.custom("Nunito", size: 12).weight(.medium))
                    .foregroundColor(changeColor)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Previews

private enum HeartRateGraphCardPreviewSamples {
    static let relax: [HeartRateSamplePoint] = [
        HeartRateSamplePoint(minuteOffset: 0, bpm: 88),
        HeartRateSamplePoint(minuteOffset: 1, bpm: 85),
        HeartRateSamplePoint(minuteOffset: 2, bpm: 82),
        HeartRateSamplePoint(minuteOffset: 3, bpm: 78),
        HeartRateSamplePoint(minuteOffset: 4, bpm: 75),
        HeartRateSamplePoint(minuteOffset: 5, bpm: 73),
        HeartRateSamplePoint(minuteOffset: 6, bpm: 70),
        HeartRateSamplePoint(minuteOffset: 7, bpm: 68),
        HeartRateSamplePoint(minuteOffset: 8, bpm: 71)
    ]

    static let steady: [HeartRateSamplePoint] = [
        HeartRateSamplePoint(minuteOffset: 0, bpm: 72),
        HeartRateSamplePoint(minuteOffset: 1, bpm: 73),
        HeartRateSamplePoint(minuteOffset: 2, bpm: 72),
        HeartRateSamplePoint(minuteOffset: 3, bpm: 71),
        HeartRateSamplePoint(minuteOffset: 4, bpm: 72),
        HeartRateSamplePoint(minuteOffset: 5, bpm: 73)
    ]

    /// Session minimum slightly below start (< 3 BPM delta) — MIN-path steady badge.
    static let minPathSteady: [HeartRateSamplePoint] = [
        HeartRateSamplePoint(minuteOffset: 0, bpm: 72),
        HeartRateSamplePoint(minuteOffset: 1, bpm: 71),
        HeartRateSamplePoint(minuteOffset: 2, bpm: 72),
        HeartRateSamplePoint(minuteOffset: 3, bpm: 71),
        HeartRateSamplePoint(minuteOffset: 4, bpm: 72),
        HeartRateSamplePoint(minuteOffset: 5, bpm: 72)
    ]

    /// All readings at/above 72 so session min > passed start — MIN-path increase badge.
    static let minPathIncrease: [HeartRateSamplePoint] = [
        HeartRateSamplePoint(minuteOffset: 0, bpm: 72),
        HeartRateSamplePoint(minuteOffset: 1, bpm: 74),
        HeartRateSamplePoint(minuteOffset: 2, bpm: 75),
        HeartRateSamplePoint(minuteOffset: 3, bpm: 76),
        HeartRateSamplePoint(minuteOffset: 4, bpm: 77),
        HeartRateSamplePoint(minuteOffset: 5, bpm: 78)
    ]
}

private let heartRateGraphCardPreviewBackground = Color(red: 0.08, green: 0.08, blue: 0.12)

#Preview("MIN path — decrease") {
    HeartRateGraphCard(
        samples: HeartRateGraphCardPreviewSamples.relax,
        startBPM: 88,
        endBPM: 71,
        minBPM: 68
    )
    .padding(16)
    .frame(width: 390)
    .background(heartRateGraphCardPreviewBackground)
}

#Preview("MIN path — steady") {
    HeartRateGraphCard(
        samples: HeartRateGraphCardPreviewSamples.minPathSteady,
        startBPM: 72,
        endBPM: 72,
        minBPM: 71
    )
    .padding(16)
    .frame(width: 390)
    .background(heartRateGraphCardPreviewBackground)
}

#Preview("MIN path — increase") {
    HeartRateGraphCard(
        samples: HeartRateGraphCardPreviewSamples.minPathIncrease,
        startBPM: 68,
        endBPM: 78,
        minBPM: 72
    )
    .padding(16)
    .frame(width: 390)
    .background(heartRateGraphCardPreviewBackground)
}

#Preview("Legacy — START / END + percent") {
    HeartRateGraphCard(
        samples: HeartRateGraphCardPreviewSamples.relax,
        startBPM: 88,
        endBPM: 71,
        minBPM: nil
    )
    .padding(16)
    .frame(width: 390)
    .background(heartRateGraphCardPreviewBackground)
}

#Preview("Steady — legacy %") {
    HeartRateGraphCard(
        samples: HeartRateGraphCardPreviewSamples.steady,
        startBPM: 72,
        endBPM: 73,
        minBPM: nil
    )
    .padding(16)
    .frame(width: 390)
    .background(heartRateGraphCardPreviewBackground)
}

#Preview("No graph — not enough samples") {
    HeartRateGraphCard(
        samples: [],
        startBPM: 75,
        endBPM: 70,
        minBPM: nil
    )
    .padding(16)
    .frame(width: 390)
    .background(heartRateGraphCardPreviewBackground)
}
