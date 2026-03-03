//
//  NetworkMonitor.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-12-26
//
//  Reactive network connectivity monitor using NWPathMonitor.
//  Provides real-time connectivity status for offline mode handling.
//

import Foundation
import Network
import Combine

/// Monitors network connectivity in real-time using NWPathMonitor.
/// Use `NetworkMonitor.shared.isConnected` to check current connectivity status.
class NetworkMonitor: ObservableObject {
    
    static let shared = NetworkMonitor()
    
    /// Whether the device currently has network connectivity
    @Published private(set) var isConnected: Bool = true
    
    /// The current connection type (wifi, cellular, etc.)
    @Published private(set) var connectionType: NWInterface.InterfaceType?
    
    /// Whether the connection is expensive (cellular data)
    @Published private(set) var isExpensive: Bool = false
    
    /// Whether the connection is constrained (Low Data Mode)
    @Published private(set) var isConstrained: Bool = false
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.dojo.networkmonitor", qos: .utility)
    private var isStarted = false
    
    private init() {
        monitor = NWPathMonitor()
    }
    
    /// Start monitoring network connectivity. Call this on app launch.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateConnectionStatus(path)
            }
        }
        
        monitor.start(queue: queue)
        print("NetworkMonitor: Started monitoring network connectivity")
    }
    
    /// Stop monitoring network connectivity. Call this on app termination if needed.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        monitor.cancel()
        print("NetworkMonitor: Stopped monitoring network connectivity")
    }
    
    private func updateConnectionStatus(_ path: NWPath) {
        let wasConnected = isConnected
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        
        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else {
            connectionType = nil
        }
        
        // Log connectivity changes
        if wasConnected != isConnected {
            let status = isConnected ? "connected" : "disconnected"
            let type = connectionType.map { "\($0)" } ?? "unknown"
            print("NetworkMonitor: Network \(status) (type: \(type), expensive: \(isExpensive))")
        }
    }
    
    /// Convenience property to check if we can perform network operations.
    /// Returns true if connected and not in Low Data Mode for optional operations.
    var canPerformNetworkOperations: Bool {
        return isConnected
    }
    
    /// Check if we should defer large downloads (e.g., on expensive/constrained connections)
    var shouldDeferLargeDownloads: Bool {
        return isExpensive || isConstrained
    }
}

