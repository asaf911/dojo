//
//  Constants.swift
//  imagine
//
//  Created for color constants
//

import SwiftUI

struct Constants {
    static let lightGrey = Color.foregroundLightGray
    
    /// Opacity for container surfaces rendered on top of background images
    static let surfaceOpacity: Double = 0.95
}

// MARK: - Surface Background Modifier

extension View {
    /// Applies the standard surface background style for cards/containers rendered on top of background images.
    /// - Parameter cornerRadius: The corner radius for the container (default: 18)
    /// - Returns: The view with the unified surface background applied
    func surfaceBackground(cornerRadius: CGFloat = 18) -> some View {
        self.background(
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.00),
                    Gradient.Stop(color: Color(red: 0.08, green: 0.08, blue: 0.14), location: 1.00),
                ],
                startPoint: UnitPoint(x: 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 1)
            )
            .opacity(Constants.surfaceOpacity)
        )
        .cornerRadius(cornerRadius)
    }
}

