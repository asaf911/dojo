import SwiftUI

/// A simple child view that displays heart-rate change info.
struct PracticeSummaryMetricView: View {
    let startBPM: Double
    let endBPM: Double
    let percentageChange: Double  // e.g. +25 => +25%

    var body: some View {
        VStack(spacing: 8) {
            Text(metricText())
                .nunitoFont(size: 18, style: .regular)
                .foregroundColor(.foregroundLightGray)
                .multilineTextAlignment(.leading)
        }
    }

    private func metricText() -> String {
        let fromRounded = String(format: "%.1f", startBPM)
        let toRounded   = String(format: "%.1f", endBPM)
        let pctRounded  = String(format: "%.1f", abs(percentageChange))

        if percentageChange > 0 {
            // BPM increased
            return """
            Hmmm... Your heart rate rose from \(fromRounded) BPM to \(toRounded) BPM, \
            a \(pctRounded)% increase.
            """
        } else if percentageChange < 0 {
            // BPM decreased
            return """
            Well done! Your heart rate dropped from \(fromRounded) BPM to \(toRounded) BPM, \
            a \(pctRounded)% decrease. 💜
            """
        } else {
            // No change
            return "Your heart rate stayed the same at \(fromRounded) BPM."
        }
    }
}

struct PracticeSummaryMetricView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Example: 80 -> 90 => +12.5%
            PracticeSummaryMetricView(startBPM: 80, endBPM: 90, percentageChange: +12.5)
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color.backgroundDarkPurple)

            // Example: 80 -> 70 => -12.5%
            PracticeSummaryMetricView(startBPM: 80, endBPM: 70, percentageChange: -12.5)
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color.backgroundDarkPurple)

            // Example: 80 -> 80 => 0.0%
            PracticeSummaryMetricView(startBPM: 80, endBPM: 80, percentageChange: 0.0)
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color.backgroundDarkPurple)
        }
    }
}
