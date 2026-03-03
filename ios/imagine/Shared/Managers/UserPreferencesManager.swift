//
//  UserPreferencesManager.swift
//  imagine
//
//  Created by Cursor on 1/21/26.
//
//  Singleton manager for user preferences with local persistence and Firebase sync.
//  Provides a unified interface for accessing and updating user preferences
//  collected during onboarding and throughout the app lifecycle.
//
//  USAGE:
//  - Read: UserPreferencesManager.shared.preferences
//  - Update: UserPreferencesManager.shared.updateGoal(.relaxation)
//  - Generic: UserPreferencesManager.shared.update { $0.goal = "relaxation" }
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Mixpanel

// MARK: - UserPreferencesManager

final class UserPreferencesManager {
    
    // MARK: - Singleton
    
    static let shared = UserPreferencesManager()
    
    // MARK: - Properties
    
    /// Current user preferences (cached in memory, persisted to storage)
    private(set) var preferences: UserPreferences {
        didSet {
            persistLocally()
        }
    }
    
    /// Storage key for local persistence
    private let storageKey: UserStorageKey = .userPreferences
    
    /// Queue for thread-safe operations
    private let queue = DispatchQueue(label: "com.imagine.userpreferences.queue")
    
    /// Firestore reference
    private let db = Firestore.firestore()
    
    // MARK: - Initialization
    
    private init() {
        // Load preferences from storage, migrating legacy data if needed
        self.preferences = Self.loadAndMigrate()
        
        #if DEBUG
        print("🗂️ PREFS: ═══════════════════════════════════════════════════════")
        print("🗂️ PREFS: [INIT] UserPreferencesManager initialized")
        print("🗂️ PREFS: [INIT] goal=\(preferences.goal ?? "nil") | hurdle=\(preferences.hurdle ?? "nil")")
        print("🗂️ PREFS: [INIT] familiarity=\(preferences.familiarity ?? "nil") | healthKit=\(preferences.connectedHealthKit?.description ?? "nil")")
        print("🗂️ PREFS: [INIT] onboardingComplete=\(preferences.hasCompletedOnboarding) | schemaVersion=\(preferences.schemaVersion)")
        print("🗂️ PREFS: ═══════════════════════════════════════════════════════")
        #endif
    }
    
    // MARK: - Generic Update
    
    /// Generic update method - allows modifying any preference field
    /// Automatically sets updatedAt and persists changes
    ///
    /// Usage:
    /// ```
    /// UserPreferencesManager.shared.update { prefs in
    ///     prefs.goal = "relaxation"
    ///     prefs.familiarity = "brand_new"
    /// }
    /// ```
    func update(_ block: (inout UserPreferences) -> Void) {
        var changeDescription = ""
        
        queue.sync {
            var updated = preferences
            let oldPrefs = preferences
            block(&updated)
            updated.updatedAt = Date()
            preferences = updated
            
            // Build change description for logging
            #if DEBUG
            var changes: [String] = []
            if updated.goal != oldPrefs.goal { changes.append("goal=\(updated.goal ?? "nil")") }
            if updated.hurdle != oldPrefs.hurdle { changes.append("hurdle=\(updated.hurdle ?? "nil")") }
            if updated.familiarity != oldPrefs.familiarity { changes.append("familiarity=\(updated.familiarity ?? "nil")") }
            if updated.connectedHealthKit != oldPrefs.connectedHealthKit { changes.append("healthKit=\(updated.connectedHealthKit?.description ?? "nil")") }
            if updated.onboardingCompletedAt != oldPrefs.onboardingCompletedAt { changes.append("onboardingComplete=true") }
            changeDescription = changes.joined(separator: ", ")
            #endif
        }
        
        #if DEBUG
        if !changeDescription.isEmpty {
            print("🗂️ PREFS: [UPDATE] Batch: \(changeDescription)")
        }
        #endif
        
        // Sync to Firebase if authenticated (non-blocking)
        syncToFirebaseIfAuthenticated()
    }
    
    // MARK: - Convenience Update Methods
    
    /// Update the user's meditation goal
    func updateGoal(_ goal: OnboardingGoal?) {
        update { prefs in
            prefs.goal = goal?.rawValue
        }
        
        #if DEBUG
        print("🗂️ PREFS: [UPDATE] goal → \(goal?.rawValue ?? "nil")")
        #endif
    }
    
    /// Update the user's hurdle/obstacle
    func updateHurdle(_ hurdleId: String?) {
        update { prefs in
            prefs.hurdle = hurdleId
        }
        
        #if DEBUG
        print("🗂️ PREFS: [UPDATE] hurdle → \(hurdleId ?? "nil")")
        #endif
    }
    
