//
//  SubscriptionState.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Manages persistent subscription flow state.
//  Tracks completion status and whether user subscribed.
//

import Foundation

// MARK: - Subscription State

/// Singleton managing persistent subscription flow state
final class SubscriptionState {
    
    // MARK: - Singleton
    
    static let shared = SubscriptionState()
    
    private init() {
        // Migrate from old storage keys if needed
        migrateFromLegacyKeys()
    }
    
    // MARK: - Migration
    
    /// Migrate from legacy subscription2026 keys to new subscription keys
    private func migrateFromLegacyKeys() {
        // Check if old keys exist and new keys don't
        let hasLegacyCompletedAt = SharedUserStorage.retrieve(forKey: .subscription2026CompletedAt, as: String.self) != nil
        let hasNewCompletedAt = SharedUserStorage.retrieve(forKey: .subscriptionCompletedAt, as: String.self) != nil
        
        // Only migrate if legacy keys exist and new keys don't
        if hasLegacyCompletedAt && !hasNewCompletedAt {
            #if DEBUG
            print("💳 SUBSCRIPTION: [MIGRATE] Starting migration from legacy keys...")
            #endif
            
            // Migrate completedAt
            if let legacyTimestamp = SharedUserStorage.retrieve(forKey: .subscription2026CompletedAt, as: String.self) {
                SharedUserStorage.save(value: legacyTimestamp, forKey: .subscriptionCompletedAt)
            }
            
            // Migrate didSubscribe
            if let legacyDidSubscribe = SharedUserStorage.retrieve(forKey: .subscription2026DidSubscribe, as: Bool.self) {
                SharedUserStorage.save(value: legacyDidSubscribe, forKey: .subscriptionDidSubscribe)
            }
            
            // Clean up legacy keys
            SharedUserStorage.delete(forKey: .subscription2026CompletedAt)
            SharedUserStorage.delete(forKey: .subscription2026DidSubscribe)
            
            #if DEBUG
            print("💳 SUBSCRIPTION: [MIGRATE] Complete - legacy keys removed")
            #endif
        }
    }
    
    // MARK: - Completion State
    
    /// Check if subscription phase has been completed (regardless of subscription status)
    var isComplete: Bool {
        SharedUserStorage.retrieve(forKey: .subscriptionCompletedAt, as: String.self) != nil
    }
    
    /// Get the completion timestamp
    var completedAt: Date? {
        guard let timestamp = SharedUserStorage.retrieve(forKey: .subscriptionCompletedAt, as: String.self) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: timestamp)
    }
    
    /// Whether the user subscribed during this flow
    var didSubscribe: Bool {
        SharedUserStorage.retrieve(forKey: .subscriptionDidSubscribe, as: Bool.self) ?? false
    }
    
    // MARK: - Lifecycle Methods
    
    /// Mark subscription phase as completed
    /// - Parameter didSubscribe: Whether the user subscribed
    func markCompleted(didSubscribe: Bool) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        SharedUserStorage.save(value: timestamp, forKey: .subscriptionCompletedAt)
        SharedUserStorage.save(value: didSubscribe, forKey: .subscriptionDidSubscribe)
        
        #if DEBUG
        print("💳 SUBSCRIPTION: [COMPLETED] subscribed=\(didSubscribe) at \(timestamp)")
        #endif
    }
    
    /// Reset subscription phase state (for testing/dev mode)
    func reset() {
        #if DEBUG
        print("💳 SUBSCRIPTION: [RESET] Clearing all state...")
        #endif
        
        SharedUserStorage.delete(forKey: .subscriptionCompletedAt)
        SharedUserStorage.delete(forKey: .subscriptionDidSubscribe)
        // Also clean up any remaining legacy keys
        SharedUserStorage.delete(forKey: .subscription2026CompletedAt)
        SharedUserStorage.delete(forKey: .subscription2026DidSubscribe)
        
        #if DEBUG
        print("💳 SUBSCRIPTION: [RESET] State cleared")
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when subscription phase is completed
    /// userInfo contains "subscribed": Bool
    static let subscriptionCompleted = Notification.Name("subscriptionCompleted")
}
