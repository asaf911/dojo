//
//  UIDevice+Extensions.swift
//  Dojo
//
//  Created by [Your Name] on [Date]
//

import UIKit

extension UIDevice {
    var isMaxiPhone: Bool {
        // Ensure this only returns true on iPhone devices.
        return userInterfaceIdiom == .phone && UIScreen.main.nativeBounds.height >= 2688
    }

    /// True when running on iPad hardware, even if the app uses iPhone compatibility mode.
    static var isRunningOnIPadHardware: Bool {
        if UIDevice.current.userInterfaceIdiom == .pad { return true }
        let model = UIDevice.current.model.lowercased()
        return model.contains("ipad")
    }
}
