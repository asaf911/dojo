//
//  UserStorageImpl.swift
//  Created by Michael Tabachnik on 10/21/24.
//

import Foundation

// MARK: - UserDefaults Storage Implementation
class UserDefaultsStorage: StorageType {
    private let defaults = UserDefaults.standard

    func save<T: Codable>(value: T, forKey key: String) {
        // If T is Bool, save it natively.
        if let boolValue = value as? Bool {
            defaults.set(boolValue, forKey: key)
        } else {
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(value) {
                defaults.set(encoded, forKey: key)
            }
        }
    }

    func retrieve<T: Codable>(forKey key: String, as type: T.Type) -> T? {
        // If T is Bool, retrieve it natively.
        if type == Bool.self {
            // Note: defaults.bool(forKey:) returns false if the key doesn't exist.
            return defaults.bool(forKey: key) as? T
        }
        if let data = defaults.data(forKey: key) {
            let decoder = JSONDecoder()
            return try? decoder.decode(type, from: data)
        }
        return nil
    }

    func delete(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Keychain Storage (placeholder)
// Implement Keychain storage by conforming to the StorageType protocol
class KeychainStorage: StorageType {

    func save<T: Codable>(value: T, forKey key: String) {
        // Implement Keychain save logic
    }

    func retrieve<T: Codable>(forKey key: String, as type: T.Type) -> T? {
        // Implement Keychain retrieve logic
        return nil
    }

    func delete(forKey key: String) {
        // Implement Keychain delete logic
    }
}