    /// Update the user's meditation familiarity level
    func updateFamiliarity(_ familiarity: OnboardingFamiliarity?) {
        update { prefs in
            prefs.familiarity = familiarity?.rawValue
        }
        
        #if DEBUG
        print("🗂️ PREFS: [UPDATE] familiarity → \(familiarity?.rawValue ?? "nil")")
        #endif
    }
    
    /// Update whether user connected HealthKit
    func updateHealthKit(_ connected: Bool) {
        update { prefs in
            prefs.connectedHealthKit = connected
        }
        
        #if DEBUG
        print("🗂️ PREFS: [UPDATE] healthKit → \(connected)")
        #endif
    }
    
    /// Mark onboarding as complete
    func markOnboardingComplete() {
        update { prefs in
            prefs.onboardingCompletedAt = Date()
        }
        
        // Also update Mixpanel user profile for segmentation
        updateMixpanelProperties()
        
        #if DEBUG
        print("🗂️ PREFS: [UPDATE] ✅ Onboarding marked complete")
        #endif
    }
    
    // MARK: - Extension Data (Prototyping New Fields)
    
    /// Set an extension value for prototyping new preferences
    /// Use this to test new fields before formalizing them as properties
    func setExtensionValue(_ value: String?, forKey key: String) {
        update { prefs in
            if prefs.extensionData == nil {
                prefs.extensionData = [:]
            }
            prefs.extensionData?[key] = value
        }
        
        #if DEBUG
        print("🗂️ PREFS: [UPDATE] extensionData[\(key)] → \(value ?? "nil")")
        #endif
    }
    
    /// Get an extension value
    func getExtensionValue(forKey key: String) -> String? {
        return preferences.extensionData?[key]
    }
    
    // MARK: - Local Persistence
    
    /// Persist preferences to local storage
    private func persistLocally() {
        SharedUserStorage.save(value: preferences, forKey: storageKey)
        
        #if DEBUG
        print("🗂️ PREFS: [PERSIST] Saved to local storage")
        #endif
    }
    
    // MARK: - Firebase Sync
    
    /// Sync preferences to Firebase (authenticated users only)
    private func syncToFirebaseIfAuthenticated() {
        guard let userId = Auth.auth().currentUser?.uid,
              !Auth.auth().currentUser!.isAnonymous else {
            #if DEBUG
            print("🗂️ PREFS: [SYNC] ⏭️ Skipped - user not authenticated or anonymous")
            #endif
            return
        }
        
        syncToFirebase(userId: userId)
    }
    
    /// Push current preferences to Firebase
    func syncToFirebase(userId: String? = nil) {
        guard NetworkMonitor.shared.isConnected else {
            #if DEBUG
            print("🗂️ PREFS: [SYNC] ⏭️ Skipped - device offline")
            #endif
            return
        }
        
        guard let uid = userId ?? Auth.auth().currentUser?.uid else {
            #if DEBUG
            print("🗂️ PREFS: [SYNC] ⏭️ Skipped - no user ID")
            #endif
            return
        }
        
        #if DEBUG
        print("🗂️ PREFS: [SYNC] 📤 Pushing to Firebase for user: \(uid.prefix(8))...")
        #endif
        
        // Update syncedAt before pushing
        var syncingPrefs = preferences
        syncingPrefs.syncedAt = Date()
        
        let userRef = db.collection("users").document(uid)
        userRef.setData([
            "preferences": syncingPrefs.toFirestoreDictionary()
        ], merge: true) { [weak self] error in
            if let error = error {
                #if DEBUG
                print("🗂️ PREFS: [SYNC] ❌ Error: \(error.localizedDescription)")
                #endif
            } else {
                // Update local syncedAt on success (didSet will auto-persist)
                self?.queue.sync {
                    self?.preferences.syncedAt = syncingPrefs.syncedAt
                }
                
                #if DEBUG
                print("🗂️ PREFS: [SYNC] ✅ Successfully pushed to Firebase")
                #endif
            }
        }
    }
    
