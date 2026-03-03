//
//  AuthService.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation
import FirebaseAuth

/// Production authentication service wrapping Firebase Auth.
/// This provides a protocol-based abstraction over Firebase Auth for dependency injection.
final class AuthService: AuthServiceProtocol {
    static let shared = AuthService()
    
    private init() {}
    
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    var isAuthenticated: Bool {
        Auth.auth().currentUser != nil
    }
    
    var isAnonymous: Bool {
        Auth.auth().currentUser?.isAnonymous ?? false
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
}

