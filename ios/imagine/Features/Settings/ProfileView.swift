//
//  ProfileView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-03-27
//  Updated to remove the Stats tab (default tab is now Account)
//
import SwiftUI

enum ProfileTab {
    case account
    case history
}

struct ProfileView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var selectedTab: ProfileTab = .account

    @Binding var showCommunitySheet: Bool
    @Binding var source: String?
    
    // Use presentationMode for the custom back button.
    @Environment(\.presentationMode) var presentationMode

    let userName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    var body: some View {
        ZStack {
            Color.backgroundNavy
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Use the unified header with back button
                UnifiedHeaderView(
                    title: profileTitle(),
                    subtitle: nil,
                    showMenuButton: false,
                    backAction: { presentationMode.wrappedValue.dismiss() },
                    showBackButton: true
                ) {
                    HeaderControlsView()
                }
                
                HStack(spacing: 16) {
                    // Account tab
                    FilterOptionView(
                        text: "Account",
                        isSelected: selectedTab == .account,
                        action: { selectedTab = .account },
                        isDurationFilter: false,
                        source: "ProfileView"
                    )
                    
                    // History tab
                    FilterOptionView(
                        text: "History",
                        isSelected: selectedTab == .history,
                        action: { selectedTab = .history },
                        isDurationFilter: false,
                        source: "ProfileView"
                    )
                    
                    Spacer()
                }
                .padding(.horizontal, 26)
                .padding(.top, 26)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if selectedTab == .account {
                            SettingsView(authViewModel: authViewModel)
                                .environmentObject(navigationCoordinator)
                        } else if selectedTab == .history {
                            HistoryView()
                        }
                        Spacer().frame(height: 84)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 26)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .background(InteractivePopGestureSetter())
        .onFirstAppear {
            // Empty onFirstAppear
        }
        .onDisappear {
            // Empty onDisappear
        }
    }
    
    // MARK: - Header Title
    private func profileTitle() -> String {
        if let name = userName, !name.isEmpty {
            let firstName = name.components(separatedBy: " ").first ?? name
            return "Your Dojo, \(firstName)"
        } else {
            return "Your Dojo"
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    @State static var showCommunitySheet = false
    @State static var source: String? = nil

    static var previews: some View {
        ProfileView(
            authViewModel: AuthViewModel(),
            showCommunitySheet: $showCommunitySheet,
            source: $source
        )
        .environmentObject(NavigationCoordinator())
        .environmentObject(SubscriptionManager(isUserSubscribed: false))
    }
}
