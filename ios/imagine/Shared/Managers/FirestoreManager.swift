// FirestoreManager.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

class FirestoreManager {
    static let shared = FirestoreManager()
    private let db = Firestore.firestore()

    private init() {}

    private var storage: Storage { Config.activeStorage }

    // MARK: - User Data Functions

    /// Updates the user's timezone in Firestore.
    /// Skipped when offline to prevent errors.
    func updateUserTimezone() {
        guard NetworkMonitor.shared.isConnected else {
            logger.eventMessage("FirestoreManager: Skipping timezone update - device is offline")
            return
        }
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(userId)

        userRef.setData([
            "timezone": TimeZone.current.identifier
        ], merge: true) { error in
            if let error = error {
                logger.errorMessage("Error updating timezone: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Timezone updated successfully.")
            }
        }
    }

    /// Updates the user's subscription data in Firestore.
    /// - Parameter data: A dictionary containing subscription details.
    /// Skipped when offline to prevent errors.
    func updateSubscriptionData(_ data: [String: Any]) {
        guard NetworkMonitor.shared.isConnected else {
            logger.eventMessage("FirestoreManager: Skipping subscription data update - device is offline")
            return
        }
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(userId)

        userRef.setData([
            "subscription": data
        ], merge: true) { error in
            if let error = error {
                logger.errorMessage("Error updating subscription data: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Subscription data updated successfully.")
            }
        }
    }

    /// Updates the user's last active date in Firestore.
    /// Skipped when offline to prevent errors.
    func updateLastActiveDate() {
        guard NetworkMonitor.shared.isConnected else {
            logger.eventMessage("FirestoreManager: Skipping last active date update - device is offline")
            return
        }
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(userId)

        userRef.setData([
            "lastActiveDate": Timestamp(date: Date())
        ], merge: true) { error in
            if let error = error {
                logger.errorMessage("Error updating last active date: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Last active date updated successfully.")
            }
        }
    }

    /// Updates the user's hashed email in Firestore.
    /// - Parameter hashedEmail: The hashed version of the user's email.
    func updateHashedEmail(hashedEmail: String) {
        guard let userId = Auth.auth().currentUser?.uid else {
            logger.eventMessage("No user is logged in.")
            return
        }
        let userRef = db.collection("users").document(userId)
        userRef.setData([
            "hashedEmail": hashedEmail
        ], merge: true) { error in
            if let error = error {
                logger.errorMessage("Error updating hashed email: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Hashed email updated successfully.")
            }
        }
    }

    // MARK: - Practice Completion Functions

    /// Marks a practice as completed in Firestore under the user's `practices` subcollection.
    /// - Parameters:
    ///   - practiceId: The ID of the practice to mark as completed.
    ///   - completion: A closure that returns `true` if the update was successful, else `false`.
    func updatePracticeCompletion(_ practiceId: String, completion: @escaping (Bool) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        let practiceRef = db.collection("users").document(userId).collection("practices").document(practiceId)

        practiceRef.setData([
            "completed": true,
            "completionDate": Timestamp(date: Date())
        ], merge: true) { error in
            if let error = error {
                logger.errorMessage("Error updating practice completion: \(error.localizedDescription)")
                completion(false)
            } else {
                logger.eventMessage("Practice completion updated successfully.")
                completion(true)
            }
        }
    }

    // MARK: - Meditation Streak

    /// Updates the meditation streak in Firestore.
    func updateMeditationStreak(_ streak: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(uid)
        userRef.updateData(["meditationStreak": streak]) { error in
            if let error = error {
                logger.eventMessage("Error updating meditation streak: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Meditation streak successfully updated in Firestore.")
            }
        }
    }

