import SwiftUI
import WatchConnectivity

/// Simple and reliable manager to check Apple Watch pairing status
class WatchPairingManager: ObservableObject {
    static let shared = WatchPairingManager()
    
    @Published var isWatchPaired: Bool = false
    
    private init() {
        checkWatchPairingStatus()
        setupNotificationObservers()
    }
    
    /// Check if an Apple Watch is paired with this iPhone
    private func checkWatchPairingStatus() {
        // Ensure WatchConnectivity is supported on this device
        guard WCSession.isSupported() else {
            print("WatchPairingManager: WatchConnectivity not supported on this device")
            DispatchQueue.main.async {
                self.isWatchPaired = false
            }
            return
        }
        
        // Check pairing status on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let paired = WCSession.default.isPaired
            
            DispatchQueue.main.async {
                self.isWatchPaired = paired
                print("WatchPairingManager: Apple Watch paired: \(paired)")
            }
        }
    }
    
    /// Setup observers to detect watch pairing/unpairing changes
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .NSExtensionHostDidBecomeActive, 
            object: nil, 
            queue: .main
        ) { _ in
            // Re-check pairing status when app becomes active
            self.checkWatchPairingStatus()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Re-check pairing status when app becomes active
            self.checkWatchPairingStatus()
        }
    }
    
    /// Force refresh of pairing status
    func refreshPairingStatus() {
        checkWatchPairingStatus()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 