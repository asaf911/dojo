import SwiftUI

struct RoundButtonStyle: ButtonStyle {
    var isEnabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? .dojoTurquoise : .gray)
            .font(.system(size: 30))
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
    }
}

struct CustomBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .foregroundColor(.white)
                .padding(.trailing, 30) // Increase the tappable area
                .contentShape(Rectangle()) // Make the entire padded area tappable
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DividerView: View {
    var body: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(.dividerGray)
    }
}
