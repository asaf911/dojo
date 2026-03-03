import Foundation
import SwiftUI
import Combine

/// Global state manager for the app.
/// Responsible for determining which main view should be shown based on authentication status.
class AppState: ObservableObject {
    /// Published property that determines if the user is authenticated.
    @Published var isAuthenticated: Bool = false
    
    /// Published property retained for compatibility. Always false now that onboarding is deprecated.
    @Published var needsOnboarding: Bool = false
    
    /// Published property that determines if the user is currently a guest.
    @Published var isGuest: Bool = false
    
    /// Initialize with current authentication state from the system.
    init() {
        // Check if user is authenticated from Firebase Auth
        self.isAuthenticated = SharedUserStorage.retrieve(forKey: .isAuthenticated, as: Bool.self) ?? false
        
        // Onboarding flow deprecated; always default to main experience
        self.needsOnboarding = false
        
        // Check if user is in guest mode
        self.isGuest = SharedUserStorage.retrieve(forKey: .isGuest, as: Bool.self) ?? false
        
        print("🔑 IDENTITY_SYSTEM: AppState (Common) initialized - isAuthenticated=\(isAuthenticated), needsOnboarding=\(needsOnboarding), isGuest=\(isGuest)")
        print("🔑 IDENTITY_SYSTEM: AppState (Common) startup decision - onboarding flow deprecated; defaulting to main app when authenticated")
    }
    
    /// Sign out the user and update the state.
    func signOut() {
        print("🔑 IDENTITY_SYSTEM: AppState (Common) signing out user")
        self.isAuthenticated = false
        self.isGuest = false
        self.needsOnboarding = false
        
        // Clear authentication and guest state
        SharedUserStorage.save(value: false, forKey: .isAuthenticated)
        SharedUserStorage.save(value: false, forKey: .isGuest)
        
        // Clear user-specific stats to prevent data mixing between users
        // These will be re-synced from Firebase when the next user logs in
        clearUserStats()
        
        print("🔑 IDENTITY_SYSTEM: AppState (Common) cleared auth flags and user stats - user will see AuthenticationScreen on restart")
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
        print("🔑 IDENTITY_SYSTEM: AppState (Common) setting user as authenticated, isGuest=\(isGuest)")
        self.isAuthenticated = true
        self.isGuest = isGuest
        SharedUserStorage.save(value: true, forKey: .isAuthenticated)
        SharedUserStorage.save(value: isGuest, forKey: .isGuest)
        
        self.needsOnboarding = false
        print("🔑 IDENTITY_SYSTEM: AppState (Common) - needsOnboarding pinned to false (onboarding deprecated)")
    }
    
    /// Mark onboarding as completed.
    func completeOnboarding() {
        print("🔑 IDENTITY_SYSTEM: AppState (Common) completeOnboarding called - onboarding deprecated; no-op")
        self.needsOnboarding = false
    }
    
    /// Refresh onboarding state from storage (used when fresh user is created)
    func refreshOnboardingState() {
        let previousNeedsOnboarding = self.needsOnboarding
        self.needsOnboarding = false
        if previousNeedsOnboarding != self.needsOnboarding {
            print("🔑 IDENTITY_SYSTEM: AppState (Common) refreshed onboarding state - onboarding flow deprecated")
        }
    }
} 