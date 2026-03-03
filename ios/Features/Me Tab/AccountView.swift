import SwiftUI

struct AccountView: View {
    @State private var showLogoutDialog = false
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var logger = Logger()

    var body: some View {
        // Update the sign out confirmation dialog
        .confirmationDialog("Do you want to sign out?", isPresented: $showLogoutDialog, actions: {
            Button("Sign out", role: .destructive) {
                logger.eventMessage("AccountView: Sign out confirmed. Current view before logout: \(navigationCoordinator.currentView)")
                authViewModel.logout()
                navigationCoordinator.currentView = .signIn(email: "")
                logger.eventMessage("AccountView: Navigated to \(navigationCoordinator.currentView)")
                presentationMode.wrappedValue.dismiss()
            }
            Button("Cancel", role: .cancel) {}
        })
    }
}

struct AccountView_Previews: PreviewProvider {
    static var previews: some View {
        AccountView()
    }
} 