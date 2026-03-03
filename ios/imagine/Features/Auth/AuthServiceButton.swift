import SwiftUI
import UIKit

struct AuthServiceButton: View {
    let iconName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            // Provide light haptic feedback.
            HapticManager.shared.impact(.light)
            action()
        }) {
            HStack(spacing: 8) {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(title)
                    .nunitoFont(size: 16, style: .bold)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 136, height: 46)
        .background(Color.clear)
        .cornerRadius(23)
        .overlay(
            RoundedRectangle(cornerRadius: 23)
                .stroke(Color("planBorder"), lineWidth: 1)
        )
    }
}

struct AuthServiceButton_Previews: PreviewProvider {
    static var previews: some View {
        AuthServiceButton(iconName: "googleLogin", title: "Google") {
            print("Google tapped")
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.black)
    }
}
