//
//  SubscriptionServiceProtocol.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import Foundation
import Combine

/// Protocol defining subscription service capabilities.
/// Implementations can wrap RevenueCat, StoreKit 2, or any other payment vendor.
protocol SubscriptionServiceProtocol: AnyObject {
    /// Whether the current user has an active subscription.
    var isUserSubscribed: Bool { get }
    
    /// Publisher for subscription status changes.
    var isUserSubscribedPublisher: AnyPublisher<Bool, Never> { get }
    
    /// Refreshes subscription status from the backend.
    func refreshSubscriptionStatus()
    
    /// Resets subscription status for guest users.
    func resetSubscriptionStatusForGuest()
}

