//
//  SubscriptionView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-03-XX
//

import SwiftUI
import RevenueCat
import WebKit

enum SubscriptionViewContext {
    case sheet
    case tab
}

@available(iOS 15.0, *)
struct SubscriptionView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator  // Use shared navigation coordinator
    @State private var selectedPackage: Package? = nil
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfUse = false
    @Environment(\.presentationMode) var presentationMode

    var source: String // Track where this view was opened from
    var context: SubscriptionViewContext

    @State private var viewAppearTime: Date?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Replace the background with our solid color.
            Color.backgroundDarkPurple.ignoresSafeArea()
            
            // Conditional content based on subscription status.
            if subscriptionManager.isUserSubscribed {
                thankYouView
            } else {
                subscriptionContent
            }

            // Close button for sheet context.
            if context == .sheet {
                closeButton
            }
            
            // Overlay the mute/unmute control.
            MuteUnmuteView()
                .padding()
        }
        .onFirstAppear {
            // Track this screen.
            viewAppearTime = Date()
            AnalyticsManager.shared.logEvent("subscription_view_loaded", parameters: ["is_subscribed": subscriptionManager.isUserSubscribed, "source": source])
            subscriptionManager.fetchOfferings()
            subscriptionManager.refreshSubscriptionStatus()
        }
        .onDisappear {
            // Track exit and fade out the onboarding background sound.
            if let appearTime = viewAppearTime {
                let duration = Date().timeIntervalSince(appearTime)
                AnalyticsManager.shared.logEvent("subscription_view_duration", parameters: ["duration": duration, "source": source])
            }
            // Fade out the onboarding background sound when the subscription view is closed.
            GeneralBackgroundMusicController.shared.fadeOutMusic()
        }
        // Present WebView for Privacy Policy and Terms of Use.
        .sheet(isPresented: $showPrivacyPolicy) {
            WebViewScreen(url: URL(string: "https://www.imaginemeditationapp.com/privacy")!, screenName: "PrivacyPolicyWebView")
        }
        .sheet(isPresented: $showTermsOfUse) {
            WebViewScreen(url: URL(string: "https://www.imaginemeditationapp.com/terms")!, screenName: "TermsOfUseWebView")
        }
    }

    // MARK: - Subviews

    private var thankYouView: some View {
        VStack {
            Spacer()
            Text("Thank you for subscribing!")
                .nunitoFont(size: 24, style: .bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding()
    }

    private var subscriptionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if context == .sheet {
                headerView
            }
            valuePropositionView
            OffersView(offerings: subscriptionManager.offerings, selectedPackage: $selectedPackage)
            subscribeButton
            footerTextView
        }
        .padding(.horizontal, context == .sheet ? 37 : 0)
        .padding(.top, context == .sheet ? 20 : 16)
        .foregroundColor(.foregroundLightGray)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var closeButton: some View {
        Button(action: {
            AnalyticsManager.shared.logEvent("subscription_view_closed", parameters: ["source": source])
            // Always route to main view regardless of subscription state.
            navigationCoordinator.currentView = .main
            presentationMode.wrappedValue.dismiss()
        }) {
            Image(systemName: "xmark")
                .foregroundColor(.white)
                .padding()
        }
        .padding()
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Get full Acces to ")
                .nunitoFont(size: 28, style: .bold)
             + Text("Dojo")
                .allenoireFont(size: 28))
                .foregroundColor(.white)
        }
        .padding(.top, 60)
    }

    private var valuePropositionView: some View {
        let valuePropositions = [
            "Unlock Premium Meditations",
            "Exclusive New Content",
            "Cancel Anytime, Hassle-Free"
        ]

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(valuePropositions, id: \.self) { sentence in
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checkmark")
                        .foregroundColor(.dojoTurquoise)
                        .font(.system(size: 15))
                    Text(sentence)
                        .nunitoFont(size: 18, style: .medium)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.top, context == .sheet ? 34 : 16)
    }

    private var subscribeButton: some View {
        Button(action: {
            if let package = selectedPackage {
                AnalyticsManager.shared.logEvent("subscribe_button_clicked", parameters: ["selected_package": package.identifier, "source": source])
                // Updated purchase call: remove extra source parameter.
                subscriptionManager.purchase(package: package) { success in
                    if success {
                        logger.eventMessage("Purchase successful")
                    } else {
                        AnalyticsManager.shared.logEvent("subscription_failed_or_cancelled", parameters: ["package_id": package.identifier, "error_message": "Purchase failed or cancelled", "source": source])
                        logger.eventMessage("Purchase failed or cancelled")
                    }
                }
            }
        }) {
            Text("Start Your 7-Day Free Trial Now")
                .nunitoFont(size: 16, style: .bold)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .foregroundColor(.foregroundDarkBlue)
                .background(Color.dojoTurquoise)
                .cornerRadius(25)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .disabled(selectedPackage == nil)
        .padding(.top, context == .sheet ? 20 : 32)
    }

    private var footerTextView: some View {
        let packagePrice = selectedPackage?.localizedPriceString ?? "Price"
        let packageName = selectedPackage?.storeProduct.localizedTitle ?? "Package"

        return VStack {
            Text("Try 7 Days Free. After that, only \(packagePrice) / \(packageName).\nAuto-renew. Cancel anytime.")
                .nunitoFont(size: 12, style: .medium)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)

            HStack {
                Button(action: {
                    showTermsOfUse.toggle()
                }) {
                    Text("Terms of Use")
                        .nunitoFont(size: 14, style: .medium)
                        .foregroundColor(.white)
                }

                Text(" | ")
                    .foregroundColor(.white)

                Button(action: {
                    showPrivacyPolicy.toggle()
                }) {
                    Text("Privacy Policy")
                        .nunitoFont(size: 14, style: .medium)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

@available(iOS 15.0, *)
struct OffersView: View {
    var offerings: Offerings?
    @Binding var selectedPackage: Package?
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let offerings = offerings {
                ForEach(offerings.current?.availablePackages ?? [], id: \.identifier) { package in
                    subscriptionOptionView(package: package)
                        .background(backgroundColorForPackage(package))
                        .cornerRadius(20)
                        .onTapGesture {
                            selectedPackage = package
                            AnalyticsManager.shared.logEvent("subscription_package_selected", parameters: ["package_id": package.identifier, "package_name": package.storeProduct.localizedTitle, "price": package.localizedPriceString])
                        }
                }
            } else {
                Text("Loading offerings...")
                    .nunitoFont(size: 18)
                    .foregroundColor(.textForegroundGray)
                    .padding(20)
            }
        }
        .padding(.top, 72)
        .onFirstAppear {
            if selectedPackage == nil, let firstPackage = offerings?.current?.availablePackages.first {
                selectedPackage = firstPackage
            }
        }
    }

    private func subscriptionOptionView(package: Package) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(package.storeProduct.localizedTitle)
                .nunitoFont(size: 16, style: .extraBold)
                .foregroundColor(textColorForPackage(package))
            HStack {
                Text(package.localizedPriceString)
                    .nunitoFont(size: 15)
                    .foregroundColor(textColorForPackage(package))
                Text(package.storeProduct.localizedDescription)
                    .nunitoFont(size: 15)
                    .foregroundColor(textColorForPackage(package))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: 100, alignment: .bottomLeading)
    }

    private func backgroundColorForPackage(_ package: Package) -> some View {
        Group {
            if selectedPackage?.identifier == package.identifier {
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.55, green: 0.33, blue: 1), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.88, green: 0.28, blue: 0.64), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: -0.18, y: 0.4),
                    endPoint: UnitPoint(x: 0.41, y: 1.15)
                )
                .cornerRadius(20)
            } else {
                Color.white
            }
        }
    }

    private func textColorForPackage(_ package: Package) -> Color {
        if selectedPackage?.identifier == package.identifier {
            return .white
        } else {
            return .backgroundDarkPurple
        }
    }
}

