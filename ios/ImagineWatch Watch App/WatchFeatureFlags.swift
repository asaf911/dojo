import Foundation

final class WatchFeatureFlags {
    static let shared = WatchFeatureFlags()
    private init() {}

    private let defaults = UserDefaults.standard
    private let hrKey = "hrFeatureEnabled"

    var isHRFeatureEnabled: Bool {
        return defaults.bool(forKey: hrKey)
    }

    func setHRFeatureEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: hrKey)
    }
}


