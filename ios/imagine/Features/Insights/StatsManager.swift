import Foundation
import FirebaseAuth

final class StatsManager {
    static let shared = StatsManager()

    private init() {}

    // MARK: - Public Getters

    func getTotalSessionDuration() -> TimeInterval {
        let val = SharedUserStorage.retrieve(forKey: .totalSessionDuration, as: Double.self) ?? 0.0
        print("StatsManager: getTotalSessionDuration returning \(val)")
        return val
    }

    func getSessionCount() -> Int {
        let val = SharedUserStorage.retrieve(forKey: .sessionCount, as: Int.self) ?? 0
        print("StatsManager: getSessionCount returning \(val)")
        return val
    }

    func getAverageSessionDuration() -> TimeInterval {
        let total = getTotalSessionDuration()
        let count = getSessionCount()
        let avg = count == 0 ? 0.0 : total / Double(count)
        print("StatsManager: getAverageSessionDuration total=\(total), count=\(count), avg=\(avg)")
        return avg
    }

    func getLongestSessionDuration() -> TimeInterval {
        let val = SharedUserStorage.retrieve(forKey: .longestSessionDuration, as: Double.self) ?? 0.0
        print("StatsManager: getLongestSessionDuration returning \(val)")
        return val
    }

    func getMeditationStreak() -> Int {
        let val = StreakManager.shared.getMeditationStreak()
        print("StatsManager: getMeditationStreak returning \(val)")
        return val
    }

    func getLongestMeditationStreak() -> Int {
        let val = StreakManager.shared.getLongestMeditationStreak()
        print("StatsManager: getLongestMeditationStreak returning \(val)")
        return val
    }

