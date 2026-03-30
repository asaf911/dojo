//
//  HeartRateGraphView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-17
//

import SwiftUI

struct HeartRateGraphView: View {
    let samples: [HeartRateSamplePoint]
    let startBPM: Double
    let endBPM: Double
    /// Right x-axis label: `"END"` (legacy) or `"MIN"` when surfacing session minimum.
    var trailingAxisLabel: String = "END"
    
    // Layout
    private let graphHeight: CGFloat = 140
    private let yAxisLabelWidth: CGFloat = 28
    private let verticalPadding: CGFloat = 8
    
    // MARK: - Dynamic Y-Axis Calculation (5 Fixed Stops)
    
    /// Calculate median BPM from samples
    private var medianBPM: Double {
        let sortedBPMs = samples.map { $0.bpm }.sorted()
        guard !sortedBPMs.isEmpty else { return 60 }
        
        let count = sortedBPMs.count
        if count % 2 == 0 {
            return (sortedBPMs[count/2 - 1] + sortedBPMs[count/2]) / 2
        } else {
            return sortedBPMs[count/2]
        }
    }
    
    /// Middle Y-axis stop - closest 10 to median BPM
    private var middleYAxis: Double {
        return (medianBPM / 10).rounded() * 10
    }
    
    /// Always 5 stops: middle +/- 20 BPM (10 BPM intervals)
    private var allYAxisStops: [Double] {
        let middle = middleYAxis
        return [
            middle + 20,  // Top
            middle + 10,
            middle,        // Middle
            middle - 10,
            middle - 20   // Bottom
        ]
    }
    
    /// Max Y-axis value (top stop)
    private var maxYAxis: Double {
        return middleYAxis + 20
    }
    
    /// Min Y-axis value (bottom stop)
    private var minYAxis: Double {
        return middleYAxis - 20
    }
    
    /// Y-axis steps (for backward compatibility - all 5 stops)
    private var yAxisSteps: [Double] {
        return allYAxisStops
    }
    
    // MARK: - Data Smoothing
    
    /// Target number of points for a smooth graph
    private let targetPointCount = 36
    
    /// Downsampled and smoothed samples for drawing
    private var smoothedSamples: [HeartRateSamplePoint] {
        guard samples.count > targetPointCount else { return samples }
        
        var result: [HeartRateSamplePoint] = []
        
        // Always keep the first point
        result.append(samples.first!)
        
        // Calculate bucket size for intermediate points
        let intermediateCount = targetPointCount - 2  // Excluding first and last
        let bucketSize = Double(samples.count - 2) / Double(intermediateCount)
        
        // Create averaged buckets for intermediate points
        for i in 0..<intermediateCount {
            let startIndex = 1 + Int(Double(i) * bucketSize)
            let endIndex = min(1 + Int(Double(i + 1) * bucketSize), samples.count - 1)
            
            guard startIndex < endIndex else { continue }
            
            let bucketSamples = Array(samples[startIndex..<endIndex])
            let avgBPM = bucketSamples.map { $0.bpm }.reduce(0, +) / Double(bucketSamples.count)
            let avgMinute = bucketSamples.map { $0.minuteOffset }.reduce(0, +) / Double(bucketSamples.count)
            
            result.append(HeartRateSamplePoint(minuteOffset: avgMinute, bpm: avgBPM))
        }
        
        // Always keep the last point
        result.append(samples.last!)
        
        return result
    }
    