    /// Fetch preferences from Firebase (for new device scenario)
    func fetchFromFirebase(completion: ((Bool) -> Void)? = nil) {
        guard NetworkMonitor.shared.isConnected else {
            #if DEBUG
            print("🗂️ PREFS: [FETCH] ⏭️ Skipped - device offline")
            #endif
            completion?(false)
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            #if DEBUG
            print("🗂️ PREFS: [FETCH] ⏭️ Skipped - no user ID")
            #endif
            completion?(false)
            return
        }
        
        #if DEBUG
        print("🗂️ PREFS: [FETCH] 📥 Fetching from Firebase for user: \(userId.prefix(8))...")
        #endif
        
        let userRef = db.collection("users").document(userId)
        userRef.getDocument { [weak self] document, error in
            guard let self = self else {
                completion?(false)
                return
            }
            
            if let error = error {
                #if DEBUG
                print("🗂️ PREFS: [FETCH] ❌ Error: \(error.localizedDescription)")
                #endif
                completion?(false)
                return
            }
            
            guard let document = document,
                  document.exists,
                  let data = document.data(),
                  let prefsDict = data["preferences"] as? [String: Any],
                  let remotePrefs = UserPreferences(fromFirestore: prefsDict) else {
                #if DEBUG
                print("🗂️ PREFS: [FETCH] ℹ️ No preferences found in Firebase (new user or first sync)")
                #endif
                completion?(false)
                return
            }
            
            #if DEBUG
            print("🗂️ PREFS: [FETCH] ✅ Found remote preferences - goal=\(remotePrefs.goal ?? "nil"), hurdle=\(remotePrefs.hurdle ?? "nil")")
            #endif
            
            // Merge remote with local (remote wins if newer)
            self.mergeWithRemote(remotePrefs)
            completion?(true)
        }
    }
    
    /// Called after user authenticates - fetch from Firebase and merge
    func handleUserAuthenticated() {
        #if DEBUG
        print("🗂️ PREFS: ═══════════════════════════════════════════════════════")
        print("🗂️ PREFS: [AUTH] User authenticated - starting preferences sync")
        #endif
        
        fetchFromFirebase { [weak self] foundRemote in
            if foundRemote {
                #if DEBUG
                print("🗂️ PREFS: [AUTH] ✅ Merged with remote preferences")
                #endif
                // Update Mixpanel with potentially restored preferences
                self?.updateMixpanelProperties()
            } else {
                // No remote data - push local to Firebase
                #if DEBUG
                print("🗂️ PREFS: [AUTH] No remote data found - pushing local to Firebase")
                #endif
                self?.syncToFirebase()
            }
            #if DEBUG
            print("🗂️ PREFS: ═══════════════════════════════════════════════════════")
            #endif
        }
    }
    
    /// Merge remote preferences with local (conflict resolution)
    private func mergeWithRemote(_ remote: UserPreferences) {
        queue.sync {
            let localUpdatedAt = preferences.updatedAt ?? Date.distantPast
            let remoteUpdatedAt = remote.updatedAt ?? Date.distantPast
            
            #if DEBUG
            print("🗂️ PREFS: [MERGE] Comparing timestamps - local=\(localUpdatedAt), remote=\(remoteUpdatedAt)")
            #endif
            
            if remoteUpdatedAt > localUpdatedAt {
                // Remote is newer - use remote preferences
                var merged = remote
                merged.syncedAt = Date()
                preferences = merged
                
                #if DEBUG
                print("🗂️ PREFS: [MERGE] 🔄 Remote is newer → using remote preferences")
                print("🗂️ PREFS: [MERGE]   goal=\(remote.goal ?? "nil") | hurdle=\(remote.hurdle ?? "nil")")
                #endif
            } else {
                // Local is newer - keep local but mark as synced
                preferences.syncedAt = Date()
                
                #if DEBUG
                print("🗂️ PREFS: [MERGE] 🔄 Local is newer → keeping local, pushing to Firebase")
                #endif
                
                // Push local to Firebase to update remote
                syncToFirebase()
            }
        }
    }
    
    // MARK: - Mixpanel Integration
    
    /// Update Mixpanel user profile properties with current preferences
    func updateMixpanelProperties() {
        Mixpanel.mainInstance().people.set(properties: [
            "onboarding_goal": preferences.goal ?? "none",
            "onboarding_hurdle": preferences.hurdle ?? "none",
            "onboarding_familiarity": preferences.familiarity ?? "none",
            "hr_onboarding_result": (preferences.enabledHeartRate == true) ? "prompted" : "skipped",
            "mindful_minutes_onboarding_result": (preferences.connectedMindfulMinutes == true) ? "authorized" : "skipped",
            "preferences_version": "unified_v\(preferences.schemaVersion)"
        ])
        
        #if DEBUG
        print("🗂️ PREFS: [ANALYTICS] Updated Mixpanel user properties")
        #endif
    }
    
    // MARK: - Schema Migration
    
