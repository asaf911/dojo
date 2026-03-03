import Foundation
import SwiftUI
import Combine
import FirebaseAuth

/// Global state manager for the app.
/// Responsible for determining which main view should be shown based on authentication status.
class AppState: ObservableObject {
    /// Shared instance for global access
    static let shared = AppState()
    
    /// Published property that determines if the user is authenticated.
    @Published var isAuthenticated: Bool = false
    
    /// Published property retained for backwards compatibility. Always false now that onboarding is deprecated.
    @Published var needsOnboarding: Bool = false
    
    /// Published property that determines if the user is currently a guest.
    @Published var isGuest: Bool = false
    
    /// Initialize with current authentication state from the system.
    init() {
        // Check if user is authenticated directly from Firebase Auth first
        if let currentUser = Auth.auth().currentUser {
            // User is logged in with Firebase, use this as source of truth
            self.isAuthenticated = true
            self.isGuest = false
            
            // Save these values to local storage for next app launch
            SharedUserStorage.save(value: true, forKey: .isAuthenticated)
            SharedUserStorage.save(value: false, forKey: .isGuest)
            
            self.needsOnboarding = false
            print("AppState: Initialized from Firebase Auth with user: \(currentUser.uid)")
        } else {
            // No authenticated Firebase user, fall back to local storage values
            self.isAuthenticated = SharedUserStorage.retrieve(forKey: .isAuthenticated, as: Bool.self) ?? false
            
            // Onboarding is deprecated; default to main experience
            self.needsOnboarding = false
            
            // Check if user is in guest mode
            self.isGuest = SharedUserStorage.retrieve(forKey: .isGuest, as: Bool.self) ?? false
        }
        
        print("🔑 IDENTITY_SYSTEM: AppState initialized - isAuthenticated=\(isAuthenticated), needsOnboarding=\(needsOnboarding), isGuest=\(isGuest)")
        print("🔑 IDENTITY_SYSTEM: AppState startup decision - onboarding flow deprecated; defaulting to main app when authenticated")
    }
    
    /// Sign out the user and update the state.
    func signOut() {
        print("🔑 IDENTITY_SYSTEM: AppState signing out user")
        self.isAuthenticated = false
        self.isGuest = false
        self.needsOnboarding = false
        
        // Clear authentication and guest state
        SharedUserStorage.save(value: false, forKey: .isAuthenticated)
        SharedUserStorage.save(value: false, forKey: .isGuest)
        
        // Clear user-specific stats to prevent data mixing between users
        // These will be re-synced from Firebase when the next user logs in
        clearUserStats()
        
        print("🔑 IDENTITY_SYSTEM: AppState cleared auth flags and user stats - user will see AuthenticationScreen on restart")
    }
    
    /// Clears user-specific stats from local storage.
    /// Called on sign out to prevent data mixing between different user accounts.
    /// Stats are re-synced from Firebase when a user logs in.
    private func clearUserStats() {
        print("🔑 IDENTITY_SYSTEM: Clearing user stats from local storage")
        
        // Clear session stats
        SharedUserStorage.delete(forKey: .sessionCount)
        SharedUserStorage.delete(forKey: .totalSessionDuration)
        SharedUserStorage.delete(forKey: .longestSessionDuration)
        
        // Clear streak stats
        SharedUserStorage.delete(forKey: .meditationStreak)
        SharedUserStorage.delete(forKey: .longestMeditationStreak)
        SharedUserStorage.delete(forKey: .lastMeditationDate)
        
        // Clear cumulative time
        SharedUserStorage.delete(forKey: .cumulativeMeditationTime)
        
        print("🔑 IDENTITY_SYSTEM: User stats cleared - will be re-synced from Firebase on next login")
    }
    
    /// Set the user as authenticated.
    func setAuthenticated(isGuest: Bool = false) {
        print("AppState: Setting user as authenticated, isGuest=\(isGuest)")
        self.isAuthenticated = true
        self.isGuest = isGuest
        SharedUserStorage.save(value: true, forKey: .isAuthenticated)
        SharedUserStorage.save(value: isGuest, forKey: .isGuest)
        
        self.needsOnboarding = false
        print("🔑 IDENTITY_SYSTEM: AppState - needsOnboarding pinned to false (onboarding deprecated)")
    }
    
    /// Mark onboarding as completed.
    func completeOnboarding() {
        print("AppState: completeOnboarding called - onboarding flow deprecated; no-op")
        self.needsOnboarding = false
    }
    
    /// Refresh onboarding state from storage (used when fresh user is created)
    func refreshOnboardingState() {
        let previousNeedsOnboarding = self.needsOnboarding
        self.needsOnboarding = false
        if previousNeedsOnboarding != self.needsOnboarding {
            print("🔑 IDENTITY_SYSTEM: AppState refreshed onboarding state - onboarding flow deprecated")
        }
    }
} 