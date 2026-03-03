//
//  MockAuthService.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

#if DEBUG
/// Mock authentication service for SwiftUI Previews and testing.
/// Provides configurable auth state without Firebase dependency.
final class MockAuthService: AuthServiceProtocol {
    private(set) var currentUserId: String?
    private(set) var isAuthenticated: Bool
    private(set) var isAnonymous: Bool
    
    /// Creates a mock auth service.
    /// - Parameters:
    ///   - isAuthenticated: Whether user is authenticated. Defaults to true for previews.
    ///   - isAnonymous: Whether user is anonymous/guest. Defaults to false.
    ///   - userId: Mock user ID. Defaults to "mock-user-id".
    init(isAuthenticated: Bool = true, isAnonymous: Bool = false, userId: String = "mock-user-id") {
        self.isAuthenticated = isAuthenticated
        self.isAnonymous = isAnonymous
        self.currentUserId = isAuthenticated ? userId : nil
    }
    
    func signOut() throws {
        isAuthenticated = false
        isAnonymous = false
        currentUserId = nil
    }
    
    /// Signs in the mock user (for testing).
    func mockSignIn(userId: String = "mock-user-id", isAnonymous: Bool = false) {
        self.currentUserId = userId
        self.isAuthenticated = true
        self.isAnonymous = isAnonymous
    }
}
#endif