    /// Load preferences from storage and migrate if needed
    private static func loadAndMigrate() -> UserPreferences {
        // Try to load existing UserPreferences
        if var prefs = SharedUserStorage.retrieve(forKey: .userPreferences, as: UserPreferences.self) {
            // Check if schema migration is needed
            migrateSchemaIfNeeded(&prefs)
            return prefs
        }
        
        // Try to migrate from legacy OnboardingResponses
        if let migrated = migrateLegacyOnboardingResponses() {
            return migrated
        }
        
        // No existing data - return fresh preferences
        #if DEBUG
        print("🗂️ PREFS: [INIT] No existing data - creating fresh preferences")
        #endif
        return UserPreferences()
    }
    
    /// Migrate from legacy OnboardingResponses to UserPreferences
    private static func migrateLegacyOnboardingResponses() -> UserPreferences? {
        guard let legacy = SharedUserStorage.retrieve(forKey: .onboardingResponses, as: OnboardingResponses.self) else {
            return nil
        }
        
        #if DEBUG
        print("🗂️ PREFS: [MIGRATE] ═══════════════════════════════════════════════")
        print("🗂️ PREFS: [MIGRATE] Found legacy OnboardingResponses - migrating...")
        #endif
        
        var prefs = UserPreferences()
        prefs.goal = legacy.selectedGoal?.rawValue
        prefs.hurdle = legacy.selectedHurdle?.id
        prefs.familiarity = legacy.selectedFamiliarity?.rawValue
        prefs.connectedHealthKit = legacy.connectedHealthKit
        prefs.updatedAt = legacy.timestamp
        
        // Check if onboarding was completed (via OnboardingState)
        if let completedAtString = SharedUserStorage.retrieve(forKey: .onboardingCompletedAt, as: String.self),
           let completedAt = ISO8601DateFormatter().date(from: completedAtString) {
            prefs.onboardingCompletedAt = completedAt
        }
        
        // Save the migrated preferences
        SharedUserStorage.save(value: prefs, forKey: .userPreferences)
        
        #if DEBUG
        print("🗂️ PREFS: [MIGRATE] ✅ Migration complete:")
        print("🗂️ PREFS: [MIGRATE]   goal=\(prefs.goal ?? "nil") | hurdle=\(prefs.hurdle ?? "nil")")
        print("🗂️ PREFS: [MIGRATE]   familiarity=\(prefs.familiarity ?? "nil") | healthKit=\(prefs.connectedHealthKit?.description ?? "nil")")
        print("🗂️ PREFS: [MIGRATE] ═══════════════════════════════════════════════")
        #endif
        
        return prefs
    }
    
    /// Migrate schema if version is outdated
    private static func migrateSchemaIfNeeded(_ prefs: inout UserPreferences) {
        guard prefs.schemaVersion < UserPreferences.currentSchemaVersion else {
            return
        }
        
        #if DEBUG
        print("🗂️ PREFS: [MIGRATE] Schema upgrade: v\(prefs.schemaVersion) → v\(UserPreferences.currentSchemaVersion)")
        #endif
        
        // Future schema migrations go here
        // Example for v1 -> v2:
        // if prefs.schemaVersion < 2 {
        //     // Migrate extensionData to formal property
        //     if let length = prefs.extensionData?["preferredSessionLength"] {
        //         prefs.preferredSessionLength = Int(length)
        //         prefs.extensionData?.removeValue(forKey: "preferredSessionLength")
        //     }
        // }
        
        // Update to current schema version
        prefs.schemaVersion = UserPreferences.currentSchemaVersion
        
        // Persist the migrated preferences
        SharedUserStorage.save(value: prefs, forKey: .userPreferences)
    }
    
    // MARK: - Reset (for testing/dev mode)
    
    /// Reset all preferences (useful for testing)
    func reset() {
        #if DEBUG
        print("🗂️ PREFS: [RESET] ⚠️ Clearing all preferences")
        #endif
        
        queue.sync {
            preferences = UserPreferences()
        }
        SharedUserStorage.delete(forKey: storageKey)
        
        #if DEBUG
        print("🗂️ PREFS: [RESET] ✅ Preferences cleared")
        #endif
    }
}

// MARK: - Convenience Accessors

extension UserPreferencesManager {
    
    /// Quick access to goal enum
    var goal: OnboardingGoal? {
        preferences.goalEnum
    }
    
    /// Quick access to familiarity enum  
    var familiarity: OnboardingFamiliarity? {
        preferences.familiarityEnum
    }
    
    /// Quick access to hurdle ID
    var hurdle: String? {
        preferences.hurdle
    }
    
    /// Whether user is new to meditation
    var isNewToMeditation: Bool {
        preferences.isNewToMeditation
    }
    
    /// Whether onboarding has been completed
    var hasCompletedOnboarding: Bool {
        preferences.hasCompletedOnboarding
    }
}
