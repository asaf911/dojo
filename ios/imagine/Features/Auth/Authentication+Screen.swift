//
//  Authentication+Screen.swift
//  imagine
//
//  Created by Asaf Shamir on 2026-02-12
//

import SwiftUI
import FirebaseAuth
import FirebaseAnalytics
import GoogleSignIn
import AuthenticationServices
import UIKit

@available(iOS 15.0, *)
struct AuthenticationScreen: View {
    // MARK: - Environment Services (DI)
    @Environment(\.analyticsService) private var analytics
    @Environment(\.authService) private var authService

    enum Field: Hashable {
        case email
        case code
    }

    let mode: Authentication.Mode

    @State private var email: String
    @State private var verificationCode = ""
    @State private var step: EmailAuthStep = .enterEmail
    @State private var isLoading = false
    @State private var canResend = false
    @State private var resendCountdown = 60
    @State private var resendTimer: Timer?
    @FocusState private var focusedField: Field?

    @ObservedObject var authViewModel: AuthViewModel
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: AuthenticationViewModel

    // Gate signup until identity system is ready (signUp only)
    @State private var isIdentityReady = false

    init(mode: Authentication.Mode, authViewModel: AuthViewModel, email: String = "") {
        self.mode = mode
        self.authViewModel = authViewModel
        _email = State(initialValue: email)
        _viewModel = StateObject(wrappedValue: AuthenticationViewModel(mode: mode, authViewModel: authViewModel))
        print("📊 [AUTH:UI] Initialized mode=\(mode.debugLabel) email='\(email)'")
    }