    /// Fetch last 7 days (existing method)
    func fetchLast7DaysStats(completion: @escaping ([DailyStat]) -> Void) {
        logger.debugMessage("Fetching last 7 days stats...", function: #function, line: #line, file: #file)
        FirestoreManager.shared.fetchLast7DaysStats { stats in
            logger.debugMessage("Fetched last 7 days stats count: \(stats.count)", function: #function, line: #line, file: #file)
            completion(stats)
        }
    }

    // MARK: - Update Methods

    func updateMetricsOnSessionCompletion(practiceID: String, startDate: Date, endDate: Date) {
        let duration = endDate.timeIntervalSince(startDate)
        logger.debugMessage("updateMetricsOnSessionCompletion called with duration: \(duration)", function: #function, line: #line, file: #file)

        updateSessionMetrics(with: duration)
        // Use new StreakManager for streak updates
        let _ = StreakManager.shared.updateStreakOnSessionCompletion()
        updateDailyStats(with: duration)

        HealthKitManager.shared.saveMindfulnessSession(startDate: startDate, endDate: endDate) { success, error in
            if success {
                logger.eventMessage("Mindfulness session saved to HealthKit for Practice ID: \(practiceID).")
            } else {
                logger.errorMessage("Failed to save mindfulness session to HealthKit: \(error?.localizedDescription ?? "Unknown error")")
            }
        }

        logPracticeSessionSummary(practiceID: practiceID, startDate: startDate, endDate: endDate, duration: duration)
        notifyStatsChanged()
    }

    private func updateSessionMetrics(with duration: TimeInterval) {
        let prevCount = getSessionCount()
        let newCount = prevCount + 1
        SharedUserStorage.save(value: newCount, forKey: .sessionCount)
        FirestoreManager.shared.updateSessionCount(newCount)
        logger.debugMessage("Session count updated from \(prevCount) to \(newCount)", function: #function, line: #line, file: #file)
        
        // Fire session milestone events at sessions 1, 2, and 3 (activation funnel)
        if newCount <= 3 {
            logger.eventMessage("StatsManager: session milestone reached count=\(newCount) — firing JourneyAnalytics")
            JourneyAnalytics.logSessionMilestone(newCount)
        }

        let prevTotal = getTotalSessionDuration()
        let newTotal = prevTotal + duration
        SharedUserStorage.save(value: newTotal, forKey: .totalSessionDuration)
        FirestoreManager.shared.updateTotalSessionDuration(newTotal)
        logger.debugMessage("Total session duration updated from \(prevTotal) to \(newTotal)", function: #function, line: #line, file: #file)

        let prevLongest = getLongestSessionDuration()
        if duration > prevLongest {
            SharedUserStorage.save(value: duration, forKey: .longestSessionDuration)
            FirestoreManager.shared.updateLongestSessionDuration(duration)
            logger.debugMessage("Longest session duration updated from \(prevLongest) to \(duration)", function: #function, line: #line, file: #file)
            NotificationCenter.default.post(name: .didUpdateLongestSessionDuration, object: nil)
        }

        NotificationCenter.default.post(name: .didUpdateSessionCount, object: nil)
        NotificationCenter.default.post(name: .didUpdateAverageSessionDuration, object: nil)
    }

    // NOTE: This method is deprecated and replaced by StreakManager
    // Kept for backward compatibility but no longer used
    private func updateMeditationStreak() {
        // This method is now handled by StreakManager.shared.updateStreakOnSessionCompletion()
        logger.debugMessage("updateMeditationStreak: This method is deprecated. Use StreakManager instead.", function: #function, line: #line, file: #file)
    }

    private func updateDailyStats(with duration: TimeInterval) {
        logger.debugMessage("Updating daily stats with duration: \(duration)", function: #function, line: #line, file: #file)
        FirestoreManager.shared.updateDailyStats(with: duration)
    }

    private func logPracticeSessionSummary(practiceID: String, startDate: Date, endDate: Date, duration: TimeInterval) {
        let completedDurationSeconds = Int(duration)
        let sessionCount = getSessionCount()
        let averageSessionDurationSeconds = Int(getAverageSessionDuration())
        let longestSessionDurationSeconds = Int(getLongestSessionDuration())
        let currentMeditationStreak = getMeditationStreak()
        let longestMeditationStreak = getLongestMeditationStreak()

        logger.debugMessage("Logging practice session summary with practiceID \(practiceID): duration=\(completedDurationSeconds) secs, sessionCount=\(sessionCount), avgSession=\(averageSessionDurationSeconds), longest=\(longestSessionDurationSeconds), streak=\(currentMeditationStreak), longestStreak=\(longestMeditationStreak)", function: #function, line: #line, file: #file)

        AnalyticsManager.shared.logEvent("practice_session_summary", parameters: [
            "practice_id": practiceID,
            "duration_seconds": completedDurationSeconds,
            "session_count": sessionCount,
            "average_session_duration_seconds": averageSessionDurationSeconds,
            "longest_session_duration_seconds": longestSessionDurationSeconds,
            "current_meditation_streak": currentMeditationStreak,
            "longest_meditation_streak": longestMeditationStreak
        ])
    }

    private func notifyStatsChanged() {
        logger.debugMessage("Stats changed notification sent.", function: #function, line: #line, file: #file)
    }

    // MARK: - Stats Migration
    
    private static let statsMigrationKey = "StatsManager_FirebaseMigration_v1_Completed"
    
    /// Checks if stats have been migrated to Firebase for this user.
    /// Migration is tracked per-user using their Firebase UID.
    private func getMigrationKey() -> String {
        let uid = FirebaseAuth.Auth.auth().currentUser?.uid ?? "unknown"
        return "\(StatsManager.statsMigrationKey)_\(uid)"
    }
    
    /// One-time migration: Push local UserDefaults stats to Firebase.
    /// This preserves existing user data and makes Firebase the source of truth.
    /// After migration, all reads come from Firebase.
    func migrateStatsToFirebaseIfNeeded(completion: @escaping (Bool) -> Void) {
        let migrationKey = getMigrationKey()
        let migrationCompleted = UserDefaults.standard.bool(forKey: migrationKey)
        
        if migrationCompleted {
            logger.debugMessage("Stats migration already completed for this user. Skipping.", function: #function, line: #line, file: #file)
            completion(true)
            return
        }
        
        logger.debugMessage("Starting one-time stats migration to Firebase...", function: #function, line: #line, file: #file)
        
        // Capture local values (what the user currently sees)
        let localSessionCount = SharedUserStorage.retrieve(forKey: .sessionCount, as: Int.self) ?? 0
        let localTotalDuration = SharedUserStorage.retrieve(forKey: .totalSessionDuration, as: Double.self) ?? 0.0
        let localLongestSession = SharedUserStorage.retrieve(forKey: .longestSessionDuration, as: Double.self) ?? 0.0
        
        logger.debugMessage("Local stats - sessionCount: \(localSessionCount), totalDuration: \(localTotalDuration), longestSession: \(localLongestSession)", function: #function, line: #line, file: #file)
        
        // Fetch Firebase values to compare
        let group = DispatchGroup()
        var firebaseSessionCount = 0
        var firebaseTotalDuration = 0.0
        var firebaseLongestSession = 0.0
        
        group.enter()
        FirestoreManager.shared.fetchSessionCount { count in
            firebaseSessionCount = count
            group.leave()
        }
        
        group.enter()
        FirestoreManager.shared.fetchTotalSessionDuration { duration in
            firebaseTotalDuration = duration
            group.leave()
        }
        
        group.enter()
        FirestoreManager.shared.fetchLongestSessionDuration { longest in
            firebaseLongestSession = longest
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard self != nil else {
                completion(false)
                return
            }
            
            logger.debugMessage("Firebase stats - sessionCount: \(firebaseSessionCount), totalDuration: \(firebaseTotalDuration), longestSession: \(firebaseLongestSession)", function: #function, line: #line, file: #file)
            
            // For monotonically increasing stats, use MAX(local, firebase)
            // This ensures we never lose user data
            let finalSessionCount = max(localSessionCount, firebaseSessionCount)
            let finalTotalDuration = max(localTotalDuration, firebaseTotalDuration)
            let finalLongestSession = max(localLongestSession, firebaseLongestSession)
            
            // Push merged values to Firebase (making Firebase the source of truth)
            if finalSessionCount > firebaseSessionCount {
                FirestoreManager.shared.updateSessionCount(finalSessionCount)
                logger.debugMessage("Migration: Pushed sessionCount \(finalSessionCount) to Firebase (was \(firebaseSessionCount))", function: #function, line: #line, file: #file)
            }
            
            if finalTotalDuration > firebaseTotalDuration {
                FirestoreManager.shared.updateTotalSessionDuration(finalTotalDuration)
                logger.debugMessage("Migration: Pushed totalDuration \(finalTotalDuration) to Firebase (was \(firebaseTotalDuration))", function: #function, line: #line, file: #file)
            }
            
            if finalLongestSession > firebaseLongestSession {
                FirestoreManager.shared.updateLongestSessionDuration(finalLongestSession)
                logger.debugMessage("Migration: Pushed longestSession \(finalLongestSession) to Firebase (was \(firebaseLongestSession))", function: #function, line: #line, file: #file)
            }
            
            // Update local storage with final values
            SharedUserStorage.save(value: finalSessionCount, forKey: .sessionCount)
            SharedUserStorage.save(value: finalTotalDuration, forKey: .totalSessionDuration)
            SharedUserStorage.save(value: finalLongestSession, forKey: .longestSessionDuration)
            
            // Migrate streak data using StreakManager
            StreakManager.shared.migrateToFirebaseIfNeeded { streakSuccess in
                logger.debugMessage("Streak migration completed: \(streakSuccess)", function: #function, line: #line, file: #file)
                
                // Mark migration as complete for this user
                UserDefaults.standard.set(true, forKey: migrationKey)
                
                logger.debugMessage("Stats migration complete - sessionCount: \(finalSessionCount), totalDuration: \(finalTotalDuration), longestSession: \(finalLongestSession)", function: #function, line: #line, file: #file)
                
                completion(true)
            }
        }
    }
    
    // MARK: - Firestore Sync
    
    /// Syncs stats FROM Firebase to local storage.
    /// Call this AFTER migration is complete - Firebase is the source of truth.
    func syncStatsFromFirestore(completion: @escaping (Bool) -> Void) {
        logger.debugMessage("Starting syncStatsFromFirestore...", function: #function, line: #line, file: #file)
        let group = DispatchGroup()

        group.enter()
        FirestoreManager.shared.fetchSessionCount { count in
            logger.debugMessage("Fetched sessionCount from Firestore: \(count)", function: #function, line: #line, file: #file)
            SharedUserStorage.save(value: count, forKey: .sessionCount)
            group.leave()
        }

        group.enter()
        FirestoreManager.shared.fetchTotalSessionDuration { duration in
            logger.debugMessage("Fetched totalSessionDuration from Firestore: \(duration)", function: #function, line: #line, file: #file)
            SharedUserStorage.save(value: duration, forKey: .totalSessionDuration)
            group.leave()
        }

        group.enter()
        FirestoreManager.shared.fetchLongestSessionDuration { longest in
            logger.debugMessage("Fetched longestSessionDuration from Firestore: \(longest)", function: #function, line: #line, file: #file)
            SharedUserStorage.save(value: longest, forKey: .longestSessionDuration)
            group.leave()
        }

        // Use StreakManager for syncing streak data
        group.enter()
        StreakManager.shared.syncFromFirestore { success in
            logger.debugMessage("Synced streak data from Firestore: \(success)", function: #function, line: #line, file: #file)
            group.leave()
        }

        group.notify(queue: .main) {
            logger.debugMessage("syncStatsFromFirestore complete. Calling completion(true).", function: #function, line: #line, file: #file)
            completion(true)
        }
    }
    
    /// Combined migration and sync - call this on app launch/login.
    /// Runs migration if needed, then syncs from Firebase.
    func migrateAndSyncStats(completion: @escaping (Bool) -> Void) {
        migrateStatsToFirebaseIfNeeded { [weak self] migrationSuccess in
            guard migrationSuccess else {
                logger.debugMessage("Migration failed, skipping sync", function: #function, line: #line, file: #file)
                completion(false)
                return
            }
            
            self?.syncStatsFromFirestore { syncSuccess in
                completion(syncSuccess)
            }
        }
    }

    // MARK: - Streak Reset if Day Missed

    func resetStreakIfNeededOnAppLaunch() {
        // Delegate to StreakManager
        StreakManager.shared.resetStreakIfNeededOnAppLaunch()
    }

    // MARK: - NEW: 14-Day Stats + Average / Comparison

    /// Fetches daily stats for the last 14 days from Firestore (or local fill).
    /// Then you can split them into previous 7 vs. current 7 to compare.
    func fetchLast14DaysStats(completion: @escaping ([DailyStat]) -> Void) {
        FirestoreManager.shared.fetchLast14DaysStats { dailyStats in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            guard let fourteenDaysAgo = calendar.date(byAdding: .day, value: -13, to: today) else {
                completion(dailyStats)
                return
            }

            // Turn existing stats into a dict keyed by "yyyy-MM-dd"
            var fetchedDict: [String: DailyStat] = [:]
            for ds in dailyStats {
                fetchedDict[ds.id] = ds
            }

            var finalStats: [DailyStat] = []
            for dayOffset in 0...13 {
                if let date = calendar.date(byAdding: .day, value: dayOffset, to: fourteenDaysAgo) {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    let dateID = formatter.string(from: date)

                    if let existing = fetchedDict[dateID] {
                        finalStats.append(existing)
                    } else {
                        // Make a zero stat for missing days
                        let zeroStat = DailyStat(id: dateID, date: date, totalDuration: 0.0)
                        finalStats.append(zeroStat)
                    }
                }
            }

            // Sort finalStats by date ascending
            finalStats.sort { $0.date < $1.date }
            completion(finalStats)
        }
    }

    /// Compute average daily minutes from a list of DailyStat objects.
    /// totalDuration is in seconds, so we convert to minutes and divide by count.
    func averageDailyMinutes(for stats: [DailyStat]) -> Double {
        guard !stats.isEmpty else { return 0.0 }
        let totalSeconds = stats.reduce(0.0) { $0 + $1.totalDuration }
        let totalMinutes = totalSeconds / 60.0
        return totalMinutes / Double(stats.count)
    }

    /// Compute percentage change from oldValue to newValue (e.g., -20% means new is 20% lower).
    func computePercentageChange(from oldValue: Double, to newValue: Double) -> Double {
        guard oldValue != 0 else {
            // If old=0 => infinite or 100% "improvement"
            return (newValue == 0) ? 0 : 100
        }
        let diff = newValue - oldValue
        return (diff / oldValue) * 100.0
    }
}

// MARK: - StatsServiceProtocol Conformance

extension StatsManager: StatsServiceProtocol {
    // Protocol conformance is automatic since StatsManager already implements:
    // - func getTotalSessionDuration() -> TimeInterval
    // - func getSessionCount() -> Int
    // - func getAverageSessionDuration() -> TimeInterval
    // - func getLongestSessionDuration() -> TimeInterval
    // - func getMeditationStreak() -> Int
    // - func getLongestMeditationStreak() -> Int
}
