//
//  ServiceEnvironmentKeys.swift
//  Dojo
//
//  Created for DI Foundation Migration
//

import SwiftUI

// MARK: - Analytics Service

private struct AnalyticsServiceKey: EnvironmentKey {
    static let defaultValue: any AnalyticsServiceProtocol = AnalyticsManager.shared
}

extension EnvironmentValues {
    var analyticsService: any AnalyticsServiceProtocol {
        get { self[AnalyticsServiceKey.self] }
        set { self[AnalyticsServiceKey.self] = newValue }
    }
}

// MARK: - Subscription Service

private struct SubscriptionServiceKey: EnvironmentKey {
    static let defaultValue: any SubscriptionServiceProtocol = SubscriptionManager.shared
}

extension EnvironmentValues {
    var subscriptionService: any SubscriptionServiceProtocol {
        get { self[SubscriptionServiceKey.self] }
        set { self[SubscriptionServiceKey.self] = newValue }
    }
}

// MARK: - Auth Service

private struct AuthServiceKey: EnvironmentKey {
    static let defaultValue: any AuthServiceProtocol = AuthService.shared
}

extension EnvironmentValues {
    var authService: any AuthServiceProtocol {
        get { self[AuthServiceKey.self] }
        set { self[AuthServiceKey.self] = newValue }
    }
}

// MARK: - Data Service

private struct DataServiceKey: EnvironmentKey {
    static let defaultValue: any DataServiceProtocol = FirestoreManager.shared
}

extension EnvironmentValues {
    var dataService: any DataServiceProtocol {
        get { self[DataServiceKey.self] }
        set { self[DataServiceKey.self] = newValue }
    }
}

// MARK: - Health Service

private struct HealthServiceKey: EnvironmentKey {
    static let defaultValue: any HealthServiceProtocol = HealthKitManager.shared
}

extension EnvironmentValues {
    var healthService: any HealthServiceProtocol {
        get { self[HealthServiceKey.self] }
        set { self[HealthServiceKey.self] = newValue }
    }
}

// MARK: - Stats Service

private struct StatsServiceKey: EnvironmentKey {
    static let defaultValue: any StatsServiceProtocol = StatsManager.shared
}

extension EnvironmentValues {
    var statsService: any StatsServiceProtocol {
        get { self[StatsServiceKey.self] }
        set { self[StatsServiceKey.self] = newValue }
    }
}

