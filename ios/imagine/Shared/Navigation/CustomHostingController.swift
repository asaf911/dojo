//
//  CustomHostingController.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-13
//

import SwiftUI

class CustomHostingController<Content: View>: UIHostingController<Content>, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Enable the interactive pop gesture when this hosting controller is embedded in a UINavigationController.
        if let navigationController = self.navigationController {
            navigationController.interactivePopGestureRecognizer?.delegate = self
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
    
    // Allow the gesture to begin only if there is more than one view controller on the navigation stack.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return (self.navigationController?.viewControllers.count ?? 0) > 1
    }
    
    // Allow simultaneous gesture recognition for smoother transitions.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
