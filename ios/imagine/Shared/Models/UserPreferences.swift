//
//  UserPreferences.swift
//  imagine
//
//  Created by Cursor on 1/21/26.
//
//  Unified user preferences model for personalization.
//  Stores onboarding choices and user settings with Firebase sync support.
//
//  EXTENSIBILITY:
//  - Schema versioning enables safe migrations
//  - Custom decoder ignores unknown keys (forward compatible)
//  - extensionData dictionary for rapid prototyping new fields
//

import Foundation
import FirebaseFirestore

// MARK: - UserPreferences Model

struct UserPreferences: Codable, Equatable {
    
    // MARK: - Schema Version
    // Increment when adding/changing fields that require migration
    static let currentSchemaVersion = 1
    var schemaVersion: Int = Self.currentSchemaVersion
    
    // MARK: - Core Onboarding Choices
    
    /// User's primary meditation goal (OnboardingGoal.rawValue)
    var goal: String?
    
    /// User's main obstacle/hurdle (HurdleOption.id)
    var hurdle: String?
    
    /// User's meditation experience level (OnboardingFamiliarity.rawValue)
    var familiarity: String?
    
    /// Whether user connected HealthKit during onboarding
    var connectedHealthKit: Bool?
    
    /// Whether user enabled Heart Rate tracking during onboarding ("prompted" or "skipped")
    var enabledHeartRate: Bool?
    
    /// Whether user connected Mindful Minutes during onboarding
    var connectedMindfulMinutes: Bool?
    
    // MARK: - Metadata
    
    /// When onboarding was completed
    var onboardingCompletedAt: Date?
    
    /// Last time preferences were updated locally
    var updatedAt: Date?
    
    /// Last time preferences were synced to/from Firebase
    var syncedAt: Date?
    
    // MARK: - Extension Data
    // Use this dictionary to prototype new preferences before formalizing them as properties.
    // Example: extensionData["preferredSessionLength"] = "10"
    // Once validated, promote to a formal property in a future schema version.
    var extensionData: [String: String]?
    
    // MARK: - Computed Helpers (Type-Safe Access)
    
    /// Type-safe access to goal enum
    var goalEnum: OnboardingGoal? {
        goal.flatMap { OnboardingGoal(rawValue: $0) }
    }
    
    /// Type-safe access to familiarity enum
    var familiarityEnum: OnboardingFamiliarity? {
        familiarity.flatMap { OnboardingFamiliarity(rawValue: $0) }
    }
    
    /// Whether user is brand new to meditation
    var isNewToMeditation: Bool {
        familiarityEnum == .brandNew
    }
    
    /// Whether user has completed onboarding
    var hasCompletedOnboarding: Bool {
        onboardingCompletedAt != nil
    }
    
    /// Whether preferences have any meaningful data
    var isEmpty: Bool {
        goal == nil && hurdle == nil && familiarity == nil && connectedHealthKit == nil && enabledHeartRate == nil && connectedMindfulMinutes == nil
    }
    
    // MARK: - Initialization
    
    /// Default initializer with empty preferences
    init() {
        self.schemaVersion = Self.currentSchemaVersion
        self.updatedAt = Date()
    }
    
    /// Full initializer for migration/testing
    init(
        schemaVersion: Int = currentSchemaVersion,
        goal: String? = nil,
        hurdle: String? = nil,
        familiarity: String? = nil,
        connectedHealthKit: Bool? = nil,
        enabledHeartRate: Bool? = nil,
        connectedMindfulMinutes: Bool? = nil,
        onboardingCompletedAt: Date? = nil,
        updatedAt: Date? = nil,
        syncedAt: Date? = nil,
        extensionData: [String: String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.goal = goal
        self.hurdle = hurdle
        self.familiarity = familiarity
        self.connectedHealthKit = connectedHealthKit
        self.enabledHeartRate = enabledHeartRate
        self.connectedMindfulMinutes = connectedMindfulMinutes
        self.onboardingCompletedAt = onboardingCompletedAt
        self.updatedAt = updatedAt ?? Date()
        self.syncedAt = syncedAt
        self.extensionData = extensionData
    }
    
    // MARK: - Custom Decoding
    // Uses decodeIfPresent for all fields to:
    // 1. Handle missing keys gracefully (backward compatible)
    // 2. Ignore unknown keys (forward compatible)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        goal = try container.decodeIfPresent(String.self, forKey: .goal)
        hurdle = try container.decodeIfPresent(String.self, forKey: .hurdle)
        familiarity = try container.decodeIfPresent(String.self, forKey: .familiarity)
        connectedHealthKit = try container.decodeIfPresent(Bool.self, forKey: .connectedHealthKit)
        enabledHeartRate = try container.decodeIfPresent(Bool.self, forKey: .enabledHeartRate)
        connectedMindfulMinutes = try container.decodeIfPresent(Bool.self, forKey: .connectedMindfulMinutes)
        onboardingCompletedAt = try container.decodeIfPresent(Date.self, forKey: .onboardingCompletedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        syncedAt = try container.decodeIfPresent(Date.self, forKey: .syncedAt)
        extensionData = try container.decodeIfPresent([String: String].self, forKey: .extensionData)
    }
    
    // MARK: - CodingKeys
    
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case goal
        case hurdle
        case familiarity
        case connectedHealthKit
        case enabledHeartRate
        case connectedMindfulMinutes
        case onboardingCompletedAt
        case updatedAt
        case syncedAt
        case extensionData
    }
}

