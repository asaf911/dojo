//
//  PracticeRatingView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-17
//

import SwiftUI

struct PracticeRatingView: View {
    // MARK: - Properties

    var practiceTitle: String
    var contentDetails: String
    var practiceDurationMinutes: Int
    var completionRate: Double
    var completedAt: String
    var onDismiss: () -> Void  // Called after user selects a rating

    // MARK: - State

    @State private var userRating: Rating? = nil

    /// Enum to represent possible ratings
    enum Rating {
        case good
        case bad
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            // Prompt: "How was your session?"
            Text("How was your session?")
                .nunitoFont(size: 18, style: .medium)
                .foregroundColor(.foregroundLightGray)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // HStack with Thumbs Down / Thumbs Up
            HStack(spacing: 35) {
                // Thumbs Down
                Button(action: {
                    handleRating(isPositive: false)
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.backgroundPurple)
                            .frame(width: 60, height: 60)
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

                        Image(systemName: userRating == .bad
                              ? "hand.thumbsdown.fill"
                              : "hand.thumbsdown"
                        )
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                        .foregroundColor(.white)
                    }
                }
                .accessibilityLabel("Thumbs Down")
                .accessibilityHint("Rate the session as bad")

                // Thumbs Up
                Button(action: {
                    handleRating(isPositive: true)
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.backgroundPurple)
                            .frame(width: 60, height: 60)
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

                        Image(systemName: userRating == .good
                              ? "hand.thumbsup.fill"
                              : "hand.thumbsup"
                        )
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                        .foregroundColor(.white)
                    }
                }
                .accessibilityLabel("Thumbs Up")
                .accessibilityHint("Rate the session as good")
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        // Smooth transition
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Rating Handling

    private func handleRating(isPositive: Bool) {
        // Update local state
        userRating = isPositive ? .good : .bad

        // Prepare event parameters
        var parameters: [String: Any] = [
            "content_details": contentDetails,
            "practice_duration_minutes": practiceDurationMinutes,
            "title": practiceTitle,
            "rating": isPositive ? "Good" : "Bad",
            "completion_rate": completionRate,
            "completed_at": completedAt
        ]
        // For practice rating events, source remains empty.
        parameters["source"] = ""
        
        // Log the event
        AnalyticsManager.shared.logEvent("practice_rated", parameters: parameters)

        // Provide haptic feedback
        HapticManager.shared.impact(.medium)

        // Now that a rating is chosen, we dismiss
        withAnimation {
            onDismiss()
        }
    }
}

// MARK: - Preview

struct PracticeRatingView_Previews: PreviewProvider {
    static var previews: some View {
        PracticeRatingView(
            practiceTitle: "Morning Meditation",
            contentDetails: "Morning Meditation Session",
            practiceDurationMinutes: 25,
            completionRate: 100.0,
            completedAt: "08:45 AM",
            onDismiss: {
                print("PracticeRatingView dismissed")
            }
        )
        .background(Color.backgroundDarkPurple)
        .previewLayout(.sizeThatFits)
    }
}
