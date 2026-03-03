import SwiftUI

struct FilterOptionView: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    let isDurationFilter: Bool   // Differentiates between duration and tag filters
    let source: String           // New parameter to indicate source view

    // New optional parameter for custom font size
    var customFontSize: CGFloat? = nil

    var body: some View {
        Button(action: {
            action()
            let filterType = isDurationFilter ? "duration" : "tag"
            AnalyticsManager.shared.logEvent("filter_tap", parameters: [
                "filter_type": filterType,
                "filter_content": text,
                "source": source
            ])
        }) {
            Text(text)
                // Use `customFontSize` if present, otherwise default to 14
                .nunitoFont(size: customFontSize ?? 14, style: isSelected ? .medium : .regular)
                .kerning(0.07)
                .multilineTextAlignment(.center)
                .foregroundColor(isSelected ? .foregroundDarkBlue : .white)
                .padding(.vertical, 4)
                .padding(.horizontal, 13)
                .frame(minWidth: 63)
                .background(
                    isSelected ? 
                        AnyView(Color.selectedLightPurple) : 
                        AnyView(
                            LinearGradient(
                                stops: [
                                    Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.00),
                                    Gradient.Stop(color: Color(red: 0.08, green: 0.08, blue: 0.14), location: 1.00),
                                ],
                                startPoint: UnitPoint(x: 0.5, y: 0),
                                endPoint: UnitPoint(x: 0.5, y: 1)
                            )
                        )
                )
                .cornerRadius(23)
                .overlay(
                    RoundedRectangle(cornerRadius: 23)
                        .inset(by: isSelected ? 0.5 : 0.25)
                        .stroke(isSelected ? .white.opacity(0) : .white.opacity(0.32), lineWidth: isSelected ? 1 : 0.5)
                )
        }
    }
}

// MARK: - Preview

struct FilterOptionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Unselected Duration Filter
            FilterOptionView(
                text: "5 m",
                isSelected: false,
                action: {},
                isDurationFilter: true,
                source: "Preview"
            )
            .previewDisplayName("Unselected Duration Filter")

            // Selected Duration Filter
            FilterOptionView(
                text: "10 m",
                isSelected: true,
                action: {},
                isDurationFilter: true,
                source: "Preview"
            )
            .previewDisplayName("Selected Duration Filter")

            // Unselected Tag Filter
            FilterOptionView(
                text: "Relaxation",
                isSelected: false,
                action: {},
                isDurationFilter: false,
                source: "Preview"
            )
            .previewDisplayName("Unselected Tag Filter")

            // Selected Tag Filter
            FilterOptionView(
                text: "Mindfulness",
                isSelected: true,
                action: {},
                isDurationFilter: false,
                source: "Preview"
            )
            .previewDisplayName("Selected Tag Filter")

            // Demonstration of custom font size
            FilterOptionView(
                text: "Custom Font",
                isSelected: false,
                action: {},
                isDurationFilter: true,
                source: "Preview",
                customFontSize: 18
            )
            .previewDisplayName("Custom Font Size 18")
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.backgroundDarkPurple)
        .environment(\.colorScheme, .dark)
    }
}
