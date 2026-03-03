import UIKit
import FirebaseAnalytics
import Mixpanel

class AnalyticsManager {

    static let shared = AnalyticsManager()
    private var eventQueue: [(String, [String: Any]?)] = []
    private var isAppInBackground = false
    private let eventQueueFileName = "eventQueue.json"
    // For this phase, send analytics only to Mixpanel
    private let mixpanelOnly: Bool = true
    
    // Set to true only when debugging analytics queue issues
    private let verboseEventQueueLogging = false
    
    // DEPRECATED: Use SessionContextManager.shared instead for session tracking.
    // When starting a practice/timer from AI, set this to "ai" so all
    // subsequent practice-related events can include the source tag.
    // Cleared when the timer session ends.
    // TODO: Remove after full migration to SessionContextManager
    @available(*, deprecated, message: "Use SessionContextManager.shared instead")
    public var currentPracticeSource: String?

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        loadEventQueue()
    }

    @objc private func appDidEnterBackground() {
        isAppInBackground = true
        saveEventQueue()
    }

    @objc private func appWillEnterForeground() {
        isAppInBackground = false
        loadEventQueue()
        flushEvents()
    }

    private func mapEventName(for vendor: String, eventName: String) -> String {
        let eventMapping: [String: [String: String]] = [
            "Firebase": [
                "sign_in": AnalyticsEventLogin,
                "sign_up": AnalyticsEventSignUp
            ]
        ]
        return eventMapping[vendor]?[eventName] ?? eventName
    }

    func logEvent(_ name: String, parameters: [String: Any]?) {
        // With our simplified approach, we don't need to ensure identity before each event
        // Mixpanel will automatically use the correct distinct_id
        
        var finalParams = parameters

        // Convert Dates to Strings
        if var params = finalParams {
            let formatter = ISO8601DateFormatter()
            for (key, value) in params {
                if let dateValue = value as? Date {
                    params[key] = formatter.string(from: dateValue)
                }
            }
            finalParams = params
        }

        // Add user ID to all events for better tracking
        if var params = finalParams {
            // Add current user ID as a parameter for better tracking
            params["user_id"] = UserIdentityManager.shared.currentUserId
            finalParams = params
        } else {
            // If no parameters, create a dictionary with user_id
            finalParams = ["user_id": UserIdentityManager.shared.currentUserId]
        }

        // Always add to event queue first for persistence (sanitize to JSON-safe)
        eventQueue.append((name, sanitizeForJSON(finalParams)))
        
        sendEventToAll(name, parameters: finalParams)
        logger.eventMessage("Event logged: \(name) with parameters: \(finalParams ?? [:])")
        saveEventQueue()
    }

    private func sendEventToAll(_ name: String, parameters: [String: Any]?) {
        // Firebase - respect gate
        if !mixpanelOnly {
            let firebaseEventName = mapEventName(for: "Firebase", eventName: name)
            Analytics.logEvent(firebaseEventName, parameters: parameters)
            logger.eventMessage("Sent event to Firebase: \(firebaseEventName) with parameters: \(parameters ?? [:])")
        }

        // AppsFlyer - route through centralized AppsFlyerManager
        // AppsFlyerManager handles allow-list filtering and event mapping internally
        AppsFlyerManager.shared.logEvent(name, parameters: parameters)

        // Mixpanel - Check if initialized first
        if let mixpanelInstance = getMixpanelInstance() {
            if let mixpanelParams = sanitizeParametersForMixpanel(parameters) {
                mixpanelInstance.track(event: name, properties: mixpanelParams)
                logger.eventMessage("✅ Sent event to Mixpanel: \(name) with parameters: \(mixpanelParams)")
            } else {
                mixpanelInstance.track(event: name)
                logger.eventMessage("✅ Sent event to Mixpanel: \(name) with no parameters")
            }
            
            // Explicitly flush to ensure event is sent immediately
            mixpanelInstance.flush()
        } else {
            logger.warnMessage("⚠️ Skipped sending event to Mixpanel: \(name) - Mixpanel not initialized. Will retry later.")
            
            // Retry after a short delay for critical early-app events
            // These fire before Mixpanel may be fully initialized
            let shouldRetry = name.contains("onboarding") || name.hasPrefix("journey_phase")
            if shouldRetry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.retrySendToMixpanel(name: name, parameters: parameters)
                }
            }
        }

        // POST didLogPracticeEvent if the event name starts with "practice_"
        if name.hasPrefix("practice_") {
            var userInfo: [String: Any] = ["eventName": name]
            
            // Extract practiceID from parameters if available
            if let params = parameters,
               let practiceID = params["practice_id"] as? String {
                userInfo["practiceID"] = practiceID
            }
            
            NotificationCenter.default.post(
                name: .didLogPracticeEvent,
                object: nil,
                userInfo: userInfo
            )
        }
    }
    
    // Retry mechanism specifically for Mixpanel
    private func retrySendToMixpanel(name: String, parameters: [String: Any]?) {
        logger.eventMessage("🔄 Retrying Mixpanel event: \(name)")
        
        if let mixpanelInstance = getMixpanelInstance() {
            if let mixpanelParams = sanitizeParametersForMixpanel(parameters) {
                mixpanelInstance.track(event: name, properties: mixpanelParams)
                logger.eventMessage("✅ Retry successful - Sent event to Mixpanel: \(name) with parameters: \(mixpanelParams)")
            } else {
                mixpanelInstance.track(event: name)
                logger.eventMessage("✅ Retry successful - Sent event to Mixpanel: \(name) with no parameters")
            }
            mixpanelInstance.flush()
        } else {
            logger.errorMessage("❌ Retry failed - Mixpanel still not initialized for event: \(name)")
        }
    }

    // Helper method to safely get Mixpanel instance
    private func getMixpanelInstance() -> MixpanelInstance? {
        // Make sure a token is set
        let instance = Mixpanel.mainInstance()
        let token = instance.apiToken
        if token.isEmpty {
            logger.warnMessage("Mixpanel token is empty - not properly initialized")
            return nil
        }
        
        // Additional check to ensure Mixpanel is truly ready
        // Try to access the distinctId which should be available if properly initialized
        let distinctId = instance.distinctId
        if distinctId.isEmpty {
            logger.warnMessage("Mixpanel distinctId is empty - not fully initialized")
            return nil
        }
        
        return instance
    }

    private func sanitizeParametersForMixpanel(_ parameters: [String: Any]?) -> [String: MixpanelType]? {
        guard let params = parameters else { return nil }
        var sanitizedParams: [String: MixpanelType] = [:]

        for (key, value) in params {
            // Try to convert value to MixpanelType
            if let stringValue = value as? String {
                sanitizedParams[key] = stringValue
            } else if let numValue = value as? NSNumber {
                sanitizedParams[key] = numValue
            } else if let boolValue = value as? Bool {
                sanitizedParams[key] = boolValue
            } else if let dateValue = value as? Date {
                // Convert date to ISO string for Mixpanel
                let formatter = ISO8601DateFormatter()
                sanitizedParams[key] = formatter.string(from: dateValue)
            } else if let arrayValue = value as? [MixpanelType] {
                sanitizedParams[key] = arrayValue
            } else if let dictValue = value as? [String: MixpanelType] {
                sanitizedParams[key] = dictValue
            } else {
                // Convert to string as fallback
                sanitizedParams[key] = String(describing: value)
            }
        }

        return sanitizedParams.isEmpty ? nil : sanitizedParams
    }

    // MARK: - Source normalization (DEPRECATED)
    /// DEPRECATED: Use SessionContextManager.shared for session tracking instead.
    /// Normalizes internal practice source tokens to display labels expected by analytics.
    /// "ai_direct" -> "AI", "ai_customized" -> "AI + Customization", "custom_timer" -> "Custom Timer".
    /// Falls back to the input string otherwise.
    @available(*, deprecated, message: "Use SessionContextManager.shared instead")
    public static func displaySourceLabel(for rawSource: String) -> String {
        let lowered = rawSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "ai", "ai_direct":
            return "AI"
        case "ai_customized":
            return "AI + Customization"
        case "custom_timer", "custom timer":
            return "Custom Timer"
        default:
            return rawSource
        }
    }

    private func flushEvents() {
        if eventQueue.isEmpty {
            logger.eventMessage("No events to flush.")
            return
        }

        logger.eventMessage("Flushing \(eventQueue.count) event(s)")

        while !eventQueue.isEmpty {
            let (name, parameters) = eventQueue.removeFirst()
            // Just log the event for record keeping
            logger.eventMessage("Flushed event: \(name) with parameters: \(parameters ?? [:])")
        }

        saveEventQueue()
        logger.eventMessage("Finished flushing events.")
    }

    private func saveEventQueue() {
        let eventData = eventQueue.map { (name, parameters) in
            return ["name": name, "parameters": sanitizeForJSON(parameters) ?? [:]] as [String: Any]
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: eventData, options: .prettyPrinted)
            let fileURL = getDocumentsDirectory().appendingPathComponent(eventQueueFileName)
            try data.write(to: fileURL)
            logger.eventMessage("Saved event queue to \(fileURL) with \(eventQueue.count) events")
        } catch {
            logger.eventMessage("Failed to save event queue: \(error)")
        }
    }

    private func loadEventQueue() {
        let fileURL = getDocumentsDirectory().appendingPathComponent(eventQueueFileName)
        do {
            let data = try Data(contentsOf: fileURL)
            if let eventData = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                eventQueue = eventData.map { event in
                    let name = event["name"] as! String
                    let parameters = event["parameters"] as? [String: Any]
                    return (name, parameters)
                }
                if verboseEventQueueLogging {
                    logger.eventMessage("Loaded event queue from \(fileURL): \(String(data: data, encoding: .utf8) ?? "nil")")
                    logger.eventMessage("Event queue after loading: \(eventQueue)")
                }
            } else {
                logger.eventMessage("Failed to cast loaded event queue data")
            }
        } catch {
            logger.eventMessage("Failed to load event queue from \(fileURL): \(error)")
        }
    }

    private func printEventQueueFromFile() {
        guard verboseEventQueueLogging else { return }
        let fileURL = getDocumentsDirectory().appendingPathComponent(eventQueueFileName)
        do {
            let data = try Data(contentsOf: fileURL)
            logger.eventMessage("Current event queue in file \(fileURL): \(String(data: data, encoding: .utf8) ?? "nil")")
        } catch {
            logger.eventMessage("Failed to read event queue from file \(fileURL): \(error)")
        }
    }

    private func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - JSON sanitization
    private func sanitizeForJSON(_ parameters: [String: Any]?) -> [String: Any]? {
        guard let params = parameters else { return nil }
        var out: [String: Any] = [:]
        for (k, v) in params {
            out[k] = sanitizeJSONValue(v)
        }
        return out
    }

    private func sanitizeJSONValue(_ value: Any) -> Any {
        switch value {
        case let s as String:
            return s
        case let n as NSNumber:
            return n
        case let b as Bool:
            return b
        case let d as Date:
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: d)
        case let u as URL:
            return u.absoluteString
        case let uuid as UUID:
            return uuid.uuidString
        case let dict as [String: Any]:
            return sanitizeForJSON(dict) ?? [:]
        case let arr as [Any]:
            return arr.map { sanitizeJSONValue($0) }
        default:
            return String(describing: value)
        }
    }
}

// MARK: - AnalyticsServiceProtocol Conformance

extension AnalyticsManager: AnalyticsServiceProtocol {
    // Protocol conformance is automatic since AnalyticsManager already implements:
    // - func logEvent(_ name: String, parameters: [String: Any]?)
    // - var currentPracticeSource: String?
}
