//
//  UserStorageProtocol.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-27
//

import Foundation

var SharedUserStorage: UserStorage {
    return UserStorage.shared
}

protocol StorageType {
    func save<T: Codable>(value: T, forKey key: String)
    func retrieve<T: Codable>(forKey key: String, as type: T.Type) -> T?
    func delete(forKey key: String)
}

// Singleton UserStorage class
class UserStorage {
    typealias Key = UserStorageKey
    static let shared = UserStorage()
    
    // Dictionary to hold multiple storage types
    private var storageTypes: [String: StorageType] = [:]
    private let queue = DispatchQueue(label: "com.yourapp.userstorage.queue") // Added for thread safety
    
    // Private initializer to prevent instantiation
    private init() {
        // Register default storage types (UserDefaults, Keychain)
        registerStorage(storage: UserDefaultsStorage(), for: .userDefaults)
        // Uncomment the following after KeychainStorage is implemented
        // registerStorage(storage: KeychainStorage(), for: .keychain)
    }
    
    // Function to register a new storage type with a name
    func registerStorage(storage: StorageType, for userStorageTypeKey: UserStorageTypeKey) {
        storageTypes[userStorageTypeKey.rawValue] = storage
    }
    
    // Save a value in a specified storage type
    func save<T: Codable>(value: T, forKey key: UserStorageKey, in userStorageTypeKey: UserStorageTypeKey = .userDefaults) {
        queue.sync {
            guard let storage = storageTypes[userStorageTypeKey.rawValue] else {
                print("Storage type not found!")
                return
            }
            storage.save(value: value, forKey: key.rawValue)
        }
    }
    
    // Retrieve a value from a specified storage type
    func retrieve<T: Codable>(forKey key: UserStorageKey, as type: T.Type, from userStorageTypeKey: UserStorageTypeKey = .userDefaults) -> T? {
        return queue.sync {
            guard let storage = storageTypes[userStorageTypeKey.rawValue] else {
                print("Storage type not found!")
                return nil
            }
            return storage.retrieve(forKey: key.rawValue, as: type)
        }
    }
    
    // Retrieve a value with a default value if key doesn't exist
    func retrieve<T: Codable>(forKey key: UserStorageKey, as type: T.Type, defaultValue: T, from userStorageTypeKey: UserStorageTypeKey = .userDefaults) -> T {
        return retrieve(forKey: key, as: type, from: userStorageTypeKey) ?? defaultValue
    }
    
    // Delete a value from a specified storage type
    func delete(forKey key: UserStorageKey, from userStorageTypeKey: UserStorageTypeKey = .userDefaults) {
        queue.sync {
            guard let storage = storageTypes[userStorageTypeKey.rawValue] else {
                print("Storage type not found!")
                return
            }
            storage.delete(forKey: key.rawValue)
        }
    }
}

enum UserStorageTypeKey: String, CaseIterable {
    case userDefaults
    case keychain
}