    // Colors - vertical gradient: hrHigh (high BPM) at top, purple (low BPM) at bottom
    // Moderately distinct transition in the middle
    private let lineGradient = LinearGradient(
        stops: [
            Gradient.Stop(color: Color.hrHigh, location: 0.00),  // Top - max BPM (hrHigh)
            Gradient.Stop(color: Color.hrHigh, location: 0.20), // Hold hrHigh briefly
            Gradient.Stop(color: Color(red: 0.55, green: 0.33, blue: 1), location: 0.80),    // Transition to purple
            Gradient.Stop(color: Color(red: 0.55, green: 0.33, blue: 1), location: 1.00)     // Bottom - min BPM (purple)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    private let gridLineColor = Color.white.opacity(0.1)
    private let labelColor = Color.foregroundLightGray
    
    var body: some View {
        VStack(spacing: 4) {
            // Graph area with Y-axis labels
            HStack(alignment: .top, spacing: 4) {
                // Y-axis labels
                yAxisLabels
                
                // Graph content
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    
                    ZStack(alignment: .topLeading) {
                        // Horizontal grid lines
                        gridLines(in: CGSize(width: width, height: height))
                        
                        // Line path with gradient
                        if smoothedSamples.count > 1 {
                            linePath(in: CGSize(width: width, height: height))
                                .stroke(lineGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                .frame(height: graphHeight)
            }
            
            // X-axis labels
            HStack {
                Spacer().frame(width: yAxisLabelWidth + 4)
                
                HStack {
                    Text("START")
                        .font(Font.custom("Nunito", size: 10).weight(.semibold))
                        .foregroundColor(labelColor)
                    
                    Spacer()
                    
                    Text("MID")
                        .font(Font.custom("Nunito", size: 10).weight(.semibold))
                        .foregroundColor(labelColor)
                    
                    Spacer()
                    
                    Text(trailingAxisLabel)
                        .font(Font.custom("Nunito", size: 10).weight(.semibold))
                        .foregroundColor(labelColor)
                }
            }
        }
    }
    
    // MARK: - Y-Axis Labels
    
    /// All Y-axis label values (5 fixed stops, top to bottom)
    private var allYAxisLabels: [Double] {
        return allYAxisStops
    }
    
    private var yAxisLabels: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            
            ZStack(alignment: .topTrailing) {
                ForEach(allYAxisLabels, id: \.self) { value in
                    let yPosition = yPositionForBPM(value, in: height)
                    
                    Text("\(Int(value))")
                        .font(Font.custom("Nunito", size: 10).weight(.medium))
                        .foregroundColor(labelColor)
                        .position(x: 9, y: yPosition) // Aligned to center of heart icon (18/2 = 9)
                }
            }
        }
        .frame(width: yAxisLabelWidth, height: graphHeight)
    }
    
    // MARK: - Grid Lines
    
    /// All Y values that need grid lines (5 fixed stops)
    private var allGridLineValues: [Double] {
        return allYAxisStops
    }
    
    private func gridLines(in size: CGSize) -> some View {
        ZStack {
            // Draw grid lines for all Y values including top/bottom boundaries
            ForEach(allGridLineValues, id: \.self) { value in
                let yPosition = yPositionForBPM(value, in: size.height)
                
                Path { path in
                    path.move(to: CGPoint(x: 0, y: yPosition))
                    path.addLine(to: CGPoint(x: size.width, y: yPosition))
                }
                .stroke(gridLineColor, style: StrokeStyle(lineWidth: 1))
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var maxMinutes: Double {
        samples.map { $0.minuteOffset }.max() ?? 1
    }
    
    private var yAxisRange: Double {
        maxYAxis - minYAxis
    }
    
    // MARK: - Position Calculations
    
    private func yPositionForBPM(_ bpm: Double, in height: CGFloat) -> CGFloat {
        let clampedBPM = max(minYAxis, min(maxYAxis, bpm))
        let ratio = (clampedBPM - minYAxis) / yAxisRange
        return height - (height * ratio)
    }
    
    private func pointPosition(for sample: HeartRateSamplePoint, in size: CGSize) -> CGPoint {
        let xRatio = maxMinutes > 0 ? sample.minuteOffset / maxMinutes : 0
        let x = size.width * xRatio
        let y = yPositionForBPM(sample.bpm, in: size.height)
        
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Path Builders (Smooth Curved Lines)
    
    private func linePath(in size: CGSize) -> Path {
        Path { path in
            guard smoothedSamples.count >= 2 else { return }
            
            let points = smoothedSamples.map { pointPosition(for: $0, in: size) }
            
            if points.count == 2 {
                path.move(to: points[0])
                path.addLine(to: points[1])
                return
            }
            
            path.move(to: points[0])
            
            // Create smooth curves using cubic Bezier with calculated control points
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]
                
                // Look ahead and behind for smoother control points
                let prevPrev = i >= 2 ? points[i - 2] : prev
                let next = i < points.count - 1 ? points[i + 1] : curr
                
                // Calculate control points with higher curvature
                let smoothing: CGFloat = 0.25  // Controls curve intensity
                
                // First control point - based on direction from prevPrev to curr
                let cp1 = CGPoint(
                    x: prev.x + (curr.x - prevPrev.x) * smoothing,
                    y: prev.y + (curr.y - prevPrev.y) * smoothing
                )
                
                // Second control point - based on direction from next to prev
                let cp2 = CGPoint(
                    x: curr.x - (next.x - prev.x) * smoothing,
                    y: curr.y - (next.y - prev.y) * smoothing
                )
                
                path.addCurve(to: curr, control1: cp1, control2: cp2)
            }
        }
    }
    
    private func areaPath(in size: CGSize) -> Path {
        Path { path in
            guard smoothedSamples.count >= 2 else { return }
            
            let points = smoothedSamples.map { pointPosition(for: $0, in: size) }
            
            // Start at bottom-left
            path.move(to: CGPoint(x: points[0].x, y: size.height))
            path.addLine(to: points[0])
            
            if points.count == 2 {
                path.addLine(to: points[1])
            } else {
                // Match the line path curves exactly
                for i in 1..<points.count {
                    let prev = points[i - 1]
                    let curr = points[i]
                    let prevPrev = i >= 2 ? points[i - 2] : prev
                    let next = i < points.count - 1 ? points[i + 1] : curr
                    
                    let smoothing: CGFloat = 0.25
                    
                    let cp1 = CGPoint(
                        x: prev.x + (curr.x - prevPrev.x) * smoothing,
                        y: prev.y + (curr.y - prevPrev.y) * smoothing
                    )
                    
                    let cp2 = CGPoint(
                        x: curr.x - (next.x - prev.x) * smoothing,
                        y: curr.y - (next.y - prev.y) * smoothing
                    )
                    
                    path.addCurve(to: curr, control1: cp1, control2: cp2)
                }
            }
            
            // Close the path at the bottom
            path.addLine(to: CGPoint(x: points.last!.x, y: size.height))
            path.closeSubpath()
        }
    }
}

// MARK: - Preview

struct HeartRateGraphView_Previews: PreviewProvider {
    static var previews: some View {
        HeartRateGraphView(
            samples: sampleData,
            startBPM: 88,
            endBPM: 71,
            trailingAxisLabel: "MIN"
        )
        .padding()
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .previewLayout(.sizeThatFits)
    }
    
    static var sampleData: [HeartRateSamplePoint] {
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
}
