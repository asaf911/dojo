.sheet(isPresented: $isShowingProfile) {
    ProfileView()
        .environmentObject(authManager)
}
.onChange(of: authManager.isAuthenticated) { newValue in
    if !newValue {
        isShowingProfile = false
    }
} 