// MARK: - Firebase Conversion

extension UserPreferences {
    
    /// Convert to dictionary for Firestore storage
    func toFirestoreDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "schemaVersion": schemaVersion
        ]
        
        if let goal = goal {
            dict["goal"] = goal
        }
        if let hurdle = hurdle {
            dict["hurdle"] = hurdle
        }
        if let familiarity = familiarity {
            dict["familiarity"] = familiarity
        }
        if let connectedHealthKit = connectedHealthKit {
            dict["connectedHealthKit"] = connectedHealthKit
        }
        if let enabledHeartRate = enabledHeartRate {
            dict["enabledHeartRate"] = enabledHeartRate
        }
        if let connectedMindfulMinutes = connectedMindfulMinutes {
            dict["connectedMindfulMinutes"] = connectedMindfulMinutes
        }
        if let onboardingCompletedAt = onboardingCompletedAt {
            dict["onboardingCompletedAt"] = onboardingCompletedAt
        }
        if let updatedAt = updatedAt {
            dict["updatedAt"] = updatedAt
        }
        if let syncedAt = syncedAt {
            dict["syncedAt"] = syncedAt
        }
        if let extensionData = extensionData, !extensionData.isEmpty {
            dict["extensionData"] = extensionData
        }
        
        return dict
    }
    
    /// Initialize from Firestore dictionary
    init?(fromFirestore dict: [String: Any]) {
        self.schemaVersion = dict["schemaVersion"] as? Int ?? 1
        self.goal = dict["goal"] as? String
        self.hurdle = dict["hurdle"] as? String
        self.familiarity = dict["familiarity"] as? String
        self.connectedHealthKit = dict["connectedHealthKit"] as? Bool
        self.enabledHeartRate = dict["enabledHeartRate"] as? Bool
        self.connectedMindfulMinutes = dict["connectedMindfulMinutes"] as? Bool
        
        // Handle Firestore Timestamp or Date
        self.onboardingCompletedAt = Self.dateFromFirestore(dict["onboardingCompletedAt"])
        self.updatedAt = Self.dateFromFirestore(dict["updatedAt"])
        self.syncedAt = Self.dateFromFirestore(dict["syncedAt"])
        
        self.extensionData = dict["extensionData"] as? [String: String]
    }
    
    /// Helper to convert Firestore value to Date
    private static func dateFromFirestore(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        } else if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        return nil
    }
}

// MARK: - Debug Description

extension UserPreferences: CustomDebugStringConvertible {
    var debugDescription: String {
        """
        UserPreferences(v\(schemaVersion)):
          goal: \(goal ?? "nil")
          hurdle: \(hurdle ?? "nil")
          familiarity: \(familiarity ?? "nil")
          healthKit: \(connectedHealthKit?.description ?? "nil")
          enabledHeartRate: \(enabledHeartRate?.description ?? "nil")
          connectedMindfulMinutes: \(connectedMindfulMinutes?.description ?? "nil")
          onboardingCompleted: \(onboardingCompletedAt?.description ?? "nil")
          updatedAt: \(updatedAt?.description ?? "nil")
          syncedAt: \(syncedAt?.description ?? "nil")
          extensionData: \(extensionData?.description ?? "nil")
        """
    }
}