    // Set the AppState reference when the view appears
    private func configureAuthViewModel() {
        if authViewModel.appState == nil {
            authViewModel.setAppState(appState)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background color.
            Color.backgroundDarkPurple.ignoresSafeArea()

            // Background image with gradient overlay.
            Image("onboardingSplash")
                .resizable()
                .scaledToFill()
                .frame(
                    width: UIScreen.main.bounds.width,
                    height: UIScreen.main.bounds.width * (376/395)
                )
                .clipped()
                .ignoresSafeArea(edges: .top)
                .overlay(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: Color.clear, location: 0.38),
                            .init(color: Color.backgroundDarkPurple, location: 0.8)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Outer container with identical layout.
            VStack(alignment: .leading, spacing: 0) {
                // Header: left aligned.
                AuthHeaderView(
                    subtitle: step == .enterEmail
                        ? mode.headerSubtitle
                        : "Enter the code sent to your email"
                )
                Spacer().frame(height: UIDevice.isRunningOnIPadHardware ? 0 : 26)

                // Inner container for form elements.
                VStack(spacing: 17) {
                    if step == .enterEmail {
                        enterEmailContent
                    } else {
                        enterCodeContent
                    }
                }
                .padding(.top, 9)
            }
            .padding(.horizontal, 52)
            .padding(.top, UIDevice.isRunningOnIPadHardware ? mode.iPadTopPadding : 244)
            .foregroundColor(.foregroundLightGray)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // Overlay the mute/unmute button in the top-right.
        .overlay(
            MuteUnmuteView(),
            alignment: .topTrailing
        )
        .onTapGesture { focusedField = nil }
        .onFirstAppear {
            // Configure AuthViewModel with AppState reference
            configureAuthViewModel()

            if email.isEmpty {
                email = SharedUserStorage.retrieve(forKey: .lastUsedEmail, as: String.self) ?? ""
            }
            print("📊 [AUTH:UI] onFirstAppear email=\(email)")
        }
        .onAppear {
            // Ensure AuthViewModel has AppState reference
            configureAuthViewModel()

            // Wait for identity system to be ready before allowing interactions (signUp only)
            if mode.waitsForIdentityReady {
                waitForIdentityReady()
            }

            print("📊 [AUTH:UI] onAppear called")
        }
        // ATT: Wait for the app to be confirmed .active before requesting the dialog (signUp only).
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
                .first()
        ) { _ in
            guard mode.requestsATT else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("TRACKING: [ATT] AuthenticationScreen - app confirmed active, requesting ATT")
                AppsFlyerManager.shared.requestATTAuthorization { status in
                    print("TRACKING: [ATT] ATT completed with status: \(status)")
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Step 1: Enter Email

    @ViewBuilder
    private var enterEmailContent: some View {
        // Social Auth Buttons.
        HStack(spacing: 14) {
            AuthServiceButton(iconName: "authGoogle", title: "Google") {
                viewModel.signInWithGoogle { success, isNewUser in
                    if success {
                        print("📊 [AUTH:UI] Google auth successful isNewUser=\(isNewUser)")
                        DispatchQueue.main.async {
                            handleSuccessfulAuth(isNewUser: isNewUser)
                        }
                    } else {
                        print("📊 [AUTH:UI] Google auth failed")
                        GlobalErrorManager.shared.error = .custom(message: "Google Sign-In failed")
                    }
                }
            }
            AuthServiceButton(iconName: "authApple", title: "Apple") {
                viewModel.signInWithApple { success, isNewUser in
                    if success {
                        print("📊 [AUTH:UI] Apple auth successful isNewUser=\(isNewUser)")
                        DispatchQueue.main.async {
                            handleSuccessfulAuth(isNewUser: isNewUser)
                        }
                    } else {
                        print("📊 [AUTH:UI] Apple auth failed")
                        GlobalErrorManager.shared.error = .custom(message: "Apple Sign-In failed")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 4)

        // Divider.
        HStack {
            AuthDividerView(text: mode.dividerText)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 4)

        // Email Input Field.
        HStack {
            InputFieldView(
                title: mode.emailFieldTitle,
                isSecure: false,
                text: $email,
                textContentType: .username,
                keyboardType: .emailAddress,
                iconName: "inputEmail"
            )
            .focused($focusedField, equals: .email)
            .onSubmit { requestCode() }
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .email }
        }
        .frame(maxWidth: .infinity, alignment: .center)

        // Continue Button.
        HStack {
            PrimaryAuthButton(
                title: isLoading ? "Sending..." : "Continue",
                action: requestCode
            )
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, UIDevice.isRunningOnIPadHardware ? 0 : 13)

        // Bottom section (differs by mode).
        bottomSection
    }

    // MARK: - Bottom Section (mode-specific)

    @ViewBuilder
    private var bottomSection: some View {
        switch mode {
        case .signUp:
            // "Already have an account? Sign In"
            HStack {
                Text(mode.switchPromptText)
                    .nunitoFont(size: 14, style: .medium)
                    .foregroundColor(.foregroundLightGray)
                Button(action: switchMode) {
                    Text(mode.switchActionTitle)
                        .nunitoFont(size: 16, style: .semiBold)
                        .foregroundColor(.dojoTurquoise)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, UIDevice.isRunningOnIPadHardware ? 0 : 13)

        case .signIn:
            // "New User? Sign Up" + "Continue without an account"
            VStack(spacing: UIDevice.isRunningOnIPadHardware ? 6 : 17) {
                HStack {
                    Text(mode.switchPromptText)
                        .nunitoFont(size: 14, style: .medium)
                        .foregroundColor(.foregroundLightGray)
                    Button(action: switchMode) {
                        Text(mode.switchActionTitle)
                            .nunitoFont(size: 16, style: .semiBold)
                            .foregroundColor(.dojoTurquoise)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, UIDevice.isRunningOnIPadHardware ? 0 : 13)

                HStack {
                    Button(action: continueAsGuest) {
                        Text("Continue without an account")
                            .nunitoFont(size: 14, style: .regular)
                            .foregroundColor(.foregroundLightGray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Step 2: Enter Code (shared)

    @ViewBuilder
    private var enterCodeContent: some View {
        // Show email as read-only with change option
        HStack {
            Text(email)
                .nunitoFont(size: 14, style: .medium)
                .foregroundColor(.foregroundLightGray)

            Button(action: {
                step = .enterEmail
                verificationCode = ""
                resendTimer?.invalidate()
            }) {
                Text("Change")
                    .nunitoFont(size: 14, style: .semiBold)
                    .foregroundColor(.dojoTurquoise)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 4)

        // Code Input (auto-verifies on 4th digit via onComplete)
        CodeInputView(code: $verificationCode, onComplete: verifyCode)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 4)

        // Resend / Verifying state
        HStack {
            if isLoading {
                Text("Verifying...")
                    .nunitoFont(size: 14, style: .medium)
                    .foregroundColor(.foregroundLightGray)
            } else if canResend {
                Button(action: resendCode) {
                    Text("Resend code")
                        .nunitoFont(size: 14, style: .semiBold)
                        .foregroundColor(.dojoTurquoise)
                }
            } else {
                Text("Resend code (\(resendCountdown)s)")
                    .nunitoFont(size: 14, style: .medium)
                    .foregroundColor(.foregroundLightGray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    // MARK: - Helper Methods

    private func requestCode() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            GlobalErrorManager.shared.error = .custom(message: "Please enter your email address.")
            return
        }

        isLoading = true
        Task {
            do {
                try await viewModel.requestVerificationCode(email: trimmedEmail)
                await MainActor.run {
                    isLoading = false
                    step = .enterCode
                    startResendCooldown()
                    print("📊 [AUTH:UI] Email -> enterCode step")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    GlobalErrorManager.shared.error = .custom(message: error.localizedDescription)
                    print("📊 [AUTH:UI] Email requestCode FAILED: \(error.localizedDescription)")
                }
            }
        }
    }

    private func verifyCode() {
        guard verificationCode.count == 4 else { return }

        isLoading = true
        viewModel.verifyCodeAndSignIn(email: email, code: verificationCode) { success, isNewUser in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    print("📊 [AUTH:UI] Email verify SUCCESS isNewUser=\(isNewUser)")
                    resendTimer?.invalidate()
                    SharedUserStorage.save(value: email, forKey: .lastUsedEmail)
                    handleSuccessfulAuth(isNewUser: isNewUser)
                } else {
                    // Clear the code so user can retry
                    verificationCode = ""
                    print("📊 [AUTH:UI] Email verify FAILED - clearing code")
                }
            }
        }
    }

    private func resendCode() {
        canResend = false
        isLoading = true

        Task {
            do {
                try await viewModel.requestVerificationCode(email: email)
                await MainActor.run {
                    isLoading = false
                    verificationCode = ""
                    startResendCooldown()
                    print("📊 [AUTH:UI] Email code RESENT successfully")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    canResend = true
                    GlobalErrorManager.shared.error = .custom(message: error.localizedDescription)
                }
            }
        }
    }

    private func startResendCooldown() {
        resendCountdown = 60
        canResend = false
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            DispatchQueue.main.async {
                if resendCountdown > 1 {
                    resendCountdown -= 1
                } else {
                    timer.invalidate()
                    canResend = true
                }
            }
        }
    }

    // MARK: - Post-Auth Navigation

    private func handleSuccessfulAuth(isNewUser: Bool = false) {
        navigateAfterAuth(isNewUser: isNewUser)
    }

    /// Unified post-auth: navigate to main. Post SelectTab for new users; log sign_in_completed for returning users.
    private func navigateAfterAuth(isNewUser: Bool) {
        if Auth.auth().currentUser != nil {
            DispatchQueue.main.async {
                print("📊 [AUTH:UI] Navigating to main view isNewUser=\(isNewUser)")
                appState.isAuthenticated = true
                appState.isGuest = false
                SharedUserStorage.save(value: false, forKey: .isGuest)
                navigationCoordinator.currentView = .main

                if isNewUser {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: NSNotification.Name("SelectTab"), object: 0)
                    }
                } else {
                    AnalyticsManager.shared.logEvent("sign_in_completed", parameters: nil)
                }
            }
            return
        }

        print("📊 [AUTH:UI] No authenticated user found after sign-in; defaulting to main view")
        appState.isAuthenticated = true
        appState.isGuest = false
        SharedUserStorage.save(value: false, forKey: .isGuest)
        navigationCoordinator.currentView = .main
        if !isNewUser {
            AnalyticsManager.shared.logEvent("sign_in_completed", parameters: nil)
        }
    }

    // MARK: - Guest Mode (signIn only)

    private func continueAsGuest() {
        print("📊 [AUTH:UI] Starting continueAsGuest flow with preserved Firebase user")

        authViewModel.setAppState(appState)
        authViewModel.switchToGuestMode()

        navigationCoordinator.configureForGuestMode()
        SubscriptionManager.shared.resetSubscriptionStatusForGuest()

        AnalyticsManager.shared.logEvent("continue_as_guest", parameters: [
            "method": "preserved_firebase_user"
        ])

        DispatchQueue.main.async {
            self.appState.isAuthenticated = true
            self.appState.isGuest = true
            self.appState.needsOnboarding = false
            self.navigationCoordinator.currentView = .guest
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.appState.objectWillChange.send()
        }
    }

    // MARK: - Identity Readiness (signUp only)

    private func waitForIdentityReady() {
        let currentUid = UserIdentityManager.shared.currentUserId
        print("IDENTITY_TRACE: [1] AuthenticationScreen.waitForIdentityReady called, currentUid=\(currentUid.isEmpty ? "EMPTY" : currentUid)")

        if UserIdentityManager.shared.isIdentityReady {
            isIdentityReady = true
            return
        }

        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            attempts += 1
            if UserIdentityManager.shared.isIdentityReady {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.isIdentityReady = true
                }
            } else if attempts > 25 {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.isIdentityReady = true
                }
            }
        }
    }

    // MARK: - Mode Switching

    private func switchMode() {
        if !email.isEmpty {
            SharedUserStorage.save(value: email, forKey: .lastUsedEmail)
        }
        switch mode {
        case .signUp:
            navigationCoordinator.currentView = .signIn(email: email)
        case .signIn:
            print("📊 [AUTH:UI] Navigating to SignUp view")
            navigationCoordinator.currentView = .signUp
        }
    }
}

// MARK: - Previews

#if DEBUG

// MARK: - Interactive Preview

private struct AuthInteractivePreview: View {
    let mode: Authentication.Mode

    @State private var email = ""
    @State private var code = ""
    @State private var step: EmailAuthStep = .enterEmail
    @State private var canResend = false
    @State private var countdown = 60

    var body: some View {
        ZStack(alignment: .top) {
            Color.backgroundDarkPurple.ignoresSafeArea()

            Image("onboardingSplash")
                .resizable()
                .scaledToFill()
                .frame(
                    width: UIScreen.main.bounds.width,
                    height: UIScreen.main.bounds.width * (376/395)
                )
                .clipped()
                .ignoresSafeArea(edges: .top)
                .overlay(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: Color.clear, location: 0.38),
                            .init(color: Color.backgroundDarkPurple, location: 0.8)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                AuthHeaderView(
                    subtitle: step == .enterEmail
                        ? mode.headerSubtitle
                        : "Enter the code sent to your email"
                )
                Spacer().frame(height: 26)

                VStack(spacing: 17) {
                    if step == .enterEmail {
                        HStack(spacing: 14) {
                            AuthServiceButton(iconName: "authGoogle", title: "Google") {}
                            AuthServiceButton(iconName: "authApple", title: "Apple") {}
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                        AuthDividerView(text: mode.dividerText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 4)

                        InputFieldView(
                            title: mode.emailFieldTitle,
                            isSecure: false,
                            text: $email,
                            textContentType: .username,
                            keyboardType: .emailAddress,
                            iconName: "inputEmail"
                        )
                        .frame(maxWidth: .infinity, alignment: .center)

                        PrimaryAuthButton(title: "Continue") {
                            if !email.isEmpty { step = .enterCode }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 13)

                        // Mode-specific bottom section
                        if mode == .signUp {
                            HStack {
                                Text(mode.switchPromptText)
                                    .nunitoFont(size: 14, style: .medium)
                                    .foregroundColor(.foregroundLightGray)
                                Text(mode.switchActionTitle)
                                    .nunitoFont(size: 16, style: .semiBold)
                                    .foregroundColor(.dojoTurquoise)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 13)
                        } else {
                            VStack(spacing: 17) {
                                HStack {
                                    Text(mode.switchPromptText)
                                        .nunitoFont(size: 14, style: .medium)
                                        .foregroundColor(.foregroundLightGray)
                                    Text(mode.switchActionTitle)
                                        .nunitoFont(size: 16, style: .semiBold)
                                        .foregroundColor(.dojoTurquoise)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 13)

                                Text("Continue without an account")
                                    .nunitoFont(size: 14, style: .regular)
                                    .foregroundColor(.foregroundLightGray)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    } else {
                        HStack {
                            Text(email)
                                .nunitoFont(size: 14, style: .medium)
                                .foregroundColor(.foregroundLightGray)
                            Button { step = .enterEmail; code = "" } label: {
                                Text("Change")
                                    .nunitoFont(size: 14, style: .semiBold)
                                    .foregroundColor(.dojoTurquoise)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                        CodeInputView(code: $code)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 4)

                        HStack {
                            if canResend {
                                Text("Resend code")
                                    .nunitoFont(size: 14, style: .semiBold)
                                    .foregroundColor(.dojoTurquoise)
                            } else {
                                Text("Resend code (\(countdown)s)")
                                    .nunitoFont(size: 14, style: .medium)
                                    .foregroundColor(.foregroundLightGray)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 9)
            }
            .padding(.horizontal, 52)
            .padding(.top, 244)
            .foregroundColor(.foregroundLightGray)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Static State Previews

private struct AuthStatePreview: View {
    let mode: Authentication.Mode
    let step: EmailAuthStep
    let email: String
    let code: String
    let isLoading: Bool
    let canResend: Bool
    let countdown: Int

    var body: some View {
        ZStack(alignment: .top) {
            Color.backgroundDarkPurple.ignoresSafeArea()

            Image("onboardingSplash")
                .resizable()
                .scaledToFill()
                .frame(
                    width: UIScreen.main.bounds.width,
                    height: UIScreen.main.bounds.width * (376/395)
                )
                .clipped()
                .ignoresSafeArea(edges: .top)
                .overlay(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: Color.clear, location: 0.38),
                            .init(color: Color.backgroundDarkPurple, location: 0.8)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                AuthHeaderView(
                    subtitle: step == .enterEmail
                        ? mode.headerSubtitle
                        : "Enter the code sent to your email"
                )
                Spacer().frame(height: 26)

                VStack(spacing: 17) {
                    if step == .enterEmail {
                        HStack(spacing: 14) {
                            AuthServiceButton(iconName: "authGoogle", title: "Google") {}
                            AuthServiceButton(iconName: "authApple", title: "Apple") {}
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                        AuthDividerView(text: mode.dividerText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 4)

                        InputFieldView(
                            title: mode.emailFieldTitle,
                            isSecure: false,
                            text: .constant(email),
                            textContentType: .username,
                            keyboardType: .emailAddress,
                            iconName: "inputEmail"
                        )
                        .frame(maxWidth: .infinity, alignment: .center)

                        PrimaryAuthButton(title: isLoading ? "Sending..." : "Continue", action: {})
                            .opacity(isLoading ? 0.6 : 1.0)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 13)

                        // Mode-specific bottom section
                        if mode == .signUp {
                            HStack {
                                Text(mode.switchPromptText)
                                    .nunitoFont(size: 14, style: .medium)
                                    .foregroundColor(.foregroundLightGray)
                                Text(mode.switchActionTitle)
                                    .nunitoFont(size: 16, style: .semiBold)
                                    .foregroundColor(.dojoTurquoise)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 13)
                        } else {
                            VStack(spacing: 17) {
                                HStack {
                                    Text(mode.switchPromptText)
                                        .nunitoFont(size: 14, style: .medium)
                                        .foregroundColor(.foregroundLightGray)
                                    Text(mode.switchActionTitle)
                                        .nunitoFont(size: 16, style: .semiBold)
                                        .foregroundColor(.dojoTurquoise)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 13)

                                Text("Continue without an account")
                                    .nunitoFont(size: 14, style: .regular)
                                    .foregroundColor(.foregroundLightGray)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    } else {
                        HStack {
                            Text(email)
                                .nunitoFont(size: 14, style: .medium)
                                .foregroundColor(.foregroundLightGray)
                            Text("Change")
                                .nunitoFont(size: 14, style: .semiBold)
                                .foregroundColor(.dojoTurquoise)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                        CodeInputView(code: .constant(code))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 4)

                        HStack {
                            if isLoading {
                                Text("Verifying...")
                                    .nunitoFont(size: 14, style: .medium)
                                    .foregroundColor(.foregroundLightGray)
                            } else if canResend {
                                Text("Resend code")
                                    .nunitoFont(size: 14, style: .semiBold)
                                    .foregroundColor(.dojoTurquoise)
                            } else {
                                Text("Resend code (\(countdown)s)")
                                    .nunitoFont(size: 14, style: .medium)
                                    .foregroundColor(.foregroundLightGray)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 9)
            }
            .padding(.horizontal, 52)
            .padding(.top, 244)
            .foregroundColor(.foregroundLightGray)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Sign Up Previews

#Preview("Sign Up — Interactive Flow") {
    AuthInteractivePreview(mode: .signUp)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign Up — Sending Code") {
    AuthStatePreview(mode: .signUp, step: .enterEmail, email: "user@example.com", code: "", isLoading: true, canResend: false, countdown: 60)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign Up — Code Partial") {
    AuthStatePreview(mode: .signUp, step: .enterCode, email: "user@example.com", code: "12", isLoading: false, canResend: false, countdown: 35)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign Up — Code Full") {
    AuthStatePreview(mode: .signUp, step: .enterCode, email: "user@example.com", code: "1234", isLoading: false, canResend: false, countdown: 20)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign Up — Verifying") {
    AuthStatePreview(mode: .signUp, step: .enterCode, email: "user@example.com", code: "1234", isLoading: true, canResend: false, countdown: 18)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign Up — Resend Available") {
    AuthStatePreview(mode: .signUp, step: .enterCode, email: "user@example.com", code: "", isLoading: false, canResend: true, countdown: 0)
        .withPreviewEnvironmentUnauthenticated()
}

// MARK: - Sign In Previews

#Preview("Sign In — Interactive Flow") {
    AuthInteractivePreview(mode: .signIn)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign In — Sending Code") {
    AuthStatePreview(mode: .signIn, step: .enterEmail, email: "user@example.com", code: "", isLoading: true, canResend: false, countdown: 60)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign In — Code Partial") {
    AuthStatePreview(mode: .signIn, step: .enterCode, email: "user@example.com", code: "12", isLoading: false, canResend: false, countdown: 35)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign In — Code Full") {
    AuthStatePreview(mode: .signIn, step: .enterCode, email: "user@example.com", code: "1234", isLoading: false, canResend: false, countdown: 20)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign In — Verifying") {
    AuthStatePreview(mode: .signIn, step: .enterCode, email: "user@example.com", code: "1234", isLoading: true, canResend: false, countdown: 18)
        .withPreviewEnvironmentUnauthenticated()
}

#Preview("Sign In — Resend Available") {
    AuthStatePreview(mode: .signIn, step: .enterCode, email: "user@example.com", code: "", isLoading: false, canResend: true, countdown: 0)
        .withPreviewEnvironmentUnauthenticated()
}

#endif
