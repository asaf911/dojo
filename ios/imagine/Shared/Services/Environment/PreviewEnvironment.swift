//
//  PreviewEnvironment.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import SwiftUI

#if DEBUG

// MARK: - Preview Environment Modifier

extension View {
    /// Injects all mock services for SwiftUI Previews.
    /// This eliminates network calls, Firebase initialization, and other side effects during preview rendering.
    ///
    /// Example usage:
    /// ```swift
    /// #Preview {
    ///     ExploreView()
    ///         .withPreviewEnvironment()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - isSubscribed: Whether the mock user has an active subscription. Defaults to true.
    ///   - isAuthenticated: Whether the mock user is authenticated. Defaults to true.
    ///   - streak: The mock meditation streak. Defaults to 7.
    /// - Returns: A view with all mock services injected.
    func withPreviewEnvironment(
        isSubscribed: Bool = true,
        isAuthenticated: Bool = true,
        streak: Int = 7
    ) -> some View {
        self
            .environment(\.analyticsService, MockAnalyticsService())
            .environment(\.subscriptionService, MockSubscriptionService(isSubscribed: isSubscribed))
            .environment(\.authService, MockAuthService(isAuthenticated: isAuthenticated))
            .environment(\.dataService, MockDataService())
            .environment(\.healthService, MockHealthService())
            .environment(\.statsService, MockStatsService(streak: streak))
    }
    
    /// Injects mock services with a non-subscribed user state.
    /// Useful for previewing paywall and subscription flows.
    func withPreviewEnvironmentFreeUser() -> some View {
        withPreviewEnvironment(isSubscribed: false)
    }
    
    /// Injects mock services with an unauthenticated user state.
    /// Useful for previewing sign-in and sign-up flows.
    func withPreviewEnvironmentUnauthenticated() -> some View {
        withPreviewEnvironment(isSubscribed: false, isAuthenticated: false)
    }
}

// MARK: - Preview Container

/// A container view that provides mock environment objects for previews.
/// Use this when the view requires @EnvironmentObject in addition to @Environment.
struct PreviewContainer<Content: View>: View {
    let content: Content
    let isSubscribed: Bool
    let isAuthenticated: Bool
    
    @StateObject private var mockNavigationCoordinator = NavigationCoordinator()
    @StateObject private var mockAppState = AppState()
    @StateObject private var mockAudioPlayerManager = AudioPlayerManager()
    
    init(
        isSubscribed: Bool = true,
        isAuthenticated: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.isSubscribed = isSubscribed
        self.isAuthenticated = isAuthenticated
    }
    
    var body: some View {
        content
            .withPreviewEnvironment(isSubscribed: isSubscribed, isAuthenticated: isAuthenticated)
            .environmentObject(mockNavigationCoordinator)
            .environmentObject(mockAppState)
            .environmentObject(mockAudioPlayerManager)
            .environmentObject(SubscriptionManager.shared) // For views still using @EnvironmentObject
            .preferredColorScheme(.dark)
    }
}

#endif

