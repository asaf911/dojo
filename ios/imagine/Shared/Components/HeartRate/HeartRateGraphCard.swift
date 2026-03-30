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

    private var secondColumnBPM: Double {
        usesMinPresentation ? (minBPM ?? endBPM) : endBPM
    }

    private var secondColumnLabel: String {
        usesMinPresentation ? "MIN" : "END"
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
            // Header row: Heart icon + "HEART RATE" + START/END or START/MIN values
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
            // Heart icon
            Image("heartIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundColor(.white)

            // "HEART RATE" label
            Text("HEART RATE")
                .font(Font.custom("Nunito", size: 14).weight(.semibold))
                .foregroundColor(.foregroundLightGray)
                .padding(.leading, 6)

            Spacer()

            // START value
            HStack(spacing: 3) {
                Text("START")
                    .font(Font.custom("Nunito", size: 10))
                    .foregroundColor(.foregroundLightGray)
                Text("\(Int(round(startBPM))) bpm")
                    .font(Font.custom("Nunito", size: 10))
                    .foregroundColor(.foregroundLightGray)
            }

            // Separator
            Text("  ")

            // MIN or END value
            HStack(spacing: 3) {
                Text(secondColumnLabel)
                    .font(Font.custom("Nunito", size: 10))
                    .foregroundColor(.foregroundLightGray)
                Text("\(Int(round(secondColumnBPM))) bpm")
                    .font(Font.custom("Nunito", size: 10))
                    .foregroundColor(.foregroundLightGray)
            }
        }
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
            if minPathIsSteady { return "HR Steady" }
            if minPathIsDecrease { return "HR Decrease" }
            if minPathIsIncrease { return "HR Increase" }
            return "HR Steady"
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

// MARK: - Preview

struct HeartRateGraphCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MIN presentation + BPM delta
                HeartRateGraphCard(
                    samples: sampleDataRelax,
                    startBPM: 88,
                    endBPM: 71,
                    minBPM: 68
                )
                .previewDisplayName("MIN path — decrease")

                // Legacy END + percent
                HeartRateGraphCard(
                    samples: sampleDataRelax,
                    startBPM: 88,
                    endBPM: 71,
                    minBPM: nil
                )
                .previewDisplayName("Legacy END + %")

                // Steady session (legacy)
                HeartRateGraphCard(
                    samples: sampleDataSteady,
                    startBPM: 72,
                    endBPM: 73,
                    minBPM: nil
                )
                .previewDisplayName("Steady legacy")

                // Insufficient data
                HeartRateGraphCard(
                    samples: [],
                    startBPM: 75,
                    endBPM: 70,
                    minBPM: nil
                )
                .previewDisplayName("No Graph Data")
            }
            .padding()
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .previewLayout(.sizeThatFits)
    }

    static var sampleDataRelax: [HeartRateSamplePoint] {
        [
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
    }

    static var sampleDataSteady: [HeartRateSamplePoint] {
        [
            HeartRateSamplePoint(minuteOffset: 0, bpm: 72),
            HeartRateSamplePoint(minuteOffset: 1, bpm: 73),
            HeartRateSamplePoint(minuteOffset: 2, bpm: 72),
            HeartRateSamplePoint(minuteOffset: 3, bpm: 71),
            HeartRateSamplePoint(minuteOffset: 4, bpm: 72),
            HeartRateSamplePoint(minuteOffset: 5, bpm: 73)
        ]
    }
}
