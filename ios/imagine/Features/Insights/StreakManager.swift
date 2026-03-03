import Foundation
import Combine
import FirebaseAuth

/// Manages meditation streaks with proper timing and state tracking
/// Addresses the issue where new record detection fails due to timing of updates
class StreakManager: ObservableObject {
    static let shared = StreakManager()
    
    // MARK: - Published Properties
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var longestStreak: Int = 0
    @Published private(set) var lastMeditationDate: Date?
    
    // MARK: - Streak State for Post Practice Display
    struct StreakDisplayData {
        let currentStreak: Int
        let longestStreak: Int
        let isNewRecord: Bool
        let previousLongestStreak: Int
    }
    
    private var pendingStreakDisplayData: StreakDisplayData?
    
    private init() {
        loadStreakData()
        // Ensure existing users don't lose their data
        performMigrationIfNeeded()
    }
    
    // MARK: - Public Interface
    
    /// Gets current streak data for display (uses cached data if available)
    func getStreakDisplayData() -> StreakDisplayData {
        if let pending = pendingStreakDisplayData {
            // Clear the pending data after returning it
            pendingStreakDisplayData = nil
            return pending
        }
        
        // Return current data with no new record
        return StreakDisplayData(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            isNewRecord: false,
            previousLongestStreak: longestStreak
        )
    }
    
    /// Updates streak when a meditation session completes
    /// Returns the display data that should be shown in PostPracticeView
    func updateStreakOnSessionCompletion() -> StreakDisplayData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Capture previous state BEFORE any updates
        let previousCurrentStreak = currentStreak
        let previousLongestStreak = longestStreak
        let previousLastDate = lastMeditationDate
        
