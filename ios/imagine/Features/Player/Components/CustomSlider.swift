//
//  CustomSlider.swift
//  Dojo
//
//  A UIKit-backed slider that allows customizing the thumb size precisely.
//

import SwiftUI
import UIKit

struct CustomSlider: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var isEnabled: Bool = true
    var minimumTrackColor: UIColor = .white
    var maximumTrackColor: UIColor = UIColor.white.withAlphaComponent(0.3)
    var thumbColor: UIColor = .white
    /// Diameter of the thumb circle in points (visual size)
    var thumbDiameter: CGFloat = 15 // roughly 50% smaller than default iOS thumb
    /// Diameter of the touch target area in points (for fat finger friendly interaction)
    /// Apple recommends minimum 44pt touch targets
    var touchTargetDiameter: CGFloat = 44
    /// Height of the track in points (default iOS is ~2-4pt)
    var trackHeight: CGFloat = 2

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.isEnabled = isEnabled
        
        // Set custom track images for thinner tracks
        let minTrackImage = makeTrackImage(color: minimumTrackColor, height: trackHeight)
        let maxTrackImage = makeTrackImage(color: maximumTrackColor, height: trackHeight)
        slider.setMinimumTrackImage(minTrackImage, for: .normal)
        slider.setMaximumTrackImage(maxTrackImage, for: .normal)
        
        slider.setThumbImage(makeThumbImage(visibleDiameter: thumbDiameter, touchDiameter: touchTargetDiameter, color: thumbColor), for: .normal)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        if uiView.minimumValue != Float(range.lowerBound) || uiView.maximumValue != Float(range.upperBound) {
            uiView.minimumValue = Float(range.lowerBound)
            uiView.maximumValue = Float(range.upperBound)
        }
        if uiView.value != Float(value) {
            uiView.value = Float(value)
        }
        uiView.isEnabled = isEnabled
        
        // Update track images
        let minTrackImage = makeTrackImage(color: minimumTrackColor, height: trackHeight)
        let maxTrackImage = makeTrackImage(color: maximumTrackColor, height: trackHeight)
        uiView.setMinimumTrackImage(minTrackImage, for: .normal)
        uiView.setMaximumTrackImage(maxTrackImage, for: .normal)
        
        // Ensure thumb reflects the configured size/color (in case of dynamic changes)
        uiView.setThumbImage(makeThumbImage(visibleDiameter: thumbDiameter, touchDiameter: touchTargetDiameter, color: thumbColor), for: .normal)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) {
            self.value = value
        }
        @objc func valueChanged(_ sender: UISlider) {
            value.wrappedValue = Double(sender.value)
        }
    }

    private func makeThumbImage(visibleDiameter: CGFloat, touchDiameter: CGFloat, color: UIColor) -> UIImage? {
        // Return transparent image if visible diameter is 0
        if visibleDiameter <= 0 {
            let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
            UIGraphicsBeginImageContextWithOptions(rect.size, false, 0)
            defer { UIGraphicsEndImageContext() }
            let ctx = UIGraphicsGetCurrentContext()
            UIColor.clear.setFill()
            ctx?.fill(rect)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            return image
        }
        
        // Use the larger of touch or visible diameter for the image size
        let imageDiameter = max(visibleDiameter, touchDiameter)
        let rect = CGRect(x: 0, y: 0, width: imageDiameter, height: imageDiameter)
        
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0)
        defer { UIGraphicsEndImageContext() }
        let ctx = UIGraphicsGetCurrentContext()
        
        // Fill with transparent background (for touch area)
        UIColor.clear.setFill()
        ctx?.fill(rect)
        
        // Draw the visible circle centered within the larger touch area
        let visibleRect = CGRect(
            x: (imageDiameter - visibleDiameter) / 2,
            y: (imageDiameter - visibleDiameter) / 2,
            width: visibleDiameter,
            height: visibleDiameter
        )
        color.setFill()
        ctx?.fillEllipse(in: visibleRect)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        return image
    }
    
    private func makeTrackImage(color: UIColor, height: CGFloat) -> UIImage? {
        // Create a stretchable image with rounded left and right edges
        // Use a wider base image to ensure rounded corners are preserved
        let cornerRadius = height / 2
        let baseWidth = max(3, cornerRadius * 2) // Ensure we have enough width for rounded corners
        let rect = CGRect(x: 0, y: 0, width: baseWidth, height: height)
        
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        let ctx = UIGraphicsGetCurrentContext()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        color.setFill()
        ctx?.addPath(path.cgPath)
        ctx?.fillPath()
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        // Make it stretchable, preserving the rounded corners on left and right
        return image?.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: cornerRadius, bottom: 0, right: cornerRadius), resizingMode: .stretch)
    }
}


