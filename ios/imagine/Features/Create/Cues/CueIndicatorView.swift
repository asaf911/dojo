//
//  CueIndicatorView.swift
//  imagine
//
//  Created by Asaf Shamir on 4/17/25.
//

import SwiftUI

struct CueIndicatorView: View {
    let text: String
    let isSelected: Bool
    let action: (() -> Void)?
    var customFontSize: CGFloat? = nil
    let source: String
    var isMenuButton: Bool = false
    
    var body: some View {
        Button(action: {
            if !isMenuButton, let action = action {
                action()
                AnalyticsManager.shared.logEvent("cue_capsule_tap", parameters: [
                    "cue_content": text,
                    "source": source
                ])
            }
        }) {
            Text(text)
                .nunitoFont(size: customFontSize ?? 14, style: isSelected ? .medium : .regular)
                .kerning(0.07)
                .multilineTextAlignment(.center)
                .foregroundColor(isSelected ? .foregroundDarkBlue : .white)
                .padding(.vertical, 4)
                .padding(.horizontal, 13)
                .frame(minWidth: 63)
                .background(isSelected ? .selectedLightPurple : .backgroundDarkPurple.opacity(0.5))
                .cornerRadius(23)
                .overlay(
                    RoundedRectangle(cornerRadius: 23)
                        .inset(by: 0.5)
                        .stroke(.white.opacity(isSelected ? 0 : 0.32), lineWidth: 1)
                )
        }
    }
}

// MARK: - Preview

struct CueIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Unselected Cue
            CueIndicatorView(
                text: "Bell",
                isSelected: false,
                action: {},
                source: "Preview"
            )
            .previewDisplayName("Unselected Cue")

            // Selected Cue
            CueIndicatorView(
                text: "Gong",
                isSelected: true,
                action: {},
                source: "Preview"
            )
            .previewDisplayName("Selected Cue")

            // Unselected Trigger
            CueIndicatorView(
                text: "Start",
                isSelected: false,
                action: {},
                source: "Preview"
            )
            .previewDisplayName("Unselected Trigger")

            // Demonstration of custom font size
            CueIndicatorView(
                text: "Custom Font",
                isSelected: false,
                action: {},
                customFontSize: 18,
                source: "Preview"
            )
            .previewDisplayName("Custom Font Size 18")
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.backgroundDarkPurple)
        .environment(\.colorScheme, .dark)
    }
}

