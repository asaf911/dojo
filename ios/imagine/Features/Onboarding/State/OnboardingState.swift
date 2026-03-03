//
//  OnboardingState.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Manages persistent onboarding state across sessions.
//  Tracks completion status, current step, and user responses.
//

import Foundation

// MARK: - Onboarding State

/// Singleton managing persistent onboarding state
final class OnboardingState {
    
    // MARK: - Singleton
    
    static let shared = OnboardingState()
    
    private init() {
        migrateFromLegacyKeysIfNeeded()
    }
    
    // MARK: - Migration
    
    /// Migrate from legacy onboarding2026* keys to new onboarding* keys
    /// This ensures existing users don't lose their onboarding state
    private func migrateFromLegacyKeysIfNeeded() {
        // Check if migration is needed (new key doesn't exist but legacy does)
        let hasNewCompletedKey = SharedUserStorage.retrieve(forKey: .onboardingCompletedAt, as: String.self) != nil
        let hasLegacyCompletedKey = SharedUserStorage.retrieve(forKey: .onboarding2026CompletedAt, as: String.self) != nil
        
        // Only migrate if we have legacy data but no new data
        guard !hasNewCompletedKey && hasLegacyCompletedKey else { return }
        
        #if DEBUG
        print("📋 ONBOARDING: [MIGRATE] Starting migration from legacy keys...")
        #endif
        
        // Migrate each key
        if let startedAt = SharedUserStorage.retrieve(forKey: .onboarding2026StartedAt, as: String.self) {
            SharedUserStorage.save(value: startedAt, forKey: .onboardingStartedAt)
        }
        
        if let completedAt = SharedUserStorage.retrieve(forKey: .onboarding2026CompletedAt, as: String.self) {
            SharedUserStorage.save(value: completedAt, forKey: .onboardingCompletedAt)
        }
        
        if let currentStep = SharedUserStorage.retrieve(forKey: .onboarding2026CurrentStep, as: Int.self) {
            SharedUserStorage.save(value: currentStep, forKey: .onboardingCurrentStep)
        }
        
        if let responses = SharedUserStorage.retrieve(forKey: .onboarding2026Responses, as: OnboardingResponses.self) {
            SharedUserStorage.save(value: responses, forKey: .onboardingResponses)
        }
        
        if let variantId = SharedUserStorage.retrieve(forKey: .onboarding2026VariantId, as: String.self) {
            SharedUserStorage.save(value: variantId, forKey: .onboardingVariantId)
        }
        
        // Delete legacy keys after successful migration
        SharedUserStorage.delete(forKey: .onboarding2026StartedAt)
        SharedUserStorage.delete(forKey: .onboarding2026CompletedAt)
        SharedUserStorage.delete(forKey: .onboarding2026CurrentStep)
        SharedUserStorage.delete(forKey: .onboarding2026Responses)
        SharedUserStorage.delete(forKey: .onboarding2026VariantId)
        
        #if DEBUG
        print("📋 ONBOARDING: [MIGRATE] Complete - legacy keys removed")
        #endif
    }
    
    // MARK: - Completion State
    
    /// Check if onboarding has been completed
    var isComplete: Bool {
        SharedUserStorage.retrieve(forKey: .onboardingCompletedAt, as: String.self) != nil
    }
    
    /// Get the completion timestamp
    var completedAt: Date? {
        guard let timestamp = SharedUserStorage.retrieve(forKey: .onboardingCompletedAt, as: String.self) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: timestamp)
    }
    
    /// Get the start timestamp
    var startedAt: Date? {
        guard let timestamp = SharedUserStorage.retrieve(forKey: .onboardingStartedAt, as: String.self) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: timestamp)
    }
    
    // MARK: - Current Step
    
    /// Get/set the current step index for resuming progress
    var currentStep: OnboardingStep? {
        get {
            guard let stepIndex = SharedUserStorage.retrieve(forKey: .onboardingCurrentStep, as: Int.self) else {
                return nil
            }
            return OnboardingStep(rawValue: stepIndex)
        }
        set {
            if let step = newValue {
                SharedUserStorage.save(value: step.rawValue, forKey: .onboardingCurrentStep)
            } else {
                SharedUserStorage.delete(forKey: .onboardingCurrentStep)
            }
        }
    }
    
    // MARK: - Responses
    
    /// Get/set user responses collected during onboarding
    var responses: OnboardingResponses {
        get {
            SharedUserStorage.retrieve(forKey: .onboardingResponses, as: OnboardingResponses.self)
                ?? OnboardingResponses()
        }
        set {
            SharedUserStorage.save(value: newValue, forKey: .onboardingResponses)
        }
    }
    
    // MARK: - Variant
    
    /// Get/set the A/B test variant ID
    var variantId: String? {
        get {
            SharedUserStorage.retrieve(forKey: .onboardingVariantId, as: String.self)
        }
        set {
            if let variant = newValue {
                SharedUserStorage.save(value: variant, forKey: .onboardingVariantId)
            } else {
                SharedUserStorage.delete(forKey: .onboardingVariantId)
            }
        }
    }
    
    // MARK: - Lifecycle Methods
    
    /// Mark onboarding as started with a variant ID
    func markStarted(variantId: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        SharedUserStorage.save(value: timestamp, forKey: .onboardingStartedAt)
        SharedUserStorage.save(value: variantId, forKey: .onboardingVariantId)
        
        #if DEBUG
        print("📋 ONBOARDING: [STARTED] variant=\(variantId) at \(timestamp)")
        #endif
    }
    
    /// Mark onboarding as completed
    func markCompleted() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        SharedUserStorage.save(value: timestamp, forKey: .onboardingCompletedAt)
        
        #if DEBUG
        print("📋 ONBOARDING: [COMPLETED] at \(timestamp)")
        #endif
    }
    
    /// Reset all onboarding state (for testing/dev mode)
    func reset() {
        #if DEBUG
        print("📋 ONBOARDING: [RESET] Clearing all state...")
        #endif
        
        SharedUserStorage.delete(forKey: .onboardingStartedAt)
        SharedUserStorage.delete(forKey: .onboardingCompletedAt)
        SharedUserStorage.delete(forKey: .onboardingCurrentStep)
        SharedUserStorage.delete(forKey: .onboardingResponses)
        SharedUserStorage.delete(forKey: .onboardingVariantId)
        
        #if DEBUG
        print("📋 ONBOARDING: [RESET] State cleared")
        #endif
    }
    
    /// Duration of onboarding (from start to completion)
    var duration: TimeInterval? {
        guard let start = startedAt, let end = completedAt else {
            return nil
        }
        return end.timeIntervalSince(start)
    }
}

// MARK: - Notification Names
// Note: .onboardingCompleted is defined in AppFunctions.swift
