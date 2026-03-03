//
//  SideMenuProfileView.swift
//  imagine
//
//  Created for Side Menu Profile Component
//

import SwiftUI

struct SideMenuProfileView: View {
    @StateObject private var viewModel: SideMenuProfileViewModel
    var onTap: (() -> Void)? = nil
    
    init(viewModel: SideMenuProfileViewModel? = nil, onTap: (() -> Void)? = nil) {
        self._viewModel = StateObject(wrappedValue: viewModel ?? SideMenuProfileViewModel())
        self.onTap = onTap
    }
    
    // MARK: - Avatar with Initials (fallback when no profile image)
    
    private var avatarWithInitials: some View {
        Circle()
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.73, green: 0.53, blue: 0.99), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.41, green: 0.19, blue: 0.61), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
            )
            .frame(width: 40, height: 40)
            .overlay(
                Text(viewModel.initials)
                    .font(Font.custom("Nunito", size: 16).weight(.semibold))
                    .foregroundColor(.white)
            )
    }
    
    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 0) {
                // Top border
                Rectangle()
                    .fill(Color.backgroundNavy)
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                
                HStack(spacing: 12) {
                    // Avatar circle with profile image or initials fallback
                    if let imageURL = viewModel.profileImageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            case .failure, .empty:
                                avatarWithInitials
                            @unknown default:
                                avatarWithInitials
                            }
                        }
                        .frame(width: 40, height: 40)
                    } else {
                        avatarWithInitials
                    }
                    
                    // Name and subscription status
                    VStack(alignment: .leading, spacing: 2) {
                        if !viewModel.displayName.isEmpty {
                            Text(viewModel.displayName)
                                .font(Font.custom("Nunito", size: 16))
                                .foregroundColor(Constants.lightGrey)
                                .lineLimit(1)
                        }
                        
                        Text(viewModel.subscriptionStatusText)
                            .font(Font.custom("Nunito", size: 12).weight(.medium))
                            .foregroundColor(Color(red: 0.88, green: 0.88, blue: 0.88).opacity(0.75))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.leading, 36) // 24px side menu padding + 12px space before circle
                .frame(height: 72)
                
                // Bottom border
                Rectangle()
                    .fill(Color.backgroundNavy)
                    .frame(height: 1)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .onAppear {
            viewModel.refresh()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("All User States") {
    let sideMenuBackground = Color(red: 0.1, green: 0.1, blue: 0.18)
    
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            // Section: With Name
            Text("WITH NAME")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal, 24)
            
            VStack(spacing: 0) {
                // Free user with name
                previewRow(
                    label: "Free Plan",
                    viewModel: SideMenuProfileViewModel(
                        userName: "John Doe",
                        isSubscribed: false
                    )
                )
                
                // Trial user - multiple days left
                previewRow(
                    label: "Trial (5 days left)",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Sarah Miller",
                        isSubscribed: true,
                        isTrial: true,
                        trialEndDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())
                    )
                )
                
                // Trial user - last day
                previewRow(
                    label: "Trial (Last day)",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Jordan Lee",
                        isSubscribed: true,
                        isTrial: true,
                        trialEndDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())
                    )
                )
                
                // Premium user with date
                previewRow(
                    label: "Premium (with date)",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Michael Chen",
                        isSubscribed: true,
                        isTrial: false,
                        subscriptionStartDate: Calendar.current.date(byAdding: .month, value: -6, to: Date())
                    )
                )
                
                // Premium user without date
                previewRow(
                    label: "Premium (no date)",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Emma Wilson",
                        isSubscribed: true,
                        isTrial: false,
                        subscriptionStartDate: nil
                    )
                )
            }
            
            // Section: Without Name
            Text("WITHOUT NAME")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            
            VStack(spacing: 0) {
                // Free user without name
                previewRow(
                    label: "Free Plan",
                    viewModel: SideMenuProfileViewModel(
                        userName: nil,
                        isSubscribed: false
                    )
                )
                
                // Trial user without name
                previewRow(
                    label: "Trial",
                    viewModel: SideMenuProfileViewModel(
                        userName: nil,
                        isSubscribed: true,
                        isTrial: true,
                        trialEndDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())
                    )
                )
                
                // Premium user without name
                previewRow(
                    label: "Premium",
                    viewModel: SideMenuProfileViewModel(
                        userName: nil,
                        isSubscribed: true,
                        isTrial: false,
                        subscriptionStartDate: Calendar.current.date(byAdding: .year, value: -1, to: Date())
                    )
                )
            }
            
            // Section: With Profile Image (Google Sign-In)
            Text("WITH PROFILE IMAGE")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            
            VStack(spacing: 0) {
                // Google user with profile image - Premium
                previewRow(
                    label: "Google User (Premium)",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Alex Thompson",
                        isSubscribed: true,
                        isTrial: false,
                        subscriptionStartDate: Calendar.current.date(byAdding: .month, value: -3, to: Date()),
                        profileImageURL: URL(string: "https://i.pravatar.cc/200?img=12")
                    )
                )
                
                // Google user with profile image - Trial
                previewRow(
                    label: "Google User (Trial)",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Jamie Rodriguez",
                        isSubscribed: true,
                        isTrial: true,
                        trialEndDate: Calendar.current.date(byAdding: .day, value: 4, to: Date()),
                        profileImageURL: URL(string: "https://i.pravatar.cc/200?img=32")
                    )
                )
                
                // Google user with profile image - Free
                previewRow(
                    label: "Google User (Free)",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Sam Parker",
                        isSubscribed: false,
                        profileImageURL: URL(string: "https://i.pravatar.cc/200?img=52")
                    )
                )
            }
            
            // Section: Edge Cases
            Text("EDGE CASES")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            
            VStack(spacing: 0) {
                // Long name
                previewRow(
                    label: "Long Name",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Christopher Alexander",
                        isSubscribed: true,
                        isTrial: false,
                        subscriptionStartDate: Date()
                    )
                )
                
                // Single name
                previewRow(
                    label: "Single Name",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Madonna",
                        isSubscribed: true,
                        isTrial: false
                    )
                )
                
                // Trial without end date (fallback)
                previewRow(
                    label: "Trial (no end date)",
                    viewModel: SideMenuProfileViewModel(
                        userName: "Test User",
                        isSubscribed: true,
                        isTrial: true,
                        trialEndDate: nil
                    )
                )
            }
        }
        .padding(.vertical, 24)
    }
    .background(sideMenuBackground.ignoresSafeArea())
}

@ViewBuilder
private func previewRow(label: String, viewModel: SideMenuProfileViewModel) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color.white.opacity(0.5))
            .padding(.horizontal, 24)
        
        SideMenuProfileView(viewModel: viewModel)
    }
}
#endif