@available(iOS 15.0, *)
struct WebViewScreen: View {
    let url: URL
    let screenName: String

    var body: some View {
        WebView(url: url)
            .onFirstAppear {
                // Empty onFirstAppear
            }
            .onDisappear {
                // Empty onDisappear
            }
    }
}

@available(iOS 15.0, *)
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
}

@available(iOS 15.0, *)
struct SubscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            let unsubscribedManager = SubscriptionManager(isUserSubscribed: false)
            let subscribedManager = SubscriptionManager(isUserSubscribed: true)

            SubscriptionView(source: "Preview_Sheet_Unsubscribed", context: .sheet)
                .environmentObject(unsubscribedManager)
                .previewDisplayName("Sheet Unsubscribed")

            SubscriptionView(source: "Preview_Tab_Unsubscribed", context: .tab)
                .environmentObject(unsubscribedManager)
                .previewDisplayName("Tab Unsubscribed")

            SubscriptionView(source: "Preview_Sheet_Subscribed", context: .sheet)
                .environmentObject(subscribedManager)
                .previewDisplayName("Sheet Subscribed")

            SubscriptionView(source: "Preview_Tab_Subscribed", context: .tab)
                .environmentObject(subscribedManager)
                .previewDisplayName("Tab Subscribed")
        }
    }
}
