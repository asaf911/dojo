import SwiftUI

struct Last7DaysChartView: View {
    @Binding var dailyStats: [DailyStat]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            
            GeometryReader { geometry in
                // Calculate available width and height
                let availableWidth = geometry.size.width
                let availableHeight = geometry.size.height
                
                // Determine the maximum duration to scale bar heights
                let maxDuration = dailyStats.map { $0.totalDuration }.max() ?? 1
                
                HStack(alignment: .bottom, spacing: 20) {
                    ForEach(dailyStats) { stat in
                        VStack(spacing: 5) {
                            // Duration Label Above Bar
                            Text("\(Int(stat.totalDuration / 60))")
                                .nunitoFont(size: 10, style: .medium)
                                .foregroundColor(.white)
                            
                            // Rounded Bar with gradient
                            Rectangle()
                                .foregroundColor(.clear)
                                .frame(
                                    width: 8,
                                    height: calculateBarHeight(
                                        duration: stat.totalDuration,
                                        maxDuration: maxDuration,
                                        availableHeight: max(availableHeight - 30, 0) // 30 for labels
                                    )
                                )
                                .background(
                                    LinearGradient(
                                        stops: [
                                            Gradient.Stop(color: Color(red: 0.88, green: 0.28, blue: 0.64), location: 0.00),
                                            Gradient.Stop(color: Color(red: 0.55, green: 0.33, blue: 1), location: 1.00),
                                        ],
                                        startPoint: UnitPoint(x: 0.44, y: 0),
                                        endPoint: UnitPoint(x: 0.44, y: 1)
                                    )
                                )
                                .cornerRadius(32)
                            
                            // Day Label Below Bar
                            Text(formatShortDate(stat.date))
                                .nunitoFont(size: 10, style: .medium)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: availableWidth, height: availableHeight, alignment: .bottom)
            }
            .frame(maxHeight: 195) // Fixed minimum height
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .surfaceBackground(cornerRadius: 20)
        .frame(minHeight: 195) // Ensure the entire view has at least 195px height
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily Minutes Practiced")
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.white)
            
            Text("Last 7 days")
                .nunitoFont(size: 14, style: .regular)
                .foregroundColor(.foregroundLightGray)
        }
    }

    // MARK: - Helper Functions
    
    /// Calculates the height of the bar based on duration and maximum duration.
    /// - Parameters:
    ///   - duration: The duration for the current day.
    ///   - maxDuration: The maximum duration among all days.
    ///   - availableHeight: The total available height for the bars.
    /// - Returns: The calculated height for the bar.
    private func calculateBarHeight(duration: Double, maxDuration: Double, availableHeight: CGFloat) -> CGFloat {
        guard maxDuration > 0 else { return 0 }
        let ratio = max(CGFloat(duration / maxDuration), 0)
        return ratio * max(availableHeight, 0)
    }
    
    /// Formats the date to a single-letter representation (e.g., "M" for Monday).
    /// - Parameter date: The date to format.
    /// - Returns: A single-letter string representing the day.
    private func formatShortDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEEE" // Single-letter day representation
        return dateFormatter.string(from: date)
    }
}

struct Last7DaysChartView_Previews: PreviewProvider {
    static var previews: some View {
        Last7DaysChartView(dailyStats: .constant(sampleDailyStats))
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.backgroundDarkPurple) // Ensure background contrasts with bars
    }

    static var sampleDailyStats: [DailyStat] {
        var stats = [DailyStat]()
        let calendar = Calendar.current
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: Date())!
            let duration = Double.random(in: 0...1800) // Random duration up to 30 minutes
            let stat = DailyStat(id: "\(i)", date: date, totalDuration: duration)
            stats.append(stat)
        }
        return stats.reversed()
    }
}

