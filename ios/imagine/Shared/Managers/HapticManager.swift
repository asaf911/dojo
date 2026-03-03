//
//  HapticManager.swift
//  Dojo
//
//  Created for centralized haptic feedback management.
//  Pre-warms generators to avoid Core Haptics initialization timeouts.
//

import UIKit

/// Centralized manager for haptic feedback.
/// Pre-warms generators on a background thread to avoid blocking the main thread
/// and prevents Core Haptics "Server timeout" errors in debug environment.
final class HapticManager {
    
    // MARK: - Singleton
    
    static let shared = HapticManager()
    
    // MARK: - Private Properties
    
    private var lightGenerator: UIImpactFeedbackGenerator?
    private var mediumGenerator: UIImpactFeedbackGenerator?
    private var heavyGenerator: UIImpactFeedbackGenerator?
    private var softGenerator: UIImpactFeedbackGenerator?
    private var rigidGenerator: UIImpactFeedbackGenerator?
    
    private var isReady = false
    private let queue = DispatchQueue(label: "com.dojo.haptics", qos: .utility)
    
    // MARK: - Initialization
    
    private init() {
        prepareGenerators()
    }
    
    // MARK: - Private Methods
    
    private func prepareGenerators() {
        queue.async { [weak self] in
            // Create all generators on background thread
            self?.lightGenerator = UIImpactFeedbackGenerator(style: .light)
            self?.mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
            self?.heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
            self?.softGenerator = UIImpactFeedbackGenerator(style: .soft)
            self?.rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
            
            // Pre-warm all generators
            self?.lightGenerator?.prepare()
            self?.mediumGenerator?.prepare()
            self?.heavyGenerator?.prepare()
            self?.softGenerator?.prepare()
            self?.rigidGenerator?.prepare()
            
            DispatchQueue.main.async {
                self?.isReady = true
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Triggers haptic feedback with the specified style.
    /// - Parameter style: The feedback style (.light, .medium, .heavy, .soft, .rigid)
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isReady else { return }
        
        DispatchQueue.main.async { [weak self] in
            switch style {
            case .light:
                self?.lightGenerator?.impactOccurred()
            case .medium:
                self?.mediumGenerator?.impactOccurred()
            case .heavy:
                self?.heavyGenerator?.impactOccurred()
            case .soft:
                self?.softGenerator?.impactOccurred()
            case .rigid:
                self?.rigidGenerator?.impactOccurred()
            @unknown default:
                break
            }
        }
    }
}

