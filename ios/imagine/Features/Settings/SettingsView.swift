import SwiftUI
 
// Reusable settings button matching the specified design
struct SettingsActionButton: View {
	let title: String
	let systemImageName: String?
	let textColor: Color
	let backgroundColor: Color
	let contentAlignment: Alignment
	let textFont: Font
	let includeHorizontalPadding: Bool
	let action: () -> Void

	init(
		title: String,
		systemImageName: String? = nil,
		textColor: Color = .textForegroundGray,
		backgroundColor: Color = Color(red: 0.24, green: 0.24, blue: 0.36),
		contentAlignment: Alignment = .leading,
		textFont: Font = Font.custom("Nunito", size: 14).weight(.medium),
		includeHorizontalPadding: Bool = true,
		action: @escaping () -> Void
	) {
		self.title = title
		self.systemImageName = systemImageName
		self.textColor = textColor
		self.backgroundColor = backgroundColor
		self.contentAlignment = contentAlignment
		self.textFont = textFont
		self.includeHorizontalPadding = includeHorizontalPadding
		self.action = action
	}

	var body: some View {
		Button(action: action) {
			ZStack {
				Rectangle()
					.foregroundColor(.clear)
					.frame(width: 288, height: 42)
					.position(x: 144, y: 21)
					.background(backgroundColor)
					.cornerRadius(100)

				HStack(spacing: 10) {
					if let imageName = systemImageName {
						Image(systemName: imageName)
							.font(.system(size: 16, weight: .semibold))
					}
					Text(title)
						.font(textFont)
				}
				.foregroundColor(textColor)
				.padding(.horizontal, includeHorizontalPadding ? 26 : 0)
				.frame(width: 288, height: 42, alignment: contentAlignment)
			}
		}
		.buttonStyle(PlainButtonStyle())
		.frame(maxWidth: .infinity, alignment: .center)
	}
}
import HealthKit
import FirebaseAuth

struct SettingsView: View {
    // MARK: - Environment Services (DI)
    @Environment(\.healthService) private var healthService
    @Environment(\.analyticsService) private var analytics
    
    @ObservedObject var authViewModel: AuthViewModel
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode

    @State private var showLogoutDialog = false
    @State private var showDeleteAccountDialog = false
    @State private var showClearCacheSheet = false

    @State private var isHealthKitEnabled = false
    @State private var isRequestingAuthorization = false
    
    // Developer mode state
    @State private var developerTapCount = 0
    @State private var isDeveloperModeEnabled = false
    @State private var developerTapResetWorkItem: DispatchWorkItem? = nil
    @State private var lastTapTimestamp: TimeInterval = 0
    @State private var hrMonitoringEnabled: Bool = false
    @State private var showReadyToUninstallAlert = false

    let showTitle: Bool

