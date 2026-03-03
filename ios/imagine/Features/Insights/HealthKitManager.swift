// HealthKitManager.swift

import Foundation
import HealthKit

class HealthKitManager {
    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()

    private init() {}

    // MARK: - Request Authorization

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        // Check if HealthKit is available on this device
        guard HKHealthStore.isHealthDataAvailable() else {
            let error = NSError(domain: "HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device"])
            logger.errorMessage("HealthKit is not available: \(error.localizedDescription)", function: #function, line: #line, file: #file)
            completion(false, error)
            return
        }

        // Define the data types we want to write
        guard let mindfulnessType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            let error = NSError(domain: "HealthKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create mindfulSession type"])
            logger.errorMessage("Failed to create mindfulSession type: \(error.localizedDescription)", function: #function, line: #line, file: #file)
            completion(false, error)
            return
        }

        let typesToShare: Set = [mindfulnessType]

        // Request authorization
        healthStore.requestAuthorization(toShare: typesToShare, read: nil) { (success, error) in
            if success {
                logger.infoMessage("HealthKit authorization granted.", function: #function, line: #line, file: #file)
            } else {
                let errorMessage = error?.localizedDescription ?? "Unknown error"
                logger.errorMessage("HealthKit authorization denied: \(errorMessage)", function: #function, line: #line, file: #file)
            }
            completion(success, error)
        }
    }
    
    // MARK: - Mindful Minutes Authorization (Write)
    
    /// Requests authorization to write Mindful Minutes to HealthKit.
    /// This is a separate permission from heart rate reading.
    func requestMindfulMinutesAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        // Check if HealthKit is available on this device
        guard HKHealthStore.isHealthDataAvailable() else {
            let error = NSError(domain: "HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device"])
            logger.errorMessage("HealthKit is not available: \(error.localizedDescription)", function: #function, line: #line, file: #file)
            completion(false, error)
            return
        }

        // Define the Mindful Minutes type we want to write
        guard let mindfulnessType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            let error = NSError(domain: "HealthKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create mindfulSession type"])
            logger.errorMessage("Failed to create mindfulSession type: \(error.localizedDescription)", function: #function, line: #line, file: #file)
            completion(false, error)
            return
        }

        let typesToShare: Set = [mindfulnessType]

        // Request authorization for Mindful Minutes only
        healthStore.requestAuthorization(toShare: typesToShare, read: nil) { (success, error) in
            if success {
                logger.infoMessage("Mindful Minutes authorization granted.", function: #function, line: #line, file: #file)
            } else {
                let errorMessage = error?.localizedDescription ?? "Unknown error"
                logger.errorMessage("Mindful Minutes authorization denied: \(errorMessage)", function: #function, line: #line, file: #file)
            }
            completion(success, error)
        }
    }
    
    /// Returns the authorization status for Mindful Minutes (write permission).
    func getMindfulMinutesAuthorizationStatus() -> HKAuthorizationStatus? {
        guard let mindfulnessType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            logger.errorMessage("Failed to create mindfulSession type for authorization status check.", function: #function, line: #line, file: #file)
            return nil
        }
        return healthStore.authorizationStatus(for: mindfulnessType)
    }
    
    // MARK: - Heart Rate Authorization (Read)
    
    /// Requests authorization to read Heart Rate and write Workouts to HealthKit.
    /// Combines both permissions so the user sees a single consolidated prompt during onboarding.
    /// - Heart Rate (read): needed to display HR data during/after sessions
    /// - Workouts (write): needed for HKWorkoutSession on iPhone (iOS 26+) to enable AirPods Pro HR
    /// Note: iOS does not reliably confirm read authorization status, so we use soft confirmation.
    /// The completion always returns true after prompting (regardless of user choice).
    func requestHeartRateAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        // Check if HealthKit is available on this device
        guard HKHealthStore.isHealthDataAvailable() else {
            let error = NSError(domain: "HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device"])
            logger.errorMessage("HealthKit is not available: \(error.localizedDescription)", function: #function, line: #line, file: #file)
            completion(false, error)
            return
        }

        // Define the Heart Rate type we want to read
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            let error = NSError(domain: "HealthKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create heartRate type"])
            logger.errorMessage("Failed to create heartRate type: \(error.localizedDescription)", function: #function, line: #line, file: #file)
            completion(false, error)
            return
        }

        let typesToRead: Set<HKObjectType> = [heartRateType]
        
        // Include Workouts write permission so AirPodsHRProvider (HKWorkoutSession)
        // doesn't trigger a separate prompt when a meditation session starts
        let workoutType = HKObjectType.workoutType()
        let typesToShare: Set<HKSampleType> = [workoutType]

        // Request authorization for Heart Rate read + Workouts write in one prompt
        // Note: We cannot reliably determine if user granted or denied read permission
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            // For read permissions, 'success' only means the prompt was shown, not that permission was granted
            // We always log as "prompted" since we cannot determine the actual user choice
            logger.infoMessage("Heart Rate + Workouts authorization prompt completed.", function: #function, line: #line, file: #file)
            
            // Always return success since we showed the prompt - actual availability checked at runtime
            completion(true, nil)
        }
    }

    // MARK: - Save Mindfulness Session

    func saveMindfulnessSession(startDate: Date, endDate: Date, completion: @escaping (Bool, Error?) -> Void) {
        // Ensure HealthKit is available
        guard HKHealthStore.isHealthDataAvailable() else {
            let error = NSError(domain: "HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device"])
            logger.errorMessage("HealthKit is not available: \(error.localizedDescription)", function: #function, line: #line, file: #file)
            completion(false, error)
            return
        }

        // Create a mindfulness sample
        guard let mindfulnessType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            let error = NSError(domain: "HealthKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create mindfulSession type"])
            logger.errorMessage("Failed to create mindfulSession type: \(error.localizedDescription)", function: #function, line: #line, file: #file)
            completion(false, error)
            return
        }

        let mindfulnessSample = HKCategorySample(type: mindfulnessType, value: 0, start: startDate, end: endDate)

        // Save the sample to HealthKit
        healthStore.save(mindfulnessSample) { (success, error) in
            if success {
                logger.infoMessage("Mindfulness session saved to HealthKit: Start - \(startDate), End - \(endDate)", function: #function, line: #line, file: #file)
            } else {
                let errorMessage = error?.localizedDescription ?? "Unknown error"
                logger.errorMessage("Failed to save mindfulness session: \(errorMessage)", function: #function, line: #line, file: #file)
            }
            completion(success, error)
        }
    }

    // MARK: - Check Authorization Status

    func getAuthorizationStatus() -> HKAuthorizationStatus? {
        guard let mindfulnessType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            logger.errorMessage("Failed to create mindfulSession type for authorization status check.", function: #function, line: #line, file: #file)
            return nil
        }
        let status = healthStore.authorizationStatus(for: mindfulnessType)
        logger.debugMessage("Current HealthKit authorization status: \(status.rawValue)", function: #function, line: #line, file: #file)
        return status
    }

    // MARK: - Fetch Mindful Sessions (For Debugging)

    func fetchMindfulSessions(completion: @escaping ([HKCategorySample]?, Error?) -> Void) {
        guard let mindfulnessType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            let error = NSError(domain: "HealthKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create mindfulSession type"])
            logger.errorMessage("Failed to create mindfulSession type: \(error.localizedDescription)", function: #function, line: #line, file: #file)
            completion(nil, error)
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: mindfulnessType, predicate: nil, limit: 10, sortDescriptors: [sortDescriptor]) { (query, samples, error) in
            if let error = error {
                logger.errorMessage("Failed to fetch mindful sessions: \(error.localizedDescription)", function: #function, line: #line, file: #file)
                completion(nil, error)
                return
            }

            guard let samples = samples as? [HKCategorySample] else {
                logger.warnMessage("No mindful sessions found.", function: #function, line: #line, file: #file)
                completion([], nil)
                return
            }

            logger.infoMessage("Fetched \(samples.count) mindful session(s) from HealthKit.", function: #function, line: #line, file: #file)
            for session in samples {
                logger.debugMessage("Session - Start: \(session.startDate), End: \(session.endDate), Duration: \(session.endDate.timeIntervalSince(session.startDate)) seconds", function: #function, line: #line, file: #file)
            }

            completion(samples, nil)
        }

        healthStore.execute(query)
    }
}

// MARK: - HealthServiceProtocol Conformance

extension HealthKitManager: HealthServiceProtocol {
    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    // Protocol conformance is automatic for:
    // - func requestAuthorization(completion: @escaping (Bool, Error?) -> Void)
    // - func saveMindfulnessSession(startDate: Date, endDate: Date, completion: @escaping (Bool, Error?) -> Void)
}
