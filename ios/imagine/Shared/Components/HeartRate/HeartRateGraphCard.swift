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
    let endBPM: Double
    
    private var percentChange: Double {
        guard startBPM > 0 else { return 0 }
        return ((endBPM - startBPM) / startBPM) * 100
    }
    
    private var isDecrease: Bool {
        endBPM < startBPM
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: Heart icon + "HEART RATE" + START/END values
            headerRow
            
            // Graph
            if samples.count >= 2 {
                HeartRateGraphView(
                    samples: samples,
                    startBPM: startBPM,
                    endBPM: endBPM
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
            if startBPM > 0 && endBPM > 0 {
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
            
            // END value
            HStack(spacing: 3) {
                Text("END")
                    .font(Font.custom("Nunito", size: 10))
                    .foregroundColor(.foregroundLightGray)
                Text("\(Int(round(endBPM))) bpm")
                    .font(Font.custom("Nunito", size: 10))
                    .foregroundColor(.foregroundLightGray)
            }
        }
    }
    
    // MARK: - Change Badge
    
    private var changeBadge: some View {
        let absPercent = abs(percentChange)
        let changeText = isDecrease ? "HR Decrease" : (percentChange > 0 ? "HR Increase" : "HR Steady")
        
        return HStack(spacing: 6) {
            // Circle with HR trend icon
            ZStack {
                // Background circle
                Circle()
                    .fill(Color.planTop)
                    .frame(width: 24, height: 24)
                
                // HR trend icon
                if isDecrease {
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
                    // Horizontal line for steady
                    Rectangle()
                        .fill(Color.selectedLightPurple)
                        .frame(width: 8, height: 2)
                }
            }
            
            // Percentage and label
            HStack(spacing: 4) {
                // Color matches the HR change direction
                let changeColor: Color = isDecrease ? .dojoTurquoise : (percentChange > 0 ? .hrHigh : .selectedLightPurple)
                
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
                // Good relaxation session (matches Figma)
                HeartRateGraphCard(
                    samples: sampleDataRelax,
                    startBPM: 88,
                    endBPM: 71
                )
                .previewDisplayName("20% Decrease")
                
                // Steady session
                HeartRateGraphCard(
                    samples: sampleDataSteady,
                    startBPM: 72,
                    endBPM: 73
                )
                .previewDisplayName("Steady")
                
                // Insufficient data
                HeartRateGraphCard(
                    samples: [],
                    startBPM: 75,
                    endBPM: 70
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
