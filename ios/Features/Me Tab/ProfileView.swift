@Environment(\.presentationMode) var presentationMode
@Environment(\.dismiss) var dismiss

Button("Sign Out") {
    authViewModel.logout()
    dismiss()
    presentationMode.wrappedValue.dismiss()
}

var body: some View {
    ZStack {
        // ... existing code ...
    }
    .onDisappear {
        Smartlook.instance.track(navigationEvent: "Screen:ProfileView", direction: .exit)
        dismiss()
        presentationMode.wrappedValue.dismiss()
    }
} 