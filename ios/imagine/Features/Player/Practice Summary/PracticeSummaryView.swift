import SwiftUI

/// Displays a combined summary after a practice:
///  1) Title
///  2) Optional BPM metric (if `startBPM` or `endBPM` are non-zero AND Apple Watch is paired)
///  3) PracticeRatingView for user rating
struct PracticeSummaryView: View {
    let practiceTitle: String
    let contentDetails: String
    let practiceDurationMinutes: Int
    let completionRate: Double
    let completedAt: String

    let startBPM: Double
    let endBPM: Double

    // Callback to dismiss
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.backgroundDarkPurple.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerView
                    subtitleView

        // Show BPM metric if we have any BPM data
        if startBPM != 0 || endBPM != 0 {
                        PracticeSummaryMetricView(
                            startBPM: startBPM,
                            endBPM: endBPM,
                            percentageChange: computePercentChange()
                        )
                    }

                    PracticeRatingView(
                        practiceTitle: practiceTitle,
                        contentDetails: contentDetails,
                        practiceDurationMinutes: practiceDurationMinutes,
                        completionRate: completionRate,
                        completedAt: completedAt
                    ) {
                        // Once user picks rating, dismiss
                        withAnimation {
                            onDismiss()
                        }
                    }

                    Spacer().frame(height: 10)
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // Title
    private var headerView: some View {
        Text(practiceTitle)
            .nunitoFont(size: 28, style: .bold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Subtitle
    private var subtitleView: some View {
        Text("Practice_Completed")
            .nunitoFont(size: 18, style: .medium)
            .foregroundColor(.foregroundLightGray)
    }

    private func computePercentChange() -> Double {
        guard startBPM != 0 else { return 0 }
        return ((endBPM - startBPM) / startBPM) * 100.0
    }
}


// MARK: - Preview

struct PracticeSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        PracticeSummaryView(
            practiceTitle: "Morning Calm",
            contentDetails: "Morning Calm Audio",
            practiceDurationMinutes: 10,
            completionRate: 95.0,
            completedAt: "10:30",
            startBPM: 80,
            endBPM: 70
        ) {
            print("PracticeSummaryView dismissed.")
        }
        .background(Color.backgroundDarkPurple)
        .previewLayout(.sizeThatFits)
    }
}