    init(authViewModel: AuthViewModel, showTitle: Bool = true) {
        self.authViewModel = authViewModel
        self.showTitle = showTitle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Header with hidden developer trigger (optional)
                if showTitle {
                    Text("My Settings")
                        .allenoireFont(size: 36)
                        .foregroundColor(isDeveloperModeEnabled ? .dojoTurquoise : .white)
                        .padding(.bottom, 10)
                        .padding(.top, 20)
                        .onTapGesture {
                            handleDeveloperTap()
                        }
                }
                
                // Developer mode settings (extracted to separate view)
                if isDeveloperModeEnabled {
                    DevModeSettingsView(
                        onTestNewUser: testNewUserWithUIDReset
                    )
                    .environmentObject(navigationCoordinator)
                }
                
                // Health Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Health Integration")
                        .font(Font.custom("Nunito", size: 18).weight(.medium))
                        .kerning(0.04)
                        .foregroundColor(.textForegroundGray)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    if isHealthKitEnabled {
                        // Connected state
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.dojoTurquoise)
                                .font(.system(size: 20))
                            
                            Text("Apple Health connected")
                                .nunitoFont(size: 16, style: .medium)
                                .foregroundColor(.foregroundLightGray)
                            
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.backgroundPurple)
                        .cornerRadius(12)
                    } else {
                        // Connect button
                        SettingsActionButton(
                            title: isRequestingAuthorization ? "Connecting..." : "Connect Apple Health",
                            systemImageName: "plus.circle.fill",
                            action: { requestHealthKitAuthorization() }
                        )
                        .disabled(isRequestingAuthorization)
                    }
                    
                    // Heart Rate Monitoring toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Heart Rate Monitoring")
                                .nunitoFont(size: 16, style: .semiBold)
                                .foregroundColor(.foregroundLightGray)
                            Text("Measure heart rate during sessions")
                                .nunitoFont(size: 12, style: .regular)
                                .foregroundColor(.foregroundLightGray.opacity(0.6))
                        }
                        Spacer()
                        Toggle("", isOn: $hrMonitoringEnabled)
                            .labelsHidden()
                            .tint(.dojoTurquoise)
                            .onChange(of: hrMonitoringEnabled) { _, newValue in
                                PhoneConnectivityManager.shared.updateHRFeatureEnabled(newValue)
                            }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.backgroundPurple)
                    .cornerRadius(12)

                }
                .padding(.bottom, 10)

                // Account Actions Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Account")
                        .font(Font.custom("Nunito", size: 18).weight(.medium))
                        .kerning(0.04)
                        .foregroundColor(.textForegroundGray)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    // Developer-only Clear Data button
                    if isDeveloperModeEnabled {
                        SettingsActionButton(
                            title: "Clear Data",
                            systemImageName: "trash.circle.fill",
                            action: { showClearCacheSheet = true }
                        )
                        .sheet(isPresented: $showClearCacheSheet) {
                            ClearCacheView(onConfirm: { categories in
                                handleClearCache(categories: categories)
                            }, onCancel: {
                                showClearCacheSheet = false
                            })
                        }
                        .alert("Ready for Uninstall", isPresented: $showReadyToUninstallAlert) {
                            Button("OK - I'll Delete Now") {
                                // Just dismiss the alert - user should close app and delete
                            }
                        } message: {
                            Text("✅ All data cleared:\n• Firebase UID\n• Journey progress\n• Onboarding/Subscription state\n• Analytics identity\n\n⚠️ Close the app and DELETE it now.\n\n📱 Next install will be a TRUE new user:\nSign Up → Onboarding → Subscription → Path")
                        }
                    }

                    // Sign out button
                    SettingsActionButton(
                        title: "Sign out",
                        systemImageName: "rectangle.portrait.and.arrow.right",
                        action: { showLogoutDialog = true }
                    )
                    .confirmationDialog("Do you want to sign out?", isPresented: $showLogoutDialog, actions: {
                        Button("Sign out", role: .destructive) {
                            performRegularSignOut()
                        }
                        Button("Cancel", role: .cancel) {}
                    })

                    // Delete Account button
                    SettingsActionButton(
                        title: "Delete account",
                        systemImageName: nil,
                        textColor: Color.textNegativePromise,
                        contentAlignment: .center,
                        textFont: Font.custom("Nunito", size: 16).weight(.semibold),
                        includeHorizontalPadding: false,
                        action: { showDeleteAccountDialog = true }
                    )
                    .confirmationDialog("Are you sure you want to delete your account? This action cannot be undone.", isPresented: $showDeleteAccountDialog, actions: {
                        Button("Delete Account Permanently", role: .destructive) {
                            authViewModel.deleteAccount { success in
                                if success {
                                    navigationCoordinator.currentView = .signUp
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    })
                }
            }
            .padding(.horizontal, 56)
        }
        .simultaneousGesture(TapGesture().onEnded { handleDeveloperTap() })
        .background(
            Color.backgroundNavy
                .contentShape(Rectangle())
                .onTapGesture { handleDeveloperTap() }
        )
        .ignoresSafeArea()
        .onAppear(perform: checkHealthKitStatus)
        .onFirstAppear {
            // Load persisted flags
            isDeveloperModeEnabled = SharedUserStorage.retrieve(forKey: .devModeEnabled, as: Bool.self, defaultValue: false)
            hrMonitoringEnabled = SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false)
            // Ensure watch receives current flag on first appear
            PhoneConnectivityManager.shared.pushHRFeatureFlagToWatch()
        }
        .onDisappear {
            // Empty onDisappear
        }
    }

    // MARK: - Developer Mode Functions
    
    private func handleDeveloperTap() {
        // Guard out accidental double-fires within 200ms
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastTapTimestamp < 0.2 { return }
        lastTapTimestamp = now

        // Ignore further taps once enabled
        guard !isDeveloperModeEnabled else { return }

        developerTapCount += 1
        print("🔧 Developer tap: \(developerTapCount)/7")

        if developerTapCount >= 7 {
            isDeveloperModeEnabled = true
            SharedUserStorage.save(value: true as Bool, forKey: .devModeEnabled)
            developerTapCount = 0
            developerTapResetWorkItem?.cancel()
            developerTapResetWorkItem = nil

            // Haptic feedback
            HapticManager.shared.impact(.medium)

            logger.eventMessage("🔧 DEVELOPER MODE ENABLED")
            return
        }

        // Debounced inactivity reset (3s after the LAST tap)
        developerTapResetWorkItem?.cancel()
        let work = DispatchWorkItem {
            // Only reset if still not enabled
            if !isDeveloperModeEnabled && developerTapCount > 0 && developerTapCount < 7 {
                developerTapCount = 0
                print("🔧 Developer tap reset due to inactivity")
            }
            developerTapResetWorkItem = nil
        }
        developerTapResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    
    // MARK: - Test New User with UID Reset
    
    /// Clears UID, journey, and all user data - then prompts to uninstall/reinstall
    /// This is the most accurate way to test the true new user experience
    private func testNewUserWithUIDReset() {
        print("📊 JOURNEY: ═══════════════════════════════════════════════════")
        print("📊 JOURNEY: [TEST_NEW_USER_UID] Starting FULL new user test")
        print("📊 JOURNEY: [TEST_NEW_USER_UID] This will clear UID + Journey + Sign out")
        print("📊 JOURNEY: ═══════════════════════════════════════════════════")
        
        // Log current state before reset
        print("📊 JOURNEY: [TEST_NEW_USER_UID] BEFORE reset:")
        print("📊 JOURNEY:   - Firebase UID: \(UserIdentityManager.shared.currentUserId)")
        print("📊 JOURNEY:   - OnboardingState.isComplete: \(OnboardingState.shared.isComplete)")
        print("📊 JOURNEY:   - SubscriptionState.isComplete: \(SubscriptionState.shared.isComplete)")
        print("📊 JOURNEY:   - ProductJourneyManager.currentPhase: \(ProductJourneyManager.shared.currentPhase.displayName)")
        
        // Haptic feedback
        HapticManager.shared.impact(.medium)
        
        // Use prepareForUninstallTest which clears:
        // - All install tracking flags
        // - Auth storage
        // - AI onboarding state
        // - ProductJourneyManager (including pre-app phases)
        // - OnboardingState and SubscriptionState
        // - Journey phase cache
        // - Session flags
        // - Mixpanel
        // - Firebase sign out (NO new user created)
        #if DEBUG
        UserIdentityManager.shared.prepareForUninstallTest()
        #endif
        
        // Show alert telling user to uninstall
        showReadyToUninstallAlert = true
        
        print("📊 JOURNEY: [TEST_NEW_USER_UID] ✅ Ready for uninstall")
        print("📊 JOURNEY: [TEST_NEW_USER_UID] User should close app and DELETE it")
        print("📊 JOURNEY: [TEST_NEW_USER_UID] Next install = TRUE fresh user experience")
        print("📊 JOURNEY: [TEST_NEW_USER_UID] Flow: Sign Up >> Onboarding >> Subscription >> Path")
        print("📊 JOURNEY: ═══════════════════════════════════════════════════")
    }
    
    private func handleClearCache(categories: [ClearCacheCategory]) {
        // Check if Clear UID and Sign Out was selected
        if categories.contains(.clearUIDAndSignOut) {
            // Handle the special case of clearing UID and signing out
            performCompleteSignOut()
        } else {
            // Handle regular cache clearing
            AppFunctions.clearCache(categories: categories)
        }
        showClearCacheSheet = false
    }
    
    // MARK: - Sign Out Functions
    
    private func performRegularSignOut() {
        logger.eventMessage("SettingsView: Regular sign out confirmed")
        
        // Regular sign out - preserves UID for analytics continuity
        authViewModel.logout()
        appState.signOut()
        
        // Navigate to SignIn view (not SignUp) since user already has an account
        navigationCoordinator.currentView = .signIn(email: "")
        
        presentationMode.wrappedValue.dismiss()
        logger.eventMessage("SettingsView: Regular sign out complete - navigating to SignIn")
    }
    
    private func performCompleteSignOut() {
        logger.eventMessage("SettingsView: Preparing for uninstall test")
        
        #if DEBUG
        // Use the new prepareForUninstallTest method that clears everything
        // but does NOT create a new anonymous user or navigate away
        UserIdentityManager.shared.prepareForUninstallTest()
        
        // Show alert telling user to delete the app
        showReadyToUninstallAlert = true
        
        logger.eventMessage("SettingsView: Ready for uninstall - user should delete app now")
        #else
        // In release builds, perform normal sign out
        UserIdentityManager.shared.signOut(getNewAnonymousUser: true)
        appState.signOut()
        presentationMode.wrappedValue.dismiss()
        logger.eventMessage("SettingsView: Complete sign out with UID reset complete")
        #endif
    }

    // MARK: - Health Functions

    private func checkHealthKitStatus() {
        if let status = HealthKitManager.shared.getAuthorizationStatus() {
            isHealthKitEnabled = (status == .sharingAuthorized)
        } else {
            isHealthKitEnabled = false
        }
    }

    private func requestHealthKitAuthorization() {
        isRequestingAuthorization = true
        healthService.requestAuthorization { success, _ in
            DispatchQueue.main.async {
                isRequestingAuthorization = false
                isHealthKitEnabled = success
                // Mark that user has been presented with HealthKit option
                SharedUserStorage.save(value: true, forKey: .hasRequestedHealthKitAuthorization)
            }
        }
    }
}

#if DEBUG
#Preview("Connected") {
    SettingsView(authViewModel: AuthViewModel())
        .withPreviewEnvironment()
        .environmentObject(NavigationCoordinator())
        .environmentObject(AppState())
}

#Preview("Not Connected") {
    SettingsView(authViewModel: AuthViewModel())
        .withPreviewEnvironment()
        .environmentObject(NavigationCoordinator())
        .environmentObject(AppState())
}
#endif

// SettingsSheetView alias removed - ProfileSheetView is no longer used with side menu navigation
