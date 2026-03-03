import SwiftUI
import UIKit

struct PrimaryAuthButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            // Provide light haptic feedback.
            HapticManager.shared.impact(.light)
            action()
        }) {
            Text(title)
                .nunitoFont(size: 16, style: .semiBold)
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(width: 288, height: 46)
                .foregroundColor(.backgroundDarkPurple)
                .background(Color.dojoTurquoise)
                .cornerRadius(23)
        }
    }
}

struct PrimaryAuthButton_Previews: PreviewProvider {
    static var previews: some View {
        PrimaryAuthButton(title: "Example Button") {
            print("Button tapped")
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.black)
    }
}