        logger.debugMessage("StreakManager: Before update - current: \(previousCurrentStreak), longest: \(previousLongestStreak), lastDate: \(String(describing: previousLastDate))", function: #function, line: #line, file: #file)
        
        var newCurrentStreak = previousCurrentStreak
        
        if let lastDate = previousLastDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            let dayDifference = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            
            if dayDifference == 0 {
                // Already meditated today
                if previousCurrentStreak == 0 {
                    // Data corruption fix: streak is 0 but we have a meditation date for today
                    // This means the streak was incorrectly reset - fix it to at least 1
                    newCurrentStreak = 1
                    logger.debugMessage("StreakManager: Data fix - streak was 0 but meditated today, setting to 1", function: #function, line: #line, file: #file)
                } else {
                    // Normal case: already meditated today, keep current streak
                    logger.debugMessage("StreakManager: Already meditated today, no streak change", function: #function, line: #line, file: #file)
                }
            } else if dayDifference == 1 {
                // Consecutive day - increment streak (minimum 1 if coming from 0)
                newCurrentStreak = max(1, previousCurrentStreak) + 1
                logger.debugMessage("StreakManager: Consecutive day detected, incrementing streak to \(newCurrentStreak)", function: #function, line: #line, file: #file)
            } else {
                // Gap in meditation - reset to 1
                newCurrentStreak = 1
                logger.debugMessage("StreakManager: Gap detected (\(dayDifference) days), resetting streak to 1", function: #function, line: #line, file: #file)
            }
        } else {
            // First time meditating
            newCurrentStreak = 1
            logger.debugMessage("StreakManager: First meditation detected, setting streak to 1", function: #function, line: #line, file: #file)
        }
        
        // Determine if this is a new record
        let isNewRecord = newCurrentStreak > previousLongestStreak
        let newLongestStreak = isNewRecord ? newCurrentStreak : previousLongestStreak
        
        // Update internal state
        currentStreak = newCurrentStreak
        longestStreak = newLongestStreak
        lastMeditationDate = today
        
        // Save to storage
        saveStreakData()
        
        // Update Firestore
        FirestoreManager.shared.updateMeditationStreak(newCurrentStreak)
        if isNewRecord {
            FirestoreManager.shared.updateLongestMeditationStreak(newLongestStreak)
            logger.debugMessage("StreakManager: New record achieved! Updated longest streak to \(newLongestStreak)", function: #function, line: #line, file: #file)
        }
        
        // Create display data for PostPracticeView
        let displayData = StreakDisplayData(
            currentStreak: newCurrentStreak,
            longestStreak: newLongestStreak,
            isNewRecord: isNewRecord,
            previousLongestStreak: previousLongestStreak
        )
        
        // Cache this for PostPracticeView to pick up
        pendingStreakDisplayData = displayData
        
        // Post notifications
        NotificationCenter.default.post(name: .didUpdateMeditationStreak, object: nil)
        if isNewRecord {
            NotificationCenter.default.post(name: .didUpdateLongestMeditationStreak, object: nil)
        }
        
        logger.debugMessage("StreakManager: After update - current: \(newCurrentStreak), longest: \(newLongestStreak), isNewRecord: \(isNewRecord)", function: #function, line: #line, file: #file)
        
        return displayData
    }
    
    /// Resets streak if needed when app launches (for missed days)
    func resetStreakIfNeededOnAppLaunch() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        guard let lastDate = lastMeditationDate else {
            // Never meditated before, nothing to reset
            return
        }
        
        let lastDay = calendar.startOfDay(for: lastDate)
        let dayDifference = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        
        // If it's been 2+ days since last meditation, reset streak to 0
        if dayDifference >= 2 {
            let previousStreak = currentStreak
            currentStreak = 0
            saveStreakData()
            
            FirestoreManager.shared.updateMeditationStreak(0)
            NotificationCenter.default.post(name: .didUpdateMeditationStreak, object: nil)
            
            logger.debugMessage("StreakManager: Streak reset from \(previousStreak) to 0 (dayDifference = \(dayDifference))", function: #function, line: #line, file: #file)
        }
    }
    
    /// Syncs streak data from Firestore (preserves existing user data)
    /// Uses MAX of local vs Firestore values to prevent data loss from stale/zero Firestore data
    func syncFromFirestore(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        
        // Capture local values BEFORE sync to prevent data loss
        let localCurrentStreak = self.currentStreak
        let localLongestStreak = self.longestStreak
        
        var firestoreCurrentStreak = 0
        var firestoreLongestStreak = 0
        
        group.enter()
        FirestoreManager.shared.fetchMeditationStreak { streak in
            firestoreCurrentStreak = streak
            group.leave()
        }
        
        group.enter()
        FirestoreManager.shared.fetchLongestMeditationStreak { longestStreak in
            firestoreLongestStreak = longestStreak
            group.leave()
        }
        
        group.notify(queue: .main) {
            // Use MAX of local vs Firestore to prevent data loss from zeros/stale data
            self.currentStreak = max(localCurrentStreak, firestoreCurrentStreak)
            self.longestStreak = max(localLongestStreak, firestoreLongestStreak)
            
            self.saveStreakData()
            
            // If local was higher, push it back to Firestore to sync
            if localCurrentStreak > firestoreCurrentStreak {
                FirestoreManager.shared.updateMeditationStreak(self.currentStreak)
                logger.debugMessage("StreakManager: Pushed higher local currentStreak (\(self.currentStreak)) to Firestore", function: #function, line: #line, file: #file)
            }
            if localLongestStreak > firestoreLongestStreak {
                FirestoreManager.shared.updateLongestMeditationStreak(self.longestStreak)
                logger.debugMessage("StreakManager: Pushed higher local longestStreak (\(self.longestStreak)) to Firestore", function: #function, line: #line, file: #file)
            }
            
            logger.debugMessage("StreakManager: Synced from Firestore - current: \(self.currentStreak) (local: \(localCurrentStreak), firestore: \(firestoreCurrentStreak)), longest: \(self.longestStreak) (local: \(localLongestStreak), firestore: \(firestoreLongestStreak))", function: #function, line: #line, file: #file)
            
            completion(true)
        }
    }
    
    /// Reloads streak data from local storage (called after Firebase sync updates local storage)
    func reloadFromLocalStorage() {
        loadStreakData()
        logger.debugMessage("StreakManager: Reloaded from local storage - current: \(currentStreak), longest: \(longestStreak)", function: #function, line: #line, file: #file)
    }
    
    // MARK: - Private Methods
    
    private func loadStreakData() {
        currentStreak = SharedUserStorage.retrieve(forKey: .meditationStreak, as: Int.self) ?? 0
        longestStreak = SharedUserStorage.retrieve(forKey: .longestMeditationStreak, as: Int.self) ?? 0
        lastMeditationDate = SharedUserStorage.retrieve(forKey: .lastMeditationDate, as: Date.self)
        
        logger.debugMessage("StreakManager: Loaded streak data - current: \(currentStreak), longest: \(longestStreak), lastDate: \(String(describing: lastMeditationDate))", function: #function, line: #line, file: #file)
        
        // Data repair: if streak is 0 but we have a recent lastMeditationDate, fix it
        repairCorruptedStreakIfNeeded()
    }
    
    /// Repairs corrupted streak data where streak is 0 but lastMeditationDate is recent
    private func repairCorruptedStreakIfNeeded() {
        guard currentStreak == 0, let lastDate = lastMeditationDate else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: lastDate)
        let dayDifference = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        
        // If we meditated today or yesterday but streak is 0, that's corrupted data
        if dayDifference <= 1 {
            let repairedStreak = 1  // At minimum, if you meditated recently, streak should be 1
            logger.debugMessage("StreakManager: DATA REPAIR - streak was 0 but lastMeditationDate is \(dayDifference) days ago. Setting streak to \(repairedStreak)", function: #function, line: #line, file: #file)
            
            currentStreak = repairedStreak
            saveStreakData()
            
            // Also push to Firestore
            FirestoreManager.shared.updateMeditationStreak(repairedStreak)
        }
    }
    
    private func saveStreakData() {
        SharedUserStorage.save(value: currentStreak, forKey: .meditationStreak)
        SharedUserStorage.save(value: longestStreak, forKey: .longestMeditationStreak)
        
        if let lastDate = lastMeditationDate {
            SharedUserStorage.save(value: lastDate, forKey: .lastMeditationDate)
        }
        
        logger.debugMessage("StreakManager: Saved streak data - current: \(currentStreak), longest: \(longestStreak)", function: #function, line: #line, file: #file)
    }
    
    // MARK: - Backward Compatibility
    
    /// Gets current streak (for backward compatibility with existing code)
    func getMeditationStreak() -> Int {
        return currentStreak
    }
    
    /// Gets longest streak (for backward compatibility with existing code)
    func getLongestMeditationStreak() -> Int {
        return longestStreak
    }
    
    // MARK: - Migration Support
    
    private static let firebaseMigrationKeyPrefix = "StreakManager_FirebaseMigration_v1_"
    
    /// Gets a user-specific migration key
    private func getFirebaseMigrationKey() -> String {
        let uid = Auth.auth().currentUser?.uid ?? "unknown"
        return "\(StreakManager.firebaseMigrationKeyPrefix)\(uid)"
    }
    
    /// One-time migration: Push local streak data to Firebase.
    /// This preserves existing user data and makes Firebase the source of truth.
    /// - longestStreak: Uses MAX(local, firebase) - only ever increases
    /// - currentStreak: If firebase=0 and local>0, use local (never synced before)
    /// - lastMeditationDate: Push to Firebase if not already there
    func migrateToFirebaseIfNeeded(completion: @escaping (Bool) -> Void) {
        let migrationKey = getFirebaseMigrationKey()
        let migrationCompleted = UserDefaults.standard.bool(forKey: migrationKey)
        
        if migrationCompleted {
            logger.debugMessage("StreakManager: Firebase migration already completed for this user. Skipping.", function: #function, line: #line, file: #file)
            completion(true)
            return
        }
        
        logger.debugMessage("StreakManager: Starting one-time Firebase migration...", function: #function, line: #line, file: #file)
        
        // Capture local values (what the user currently sees)
        let localCurrentStreak = self.currentStreak
        let localLongestStreak = self.longestStreak
        let localLastMeditationDate = self.lastMeditationDate
        
        logger.debugMessage("StreakManager: Local values - current: \(localCurrentStreak), longest: \(localLongestStreak), lastDate: \(String(describing: localLastMeditationDate))", function: #function, line: #line, file: #file)
        
        // Fetch Firebase values
        let group = DispatchGroup()
        var firebaseCurrentStreak = 0
        var firebaseLongestStreak = 0
        
        group.enter()
        FirestoreManager.shared.fetchMeditationStreak { streak in
            firebaseCurrentStreak = streak
            group.leave()
        }
        
        group.enter()
        FirestoreManager.shared.fetchLongestMeditationStreak { longest in
            firebaseLongestStreak = longest
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            logger.debugMessage("StreakManager: Firebase values - current: \(firebaseCurrentStreak), longest: \(firebaseLongestStreak)", function: #function, line: #line, file: #file)
            
            // longestStreak: Always use MAX (monotonically increasing)
            let finalLongestStreak = max(localLongestStreak, firebaseLongestStreak)
            
            // currentStreak: Special handling
            // - If Firebase has data (>0), trust Firebase (it's been syncing)
            // - If Firebase is 0 but local has data, user never synced - use local
            let finalCurrentStreak: Int
            if firebaseCurrentStreak > 0 {
                // Firebase has data - it's the source of truth
                // But also consider local if higher (edge case where local got ahead)
                finalCurrentStreak = max(localCurrentStreak, firebaseCurrentStreak)
            } else if localCurrentStreak > 0 {
                // Firebase is 0 but local has data - user never synced before
                finalCurrentStreak = localCurrentStreak
            } else {
                // Both are 0
                finalCurrentStreak = 0
            }
            
            // Push merged values to Firebase
            if finalLongestStreak > firebaseLongestStreak {
                FirestoreManager.shared.updateLongestMeditationStreak(finalLongestStreak)
                logger.debugMessage("StreakManager Migration: Pushed longestStreak \(finalLongestStreak) to Firebase (was \(firebaseLongestStreak))", function: #function, line: #line, file: #file)
            }
            
            if finalCurrentStreak != firebaseCurrentStreak {
                FirestoreManager.shared.updateMeditationStreak(finalCurrentStreak)
                logger.debugMessage("StreakManager Migration: Pushed currentStreak \(finalCurrentStreak) to Firebase (was \(firebaseCurrentStreak))", function: #function, line: #line, file: #file)
            }
            
            // Push lastMeditationDate if we have one locally
            if let localDate = localLastMeditationDate {
                FirestoreManager.shared.updateLastMeditationDate(localDate)
                logger.debugMessage("StreakManager Migration: Pushed lastMeditationDate to Firebase", function: #function, line: #line, file: #file)
            }
            
            // Update local values
            self.currentStreak = finalCurrentStreak
            self.longestStreak = finalLongestStreak
            self.saveStreakData()
            
            // Mark migration as complete for this user
            UserDefaults.standard.set(true, forKey: migrationKey)
            
            logger.debugMessage("StreakManager Migration complete - current: \(finalCurrentStreak), longest: \(finalLongestStreak)", function: #function, line: #line, file: #file)
            
            completion(true)
        }
    }
    
    /// Ensures existing users don't lose their streak data when upgrading to StreakManager
    private func performMigrationIfNeeded() {
        let migrationKey = "StreakManager_Migration_v1_Completed"
        let migrationCompleted = UserDefaults.standard.bool(forKey: migrationKey)
        
        if !migrationCompleted {
            logger.debugMessage("StreakManager: Performing migration for existing users", function: #function, line: #line, file: #file)
            
            // Verify that our loaded data matches what's in SharedUserStorage directly
            let directCurrentStreak = SharedUserStorage.retrieve(forKey: .meditationStreak, as: Int.self) ?? 0
            let directLongestStreak = SharedUserStorage.retrieve(forKey: .longestMeditationStreak, as: Int.self) ?? 0
            let directLastDate = SharedUserStorage.retrieve(forKey: .lastMeditationDate, as: Date.self)
            
            if directCurrentStreak != currentStreak || directLongestStreak != longestStreak {
                logger.debugMessage("StreakManager: Migration - updating streak data. Current: \(directCurrentStreak), Longest: \(directLongestStreak)", function: #function, line: #line, file: #file)
                
                currentStreak = directCurrentStreak
                longestStreak = directLongestStreak
                lastMeditationDate = directLastDate
                
                // Re-save to ensure consistency
                saveStreakData()
            }
            
            UserDefaults.standard.set(true, forKey: migrationKey)
            logger.debugMessage("StreakManager: Migration completed successfully", function: #function, line: #line, file: #file)
        }
    }
    
    // MARK: - Debugging Support
    
    /// Logs detailed streak state for debugging purposes
    func logStreakDiagnostics(context: String = "") {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var daysSinceLastMeditation = "N/A"
        if let lastDate = lastMeditationDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            let difference = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            daysSinceLastMeditation = "\(difference)"
        }
        
        logger.debugMessage("""
        StreakManager Diagnostics [\(context)]:
        - Current Streak: \(currentStreak)
        - Longest Streak: \(longestStreak)
        - Last Meditation Date: \(String(describing: lastMeditationDate))
        - Days Since Last Meditation: \(daysSinceLastMeditation)
        - Pending Display Data: \(pendingStreakDisplayData != nil ? "Yes" : "No")
        """, function: #function, line: #line, file: #file)
    }
} 