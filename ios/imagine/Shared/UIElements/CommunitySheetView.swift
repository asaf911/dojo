import SwiftUI

struct CommunitySheetView: View {
    @Environment(\.presentationMode) var presentationMode  // Access presentation mode for dismissal

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background image or color to match SubscriptionView
            Image(.subscriptionBackground) // Assuming you have this image asset
                .resizable()
                .ignoresSafeArea()

            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()  // Push content down to center vertically
                    Image("ImagineIconNoBG")
                        .resizable()
                        .aspectRatio(75 / 63, contentMode: .fit)
                        .frame(height: 63)
                    Spacer().frame(height: 20)
                    Text("Join Our Community")
                        .nunitoFont(size: 28, style: .bold)
                        .foregroundColor(.white)
                    
                    Text("Share experiences, ask questions, and connect with other meditators.")
                        .nunitoFont(size: 18, style: .medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer().frame(height: 20)
                    Button(action: openDiscordLink) {
                        Text("Join Dojo on Discord")
                            .nunitoFont(size: 16, style: .semiBold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .foregroundColor(.foregroundDarkBlue)
                            .background(Color.dojoTurquoise)
                            .cornerRadius(25)
                            .frame(minWidth: 280)
                    }
                    .padding(.horizontal)

                    Spacer()  // Push content up to center vertically
                }
                .frame(width: geometry.size.width * 0.9)  // Set width to 90% of screen width for horizontal padding
                .padding(.horizontal)  // Add padding to keep content away from edges
                .padding(.vertical, 20)
                .cornerRadius(20)  // Add corner radius for rounded edges
                .shadow(radius: 10)  // Optional: add shadow for better visibility
            }

            // Close button
            Button(action: {
                presentationMode.wrappedValue.dismiss()  // Dismiss the sheet
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.clear)
                    .clipShape(Circle())
            }
            .padding()
        }
    }

    private func openDiscordLink() {
        AnalyticsManager.shared.logEvent("join_discord_tap", parameters: ["source": "CommunitySheetView"])
        
        if let url = URL(string: "https://discord.gg/MtQwfm7YU5") {
            UIApplication.shared.open(url)
        }
    }

}

#Preview {
    CommunitySheetView()
}
