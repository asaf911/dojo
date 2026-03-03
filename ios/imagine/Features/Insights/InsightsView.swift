//
//  InsightsView.swift
//  Dojo
//
//  Created by Asaf Shamir on 12/13/24
//  Updated to include the universal HeaderView with title "Measured Mastery" and subtitle "Only disciplined practice produces results", with the header out of the horizontal padding.
//  The system back button is hidden and a custom back button in HeaderView is used instead.
//
import SwiftUI
import FirebaseAuth

struct InsightsView: View {
    // MARK: - Environment Services (DI)
    @Environment(\.statsService) private var stats
    @Environment(\.analyticsService) private var analytics
    
    @State private var totalSessionDuration: Double = 0.0
    @State private var meditationStreak: Int = 0
    @State private var longestMeditationStreak: Int = 0
    @State private var sessionCount: Int = 0
    @State private var averageSessionDuration: Double = 0.0
    @State private var longestSessionDuration: Double = 0.0
    @State private var dailyStats: [DailyStat] = []
    
    // 7-day average daily minutes & comparison
    @State private var last7DaysAvgMinutes: Double = 0.0
    @State private var prev7DaysAvgMinutes: Double = 0.0
    @State private var percentChange: Double = 0.0
    
    // Use presentationMode for custom back button action.
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.toggleMenu) private var toggleMenu
    @EnvironmentObject var appState: AppState
    @ObservedObject var authViewModel = AuthViewModel()
    @State private var showAccountCreationSheet = false
    let useContainer: Bool
    
    init(showHeaderAndBackground: Bool = true) {
        self.useContainer = showHeaderAndBackground
    }

    var body: some View {
        Group {
            if useContainer {
                DojoScreenContainer(
                    headerTitle: "Progress",
                    headerSubtitle: "",
                    backgroundImageName: "InsightsBackground",
                    backAction: { presentationMode.wrappedValue.dismiss() },
                    showBackButton: false,
                    menuAction: toggleMenu,
                    showMenuButton: true
                ) {
                    contentView
                }
            } else {
                contentView
                    .background(Color.backgroundNavy)
            }
        }
        .onAppear {
            // First load from local cache for immediate display
            loadStats()
            load14DayStats()
            
            // Then sync from Firebase to ensure data is fresh and user-specific
            // This is critical when switching between users to prevent stale/mixed data
            syncFromFirebaseAndReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didUpdateSessionCount)) { _ in
            loadStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didUpdateAverageSessionDuration)) { _ in
            loadStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didUpdateMeditationStreak)) { _ in
            loadStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didUpdateLongestMeditationStreak)) { _ in
            loadStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didUpdateLongestSessionDuration)) { _ in
            loadStats()
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureSetter())
        .background(Color.clear)
    }
    
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer().frame(height: 5)
                VStack(alignment: .leading, spacing: 16) {
                    BigMetricView(
                        title: "Overall Practice Time",
                        value: formatTime(totalSessionDuration)
                    )
                    Last7DaysChartView(dailyStats: $dailyStats)
                    HStack(spacing: 16) {
                        StatCardView(
                            title: "Total Practices",
                            value: "\(sessionCount)"
                        )
                        StatCardView(
                            title: "7D Avg",
                            value: String(format: "%.1f", last7DaysAvgMinutes),
                            unit: "m",
                            percentageChange: percentChange
                        )
                    }
                    StatCardView(
                        title: "Longest Practice",
                        value: formatTime(longestSessionDuration)
                    )
                    HStack(spacing: 14) {
                        StatCardView(
                            title: "Current Streak",
                            value: "\(meditationStreak)",
                            unit: " day\(meditationStreak == 1 ? "" : "s")"
                        )
                        StatCardView(
                            title: "Best Streak",
                            value: "\(longestMeditationStreak)",
                            unit: " day\(longestMeditationStreak == 1 ? "" : "s")"
                        )
                    }
                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .frame(maxWidth: .infinity)
        }
        .topFadeMask(height: 5)
    }
    
    private func loadStats() {
        // Use injected stats service for DI-friendly access
        totalSessionDuration = stats.getTotalSessionDuration()
        sessionCount = stats.getSessionCount()
        averageSessionDuration = stats.getAverageSessionDuration()
        longestSessionDuration = stats.getLongestSessionDuration()
        meditationStreak = stats.getMeditationStreak()
        longestMeditationStreak = stats.getLongestMeditationStreak()
        
        // Still use StatsManager for async fetch (Firestore integration)
        StatsManager.shared.fetchLast7DaysStats { fetchedStats in
            DispatchQueue.main.async {
                self.dailyStats = fetchedStats
            }
        }
    }
    
    private func load14DayStats() {
        StatsManager.shared.fetchLast14DaysStats { finalStats in
            DispatchQueue.main.async {
                if finalStats.count < 14 { return }
                let last7 = Array(finalStats.suffix(7))
                let prev7 = Array(finalStats.dropLast(7).suffix(7))
                
                let sm = StatsManager.shared
                let avgCurrent = sm.averageDailyMinutes(for: last7)
                let avgPrevious = sm.averageDailyMinutes(for: prev7)
                let pctChange = sm.computePercentageChange(from: avgPrevious, to: avgCurrent)
                
                self.last7DaysAvgMinutes = avgCurrent
                self.prev7DaysAvgMinutes = avgPrevious
                self.percentChange = pctChange
            }
        }
    }
    
    /// Syncs stats from Firebase and reloads the view.
    /// This ensures users always see their actual stats, not stale local data.
    private func syncFromFirebaseAndReload() {
        StatsManager.shared.syncStatsFromFirestore { success in
            if success {
                DispatchQueue.main.async {
                    // Reload stats after sync completes
                    self.loadStats()
                    
                    // Also reload StreakManager's in-memory data
                    StreakManager.shared.reloadFromLocalStorage()
                }
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let totalMinutes = Int(time / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "0"
        }
    }
    
    /// Determines if the account creation sheet should be shown
    /// Returns true ONLY for guest users who need to create an account
    /// Returns false for users who already authenticated via email/google/apple
    private func shouldShowAccountCreation() -> Bool {
        // **CLEAR FLAG SYSTEM:**
        
        // 1. Check authentication method - if user signed up/signed in with email/google/apple, DON'T show
        let authMethod = SharedUserStorage.retrieve(forKey: .authenticationMethod, as: AuthenticationMethod.self)
        if let method = authMethod {
            switch method {
            case .email, .google, .apple:
                // User has a real account - NEVER show account creation
                return false
            case .guest:
                // User is guest - ALWAYS show account creation
                return true
            case .none:
                break // Continue to other checks
            }
        }
        
        // 2. Fallback check: if user is explicitly marked as guest in AppState, show account creation
        if appState.isGuest {
            return true
        }
        
        // 3. If user is properly authenticated (not guest), don't show
        if appState.isAuthenticated {
            return false
        }
        
        // 4. If user has a Firebase account, they're authenticated - don't show
        if Auth.auth().currentUser != nil {
            return false
        }
        
        // 5. Default: if no clear authentication method and no Firebase account, show account creation
        return true
    }
}

#if DEBUG
#Preview {
    InsightsView()
        .withPreviewEnvironment(streak: 5)
        .environmentObject(AppState())
        .background(Color.backgroundDarkPurple)
}
#endif
