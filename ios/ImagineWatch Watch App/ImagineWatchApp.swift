import SwiftUI
import WatchKit
import UserNotifications
import HealthKit

@main
struct imagineWatchApp: App {
    @StateObject private var healthKitManager = WatchHealthKitManager.shared
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    // Debounce lifecycle notifications
    @State private var lastActiveNotification: Date = .distantPast
    @State private var lastBackgroundNotification: Date = .distantPast
    private let notificationDebounceSeconds: TimeInterval = 5

    init() {
        print("[HR] Watch: App starting")
        // Request HealthKit authorization early so it's ready when needed
        requestHealthKitAuthorizationOnLaunch()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(healthKitManager)
                .environmentObject(connectivityManager)
                .onAppear {
                    print("[HR] Watch: UI appeared")
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        // Debounce active notifications
                        let now = Date()
                        if now.timeIntervalSince(lastActiveNotification) > notificationDebounceSeconds {
                            lastActiveNotification = now
                            print("[HR] Watch: App became active")
                            WatchConnectivityManager.shared.notifyWatchAppDidBecomeActive()
                            requestHealthKitAuthorizationOnLaunch()
                        }
                        
                    case .inactive:
                        break  // Don't spam inactive logs
                        
                    case .background:
                        // Debounce background notifications
                        let now = Date()
                        if now.timeIntervalSince(lastBackgroundNotification) > notificationDebounceSeconds {
                            lastBackgroundNotification = now
                            print("[HR] Watch: App went to background")
                            WatchConnectivityManager.shared.notifyWatchAppDidEnterBackground()
                        }
                        
                    @unknown default:
                        break
                    }
                }
        }
    }
    
    /// Request HealthKit authorization early so HR monitoring can start without user intervention
    private func requestHealthKitAuthorizationOnLaunch() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HR] Watch: HealthKit not available")
            return
        }
        
        let healthStore = HKHealthStore()
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let workoutType = HKObjectType.workoutType()
        
        // Check current authorization status
        let hrReadStatus = healthStore.authorizationStatus(for: hrType)
        let workoutShareStatus = healthStore.authorizationStatus(for: workoutType)
        
        print("[HR] Watch: Current auth - HR read: \(hrReadStatus.rawValue), Workout share: \(workoutShareStatus.rawValue)")
        
        // Request authorization if not already determined
        // Note: .notDetermined means we haven't asked yet
        if hrReadStatus == .notDetermined || workoutShareStatus == .notDetermined {
            print("[HR] Watch: Requesting HealthKit authorization...")
            healthStore.requestAuthorization(toShare: [workoutType, hrType], read: [hrType]) { success, error in
                if success {
                    print("[HR] Watch: HealthKit authorization granted")
                } else {
                    print("[HR] Watch: HealthKit authorization failed: \(error?.localizedDescription ?? "unknown")")
                }
            }
        } else if hrReadStatus == .sharingAuthorized && workoutShareStatus == .sharingAuthorized {
            print("[HR] Watch: HealthKit already authorized")
        } else {
            print("[HR] Watch: HealthKit permission denied - user needs to enable in Settings")
        }
    }
}