    /// Fetches the meditation streak from Firestore.
    func fetchMeditationStreak(completion: @escaping (Int) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(0)
            return
        }
        let userRef = db.collection("users").document(uid)
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                if let streak = document.data()?["meditationStreak"] as? Int {
                    completion(streak)
                } else {
                    completion(0)
                }
            } else {
                logger.eventMessage("Meditation streak document does not exist")
                completion(0)
            }
        }
    }

    /// Updates the longest meditation streak in Firestore.
    func updateLongestMeditationStreak(_ longestStreak: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(uid)
        userRef.updateData(["longestMeditationStreak": longestStreak]) { error in
            if let error = error {
                logger.eventMessage("Error updating longest meditation streak: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Longest meditation streak successfully updated in Firestore.")
            }
        }
    }

    /// Fetches the longest meditation streak from Firestore.
    func fetchLongestMeditationStreak(completion: @escaping (Int) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(0)
            return
        }
        let userRef = db.collection("users").document(uid)
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                if let longestStreak = document.data()?["longestMeditationStreak"] as? Int {
                    completion(longestStreak)
                } else {
                    completion(0)
                }
            } else {
                logger.eventMessage("Longest meditation streak document does not exist")
                completion(0)
            }
        }
    }
    
    /// Updates the last meditation date in Firestore.
    func updateLastMeditationDate(_ date: Date) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(uid)
        userRef.updateData(["lastMeditationDate": Timestamp(date: date)]) { error in
            if let error = error {
                logger.eventMessage("Error updating last meditation date: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Last meditation date successfully updated in Firestore.")
            }
        }
    }

    // MARK: - Learning Sequence

    /// Updates the learning sequence in Firestore with only completed 'learn' category practices.
    func updateLearningSequence(_ sequenceData: [String: Any]) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(userId)

        // Ensure that 'completedPractices' is an array of strings
        guard let completedPractices = sequenceData["completedPractices"] as? [String] else {
            logger.eventMessage("Invalid sequence data provided.")
            return
        }

        userRef.setData([
            "learningSequence": completedPractices
        ], merge: true) { error in
            if let error = error {
                logger.errorMessage("Error updating learning sequence: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Learning sequence updated successfully.")
            }
        }
    }

    // MARK: - Cumulative Meditation Time

    /// Updates the user's cumulative meditation time in Firestore.
    /// - Parameter totalTime: The total meditation time to update.
    func updateCumulativeMeditationTime(_ totalTime: Double) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(userId)

        userRef.setData([
            "cumulativeMeditationTime": totalTime
        ], merge: true) { error in
            if let error = error {
                logger.errorMessage("Error updating cumulative meditation time: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Cumulative meditation time updated successfully in Firestore.")
            }
        }
    }

    /// Fetches the user's cumulative meditation time from Firestore.
    /// - Parameter completion: A closure that returns the cumulative meditation time.
    func fetchCumulativeMeditationTime(completion: @escaping (Double) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(0.0)
            return
        }
        let userRef = db.collection("users").document(userId)
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                let data = document.data()
                let totalTime = data?["cumulativeMeditationTime"] as? Double ?? 0.0
                completion(totalTime)
            } else {
                logger.errorMessage("Error fetching cumulative meditation time: \(error?.localizedDescription ?? "Unknown error")")
                completion(0.0)
            }
        }
    }

    // MARK: - Session Metrics

    /// Updates the session count in Firestore.
    func updateSessionCount(_ count: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(uid)
        userRef.updateData(["sessionCount": count]) { error in
            if let error = error {
                logger.eventMessage("Error updating session count: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Session count successfully updated in Firestore.")
            }
        }
    }

    /// Fetches the session count from Firestore.
    func fetchSessionCount(completion: @escaping (Int) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(0)
            return
        }
        let userRef = db.collection("users").document(uid)
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                if let count = document.data()?["sessionCount"] as? Int {
                    completion(count)
                } else {
                    completion(0)
                }
            } else {
                logger.eventMessage("Session count document does not exist")
                completion(0)
            }
        }
    }

    /// Updates the total session duration in Firestore.
    func updateTotalSessionDuration(_ duration: Double) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(uid)
        userRef.updateData(["totalSessionDuration": duration]) { error in
            if let error = error {
                logger.eventMessage("Error updating total session duration: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Total session duration successfully updated in Firestore.")
            }
        }
    }

    /// Fetches the total session duration from Firestore.
    func fetchTotalSessionDuration(completion: @escaping (Double) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(0.0)
            return
        }
        let userRef = db.collection("users").document(uid)
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                if let duration = document.data()?["totalSessionDuration"] as? Double {
                    completion(duration)
                } else {
                    completion(0.0)
                }
            } else {
                logger.eventMessage("Total session duration document does not exist")
                completion(0.0)
            }
        }
    }

    /// Updates the longest session duration in Firestore.
    func updateLongestSessionDuration(_ duration: Double) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(uid)
        userRef.updateData(["longestSessionDuration": duration]) { error in
            if let error = error {
                logger.eventMessage("Error updating longest session duration: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Longest session duration successfully updated in Firestore.")
            }
        }
    }

    /// Fetches the longest session duration from Firestore.
    func fetchLongestSessionDuration(completion: @escaping (Double) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(0.0)
            return
        }
        let userRef = db.collection("users").document(uid)
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                if let duration = document.data()?["longestSessionDuration"] as? Double {
                    completion(duration)
                } else {
                    completion(0.0)
                }
            } else {
                logger.eventMessage("Longest session duration document does not exist")
                completion(0.0)
            }
        }
    }

    /// Checks if a user has completed the onboarding process based on Firestore data
    /// - Parameters:
    ///   - userID: The ID of the user to check
    ///   - completion: A closure that returns true if onboarding is completed, false otherwise
    func checkUserHasCompletedOnboarding(userID: String, completion: @escaping (Bool) -> Void) {
        logger.eventMessage("Onboarding flow deprecated - skipping Firestore check for user \(userID)")
        completion(true)
    }

    /// Updates the onboarding completion status in Firestore
    /// - Parameter completion: Optional completion handler that returns true if the update was successful
    func updateOnboardingCompleted(completion: ((Bool) -> Void)? = nil) {
        logger.eventMessage("Onboarding flow deprecated - skipping Firestore onboarding update")
        completion?(true)
    }

    /// Resets the onboarding flags in Firestore for the current user (testing/use via ClearCache)
    func resetOnboardingForCurrentUser(completion: ((Bool) -> Void)? = nil) {
        logger.eventMessage("Onboarding flow deprecated - skipping Firestore onboarding reset")
        completion?(true)
    }

    // MARK: - Daily Stats Functions

    /// Updates the user's daily meditation stats in Firestore.
    /// - Parameters:
    ///   - duration: The duration to add to the day's total meditation time.
    func updateDailyStats(with duration: TimeInterval) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        // Use the user's local time zone
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current // Use the user's local time zone
        let dateString = dateFormatter.string(from: Date())

        let dailyStatsRef = db.collection("users").document(userId).collection("dailyStats").document(dateString)

        // Use the start of the day in the user's local time zone
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current // Use the user's local time zone
        let todayStartLocal = calendar.startOfDay(for: Date())

        dailyStatsRef.setData([
            "date": Timestamp(date: todayStartLocal),
            "totalDuration": FieldValue.increment(duration)
        ], merge: true) { error in
            if let error = error {
                logger.errorMessage("Error updating daily stats: \(error.localizedDescription)")
            } else {
                logger.eventMessage("Daily stats successfully updated in Firestore for dateString: \(dateString)")
            }
        }
    }

    /// Fetches the user's meditation stats for the last 7 days, ensuring all days are represented.
    /// - Parameter completion: A closure that returns an array of `DailyStat`.
    func fetchLast7DaysStats(completion: @escaping ([DailyStat]) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion([])
            return
        }

        let dailyStatsRef = db.collection("users").document(userId).collection("dailyStats")

        // Use the user's local time zone
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current // Use the user's local time zone

        let today = calendar.startOfDay(for: Date())
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today) else {
            completion([])
            return
        }

        let query = dailyStatsRef
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: sevenDaysAgo))
            .order(by: "date", descending: false)

        query.getDocuments { (snapshot, error) in
            if let error = error {
                logger.errorMessage("Error fetching daily stats: \(error.localizedDescription)")
                completion([])
                return
            }

            var fetchedStats: [DailyStat] = []
            snapshot?.documents.forEach { document in
                if let stat = DailyStat(dictionary: document.data(), id: document.documentID) {
                    fetchedStats.append(stat)
                }
            }

            // Generate last 7 days stats, ensuring all days are represented
            var last7DaysStats: [DailyStat] = []
            for dayOffset in 0...6 {
                if let date = calendar.date(byAdding: .day, value: -6 + dayOffset, to: today) {
                    let dateString = self.dateToString(date)
                    if let existingStat = fetchedStats.first(where: { $0.id == dateString }) {
                        last7DaysStats.append(existingStat)
                    } else {
                        // Create a default DailyStat with zero duration
                        let defaultStat = DailyStat(id: dateString, date: date, totalDuration: 0.0)
                        last7DaysStats.append(defaultStat)
                    }
                }
            }

            completion(last7DaysStats)
        }
    }

    func fetchLast14DaysStats(completion: @escaping ([DailyStat]) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion([])
            return
        }

        let dailyStatsRef = db.collection("users").document(userId).collection("dailyStats")

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let fourteenDaysAgo = calendar.date(byAdding: .day, value: -13, to: today) else {
            completion([])
            return
        }

        let query = dailyStatsRef
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: fourteenDaysAgo))
            .order(by: "date", descending: false)

        query.getDocuments { (snapshot, error) in
            if let error = error {
                logger.errorMessage("Error fetching daily stats: \(error.localizedDescription)")
                completion([])
                return
            }

            var fetchedStats: [DailyStat] = []
            snapshot?.documents.forEach { document in
                if let stat = DailyStat(dictionary: document.data(), id: document.documentID) {
                    fetchedStats.append(stat)
                }
            }

            completion(fetchedStats)
        }
    }

    /// Helper function to convert Date to string in 'yyyy-MM-dd' format.
    private func dateToString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // Ensure UTC
        return formatter.string(from: date)
    }
    
    // MARK: - Path Steps Functions
    
    /// Fetches the path steps data from Firebase Storage
    /// - Parameter completion: A closure that returns the PathStepsResponse if successful, nil otherwise
    func fetchPathSteps(completion: @escaping (PathStepsResponse?) -> Void) {
        print("[Server][Path] fetchPathSteps: start server=\(Config.serverLabel)")
        let pathRef = storage.reference(forURL: Config.storagePathPrefix + Config.activeServerPath + "Path/pathSteps.json")
        
        // Check if we have cached data and version
        if let cachedVersion = SharedUserStorage.retrieve(forKey: .pathVersion, as: Int.self),
           let cachedSteps = SharedUserStorage.retrieve(forKey: .pathStepsCache, as: PathStepsResponse.self) {
            
            // First return cached data
            completion(cachedSteps)
            
            // Then check if we need to update by fetching the latest version
            pathRef.getData(maxSize: 1 * 1024 * 1024) { data, error in
                if let error = error {
                    logger.errorMessage("Error checking path version: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    logger.errorMessage("No data received for path version check")
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(PathStepsResponse.self, from: data)
                    
                    guard response.version > cachedVersion else {
                        logger.eventMessage("Path content is up to date (v\(cachedVersion))")
                        return // No need to update
                    }
                    
                    logger.eventMessage("New path version found (v\(response.version)), updating cache")
                    print("[Server][Path] fetchPathSteps: success server=\(Config.serverLabel) version=\(response.version) (from version check)")
                    // Version is newer, cache and return the new data
                    SharedUserStorage.save(value: response.version, forKey: .pathVersion)
                    SharedUserStorage.save(value: response, forKey: .pathStepsCache)
                    completion(response)
                } catch {
                    logger.errorMessage("Error decoding path version: \(error.localizedDescription)")
                }
            }
        } else {
            // No cache exists, fetch fresh data
            fetchAndCachePathSteps(pathRef: pathRef, completion: completion)
        }
    }
    
    private func fetchAndCachePathSteps(pathRef: StorageReference, completion: @escaping (PathStepsResponse?) -> Void) {
        pathRef.getData(maxSize: 1 * 1024 * 1024) { data, error in
            if let error = error {
                logger.errorMessage("Error fetching path steps: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                logger.errorMessage("No data received for path steps")
                completion(nil)
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(PathStepsResponse.self, from: data)
                print("[Server][Path] fetchPathSteps: success server=\(Config.serverLabel) version=\(response.version)")
                // Cache the new data
                SharedUserStorage.save(value: response.version, forKey: .pathVersion)
                SharedUserStorage.save(value: response, forKey: .pathStepsCache)
                
                completion(response)
            } catch {
                logger.errorMessage("Error decoding path steps: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    /// Migrates guest user data to a registered user account
    /// - Parameters:
    ///   - to: The user ID to migrate data to
    ///   - cumulativeMeditationTime: The cumulative meditation time to migrate
    ///   - meditationStreak: The meditation streak to migrate
    ///   - sessionCount: The session count to migrate
    ///   - completion: A closure that returns true if the migration was successful
    func migrateGuestData(to userId: String, cumulativeMeditationTime: Double, meditationStreak: Int, sessionCount: Int, completion: @escaping (Bool) -> Void) {
        let userRef = db.collection("users").document(userId)
        
        // Create migration data with timestamps
        let migrationData: [String: Any] = [
            "cumulativeMeditationTime": cumulativeMeditationTime,
            "meditationStreak": meditationStreak,
            "sessionCount": sessionCount,
            "migrationDate": Timestamp(date: Date()),
            "migratedFromGuest": true,
            "lastActiveDate": Timestamp(date: Date())
        ]
        
        // Update user document with migration data
        userRef.setData(migrationData, merge: true) { error in
            if let error = error {
                logger.errorMessage("Error migrating guest data: \(error.localizedDescription)")
                completion(false)
            } else {
                logger.eventMessage("Guest data successfully migrated to user \(userId)")
                completion(true)
            }
        }
    }
}

// MARK: - DataServiceProtocol Conformance

extension FirestoreManager: DataServiceProtocol {
    // Protocol conformance is automatic since FirestoreManager already implements:
    // - func updateSubscriptionData(_ data: [String: Any])
    // - func fetchLast7DaysStats(completion: @escaping ([DailyStat]) -> Void)
    // - func updateDailyStats(with duration: TimeInterval)
    // - func updateMeditationStreak(_ streak: Int)
    // - func fetchMeditationStreak(completion: @escaping (Int) -> Void)
    // - func updateLongestMeditationStreak(_ longestStreak: Int)
    // - func fetchLongestMeditationStreak(completion: @escaping (Int) -> Void)
    // - func updateCumulativeMeditationTime(_ totalTime: Double)
    // - func fetchCumulativeMeditationTime(completion: @escaping (Double) -> Void)
    // - func updateSessionCount(_ count: Int)
    // - func fetchSessionCount(completion: @escaping (Int) -> Void)
}
