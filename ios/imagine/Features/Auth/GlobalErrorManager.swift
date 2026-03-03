//
//  GlobalErrorManager.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-12
//

import Foundation
import SwiftUI

// Updated AuthError so that each instance gets a unique id.
enum AuthError: LocalizedError, Identifiable {
    case custom(message: String, id: UUID = UUID())
    
    var id: UUID {
        switch self {
        case .custom(_, let id):
            return id
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .custom(let message, _):
            return message
        }
    }
}

// A singleton to drive global error alerts using our concrete AuthError type.
class GlobalErrorManager: ObservableObject {
    static let shared = GlobalErrorManager()
    
    @Published var error: AuthError? {
        didSet {
            print("GlobalErrorManager: error updated to: \(error?.localizedDescription ?? "nil") (isMainThread: \(Thread.isMainThread))")
        }
    }
    
    private init() {}
}
