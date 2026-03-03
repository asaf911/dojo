//
//  MockSubscriptionService.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation
import Combine

#if DEBUG
/// Mock subscription service for SwiftUI Previews and testing.
/// Provides configurable subscription state without RevenueCat dependency.
final class MockSubscriptionService: SubscriptionServiceProtocol {
    private let _isUserSubscribed: CurrentValueSubject<Bool, Never>
    
    var isUserSubscribed: Bool {
        _isUserSubscribed.value
    }
    
    var isUserSubscribedPublisher: AnyPublisher<Bool, Never> {
        _isUserSubscribed.eraseToAnyPublisher()
    }
    
    /// Creates a mock subscription service.
    /// - Parameter isSubscribed: Whether the mock user is subscribed. Defaults to true for previews.
    init(isSubscribed: Bool = true) {
        _isUserSubscribed = CurrentValueSubject(isSubscribed)
    }
    
    func refreshSubscriptionStatus() {
        // No-op for previews
    }
    
    func resetSubscriptionStatusForGuest() {
        _isUserSubscribed.send(false)
    }
    
    /// Sets the subscription status (for testing).
    func setSubscribed(_ subscribed: Bool) {
        _isUserSubscribed.send(subscribed)
    }
}
#endif

