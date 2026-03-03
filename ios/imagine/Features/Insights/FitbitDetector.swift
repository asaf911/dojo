import UIKit

/// Lightweight utility for detecting whether the Fitbit app is installed on this device.
/// Used by FitbitHRProvider (to gate BLE scanning) and LiveHeartRateCard (to show the
/// "Enable HR on Equipment" prompt when no HR source is active yet).
///
/// Requires `fitbit` in LSApplicationQueriesSchemes (Info.plist) for canOpenURL to work.
struct FitbitDetector {
    static var isFitbitAppInstalled: Bool {
        guard let url = URL(string: "fitbit://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