enum UserStorageKey: String, CaseIterable {
    case onboardingCompleted
    case appVersion
    case isUserSubscribed
    case userName
    case userProfileImageURL
    case lastFetchTime
    case audioFilesKey
    case lastUsedEmail
    case completedPractices
    case lastRecommendation
    case lastRecommendationTime
    case cumulativeMeditationTime
    case lastMeditationDate
    case meditationStreak
    case longestMeditationStreak
    case sessionCount
    case totalSessionDuration
    case longestSessionDuration
    case hasRequestedHealthKitAuthorization
    case pendingPushNotificationLink
    case pathVersion
    case pathStepsCache
    case onboardingAnswers
    case onboardingRecommendedPractice
    case onboardingCompletionTime
    case timerSettings
    case userPassword
    case firstOpenTracked
    case isAuthenticated
    case isGuest
    case pendingPathStepId
    case previousGuestId
    case migrationInProgress
    case wasSubscribedBeforeMigration
    case accountSource
    case emailVerificationBypassAllowed
    case authenticationMethod
    case hasTrackedInstall
    case hasTrackedReinstall
    case lastTrackedBuildNumber
    case firstInstallDate
    case firstSeenDate
    case installMethod
    case installSource
    case installAppVersion
    case aiChatHistory
    case aiChatKeyboardExpanded
    case onboardingResponses
    case hasCreatedFirstAIMeditation
    case hasSeenFirstMeditationSubscription
    case hasCompletedFirstSession        // Bool - true after first session_complete
    // Feature flags
    case devModeEnabled
    case useDevServer  // Bool - when true, app uses dev Firebase project (Cloud Functions + Storage)
    case hrMonitoringEnabled
    case aiPendingPostSessionMessage
    case userProfile
    // Unified user preferences (consolidates onboarding choices for personalization)
    case userPreferences
    // History feature
    case sessionHistory
    // Migration flags
    case keychainMigrated
    // Journey phase tracking (Daily Routines)
    case lastAutoSuggestedSlot          // String like "2026-01-14_morning"
    case completedRoutineSessionsCount  // Int counter for customization unlock
    case hasShownFirstWelcome           // Bool - true after the first-ever recommendation welcome is shown
    case hasReceivedFirstCustomMeditation  // Bool - true after first Custom from dual recommendation
    case contextStateSnapshot           // ContextStateSnapshot - Adaptive Context Evolution Layer state
    case cachedJourneyPhase             // Persisted phase to survive app restart race condition
    case loggedPhaseEntries             // [String] array of phase rawValues that have had entry logged
    case loggedSessionMilestones        // [Int] array of session numbers (1, 2, 3) that have had milestone logged
    case loggedFirstSessionStarted      // Bool - true after journey_first_session_started event fired once
    // DEPRECATED: Use loggedPhaseEntries instead
    case hasLoggedInitialPhaseEntry     // Bool - tracks if we've logged the initial phase entry event
    
    // Onboarding (current keys)
    case onboardingStartedAt             // String ISO8601 timestamp
    case onboardingCompletedAt           // String ISO8601 timestamp
    case onboardingCurrentStep           // Int step index
    // Note: onboardingResponses key already exists above (line 134)
    case onboardingVariantId             // String variant identifier
    
    // Onboarding 2026 (legacy keys - kept for migration, will be removed in future release)
    // DEPRECATED: Use onboardingStartedAt instead
    case onboarding2026StartedAt
    // DEPRECATED: Use onboardingCompletedAt instead
    case onboarding2026CompletedAt
    // DEPRECATED: Use onboardingCurrentStep instead
    case onboarding2026CurrentStep
    // DEPRECATED: Use onboardingResponses instead
    case onboarding2026Responses
    // DEPRECATED: Use onboardingVariantId instead
    case onboarding2026VariantId
    
    // Subscription 2026 (legacy keys - kept for migration)
    case subscription2026CompletedAt     // String ISO8601 timestamp (legacy)
    case subscription2026DidSubscribe    // Bool whether user subscribed (legacy)
    
    // Subscription (current keys)
    case subscriptionCompletedAt         // String ISO8601 timestamp
    case subscriptionDidSubscribe        // Bool whether user subscribed
    
    // Heart rate session counter (local mirror of Mixpanel total_hr_sessions for event enrichment)
    case totalHRSessions                 // Int counter

    // Fitbit BLE pairing
    case fitbitDeviceUUID                // String — CBPeripheral identifier UUID
    case fitbitDeviceName                // String — human-readable device name for Settings UI

    // Identity stitching
    case installDistinctId               // String — anonymous UID at first install, cleared after alias is created

    // Last active HR source — primary hint for next session's "waiting" message.
    // Values: "watch" | "airpods" | "fitbit"
    case lastHRSource

    // AppsFlyer subscription event deduplication.
    // Tracks the last observed RevenueCat periodType ("trial", "intro", "normal").
    // Used to detect trial→paid conversion so af_subscribe fires exactly once.
    case lastKnownPeriodType

    // Narration voice for custom meditations (dev mode). Values: "Asaf" | "Dan"
    case narrationVoiceId
}
