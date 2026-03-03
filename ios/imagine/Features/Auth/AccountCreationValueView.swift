//
//  AccountCreationValueView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-04-08
//

import SwiftUI

struct AccountCreationValueView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var appState: AppState
    var source: String = "generic"
    
    @State private var shouldNavigateToSignUp = false

    var body: some View {
        ZStack(alignment: .top) {
            // Background split:
            // Top 306 pixels: linear gradient from backgroundTopLightPurple to backgroundDarkPurple.
            // Remainder: solid backgroundDarkPurple.
            VStack(spacing: 0) {
                LinearGradient(
                    gradient: Gradient(stops: [
                        Gradient.Stop(color: Color.backgroundTopLightPurple, location: -1),
                        Gradient.Stop(color: Color.backgroundDarkPurple, location: 0.6)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 306)
                
                Color.backgroundDarkPurple
            }
            .ignoresSafeArea()
            
            // Content overlay
            VStack(alignment: .leading, spacing: UIDevice.isRunningOnIPadHardware ? 10 : 20) {
                Text("Get the most out of Dojo")
                    .allenoireFont(size: 36)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.white)
                    .baselineOffset(-2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer().frame(height: UIDevice.isRunningOnIPadHardware ? 5 : 10)
                
                VStack(alignment: .leading, spacing: UIDevice.isRunningOnIPadHardware ? 15.5 : 31) {
                    AccountValuePoint(
                        text: "Track your meditation progress over time and maintain your streaks"
                    )
                    AccountValuePoint(
                        text: "Get personalized session recommendations based on your practice history and preferences"
                    )
                    AccountValuePoint(
                        text: "Save your meditation history and settings securely, so they're always available when you sign in"
                    )
                }

                Spacer()
            }
            .padding(.leading, 47)
            .padding(.trailing, 39)
            .padding(.top, UIDevice.isRunningOnIPadHardware ? 25 : 50)
        }
        // Use the onboarding extension to overlay the continue button
        .continueButtonOverlay {
            VStack(spacing: UIDevice.isRunningOnIPadHardware ? 8 : 16) {
                LegacyContinueButton(text: "Create your account", action: {
                    // Log event for analytics
                    AnalyticsManager.shared.logEvent("account_creation_button_tapped", parameters: [
                        "source": source,
                        "current_view": "\(navigationCoordinator.currentView)",
                        "is_guest": appState.isGuest,
                        "is_authenticated": appState.isAuthenticated
                    ])
                    
                    print("AccountCreationValueView: Create Account button tapped")
                    print("AccountCreationValueView: Current navigation state: \(navigationCoordinator.currentView)")
                    print("AccountCreationValueView: AppState - isAuthenticated: \(appState.isAuthenticated), isGuest: \(appState.isGuest)")
                    
                    // CRITICAL: Reset authentication state for proper SignUp flow
                    // Guest users need to be in unauthenticated state to access AuthenticationScreen
                    print("AccountCreationValueView: Resetting authentication state for SignUp flow")
                    appState.isAuthenticated = false
                    appState.isGuest = false
                    
                    // Set flag to trigger navigation after dismissal
                    shouldNavigateToSignUp = true
                    
                    // Dismiss the sheet - navigation will happen in onDisappear
                    presentationMode.wrappedValue.dismiss()
                })
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Continue without an account")
                        .nunitoFont(size: 16, style: .medium)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, UIDevice.isRunningOnIPadHardware ? 2 : 4)
            }
            .padding(.horizontal, 30)
        }
        .onAppear {
            AnalyticsManager.shared.logEvent("account_creation_screen_viewed", parameters: [
                "screen_name": "value_proposition",
                "source": source
            ])
        }
        .onDisappear {
            // Handle navigation after sheet dismissal
            if shouldNavigateToSignUp {
                print("AccountCreationValueView: onDisappear - navigating to AuthenticationScreen")
                print("AccountCreationValueView: Current appState before navigation - isAuthenticated: \(appState.isAuthenticated), isGuest: \(appState.isGuest), needsOnboarding: \(appState.needsOnboarding)")
                
                // Small delay to ensure view hierarchy is stable
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("AccountCreationValueView: Executing navigation to AuthenticationScreen")
                    print("AccountCreationValueView: About to set currentView from \(navigationCoordinator.currentView) to .signUp")
                    
                    // Ensure we're in the right state for signup
                    // Don't change authentication status, but ensure we can navigate to signup
                    navigationCoordinator.currentView = .signUp
                    
                    print("AccountCreationValueView: Navigation completed to: \(navigationCoordinator.currentView)")
                    print("AccountCreationValueView: appState after navigation - isAuthenticated: \(appState.isAuthenticated), isGuest: \(appState.isGuest), needsOnboarding: \(appState.needsOnboarding)")
                    
                    // Log successful navigation
                    AnalyticsManager.shared.logEvent("guest_to_signup_navigation_executed", parameters: [
                        "new_view": "\(navigationCoordinator.currentView)",
                        "is_guest": appState.isGuest,
                        "is_authenticated": appState.isAuthenticated
                    ])
                    
                    // Force a view update to ensure AuthenticationScreen appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        print("AccountCreationValueView: Final verification - navigationCoordinator.currentView: \(navigationCoordinator.currentView)")
                    }
                }
            }
        }
    }
}

struct AccountValuePoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image("checkmarkIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(.dojoTurquoise)
                .padding(2)
            Text(text)
                .nunitoFont(size: 18, style: .medium)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct AccountCreationValueView_Previews: PreviewProvider {
    static var previews: some View {
        AccountCreationValueView(viewModel: AuthViewModel())
            .environmentObject(NavigationCoordinator())
            .environmentObject(AppState())
            .environmentObject(GlobalErrorManager.shared)
            .preferredColorScheme(.dark)
    }
} 
