import SwiftUI

struct StatCardView: View {
    var title: String
    var value: String
    var unit: String? = nil

    /// Optional percentage change. If set, we'll display it right after the unit
    /// e.g. "17m -27%" in the same font.
    var percentageChange: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1) Title
            Text(title)
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.white)

            // 2) Value + Unit + optional percentage
            HStack(spacing: 4) {
                Text(formattedValue(value))
                    .nunitoFont(size: 14, style: .regular)
                    .foregroundColor(.foregroundLightGray)

                if let pct = percentageChange {
                    Text(formatPercentageChange(pct))
                        .nunitoFont(size: 14, style: .regular)
                        .foregroundColor(colorForPercentage(pct))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .surfaceBackground(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .inset(by: 0.25)
                .stroke(Color.white.opacity(0.32), lineWidth: 0.5)
        )
    }

    // MARK: - Formatting

    /// Format the numeric or textual "value" you pass in, returning something like "17m"
    /// or "1h 55m" or "<1m". No extra space before the unit.
    private func formattedValue(_ value: String) -> String {
        // Handle the "<1m" case specifically
        if value == "<1m" {
            return "0\(unit ?? "m")"
        }
        
        // Attempt to parse as Double
        if let numericValue = Double(value) {
            // If numeric >= 1, we show "value + unit" (no space)
            if numericValue >= 1 {
                return "\(value)\(unit ?? "")"  // e.g. "17m"
            } else {
                // If < 1, fallback to "0 + unit"
                return "0\(unit ?? "")"        // e.g. "0m"
            }
        } else {
            // If not numeric (like "1h 55m"), return as-is
            return value
        }
    }

    /// Format a double like -27.3 as "-27%", +10.2 as "+10%".
    private func formatPercentageChange(_ pct: Double) -> String {
        let sign = pct > 0 ? "+" : ""
        return String(format: "%@%.0f%%", sign, pct)
    }

    /// Color-code the percentage: green if positive, red if negative, white if zero
    private func colorForPercentage(_ pct: Double) -> Color {
        if pct > 0 {
            return .green
        } else if pct < 0 {
            return .red
        }
        return .white
    }
}

struct StatCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 1) Basic usage (no percentageChange)
            StatCardView(title: "Total Practices", value: "10", unit: "m")
                .previewLayout(.sizeThatFits)
                .padding()
                .background(Color.backgroundDarkPurple)

            // 2) Negative percentage
            StatCardView(title: "Avg 7D Duration", value: "17", unit: "m", percentageChange: -27.0)
                .previewLayout(.sizeThatFits)
                .padding()
                .background(Color.backgroundDarkPurple)

            // 3) Positive percentage
            StatCardView(title: "Avg 7D Duration", value: "20", unit: "m", percentageChange: 15.5)
                .previewLayout(.sizeThatFits)
                .padding()
                .background(Color.backgroundDarkPurple)

            // 4) Textual value, not numeric
            StatCardView(title: "Overall Practice Time", value: "1h 55m")
                .previewLayout(.sizeThatFits)
                .padding()
                .background(Color.backgroundDarkPurple)

            // 5) A "<1m" case with negative percentage
            StatCardView(title: "Longest Practice", value: "0", unit: "m", percentageChange: -100)
                .previewLayout(.sizeThatFits)
                .padding()
                .background(Color.backgroundDarkPurple)

            // 6) A decimal under 1, e.g. "0.2" => "0m"
            StatCardView(title: "Tiny Duration", value: "0.2", unit: "m", percentageChange: -50)
                .previewLayout(.sizeThatFits)
                .padding()
                .background(Color.backgroundDarkPurple)
        }
    }
}
