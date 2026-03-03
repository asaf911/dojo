//
//  AuthServiceProtocol.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation

/// Protocol defining authentication service capabilities.
/// Implementations can wrap Firebase Auth, Auth0, or any other auth vendor.
protocol AuthServiceProtocol {
    /// The current user's unique identifier, or nil if not authenticated.
    var currentUserId: String? { get }
    
    /// Whether the current user is authenticated (has a valid session).
    var isAuthenticated: Bool { get }
    
    /// Whether the current user is anonymous (guest mode).
    var isAnonymous: Bool { get }
    
    /// Signs out the current user.
    func signOut() throws
}

