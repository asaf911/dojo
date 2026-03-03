//
//  SideMenuProfileViewModel.swift
//  imagine
//
//  Created for Side Menu Profile Component
//

import SwiftUI
import Combine
import RevenueCat
import FirebaseAuth
import GoogleSignIn

final class SideMenuProfileViewModel: ObservableObject {
    @Published var userName: String?
    @Published var profileImageURL: URL?
    @Published var isSubscribed: Bool = false
    @Published var isTrial: Bool = false
    @Published var subscriptionStartDate: Date?
    @Published var trialEndDate: Date?
    
    private var cancellables = Set<AnyCancellable>()
    private let isPreview: Bool
    
    /// Static flag to prevent multiple simultaneous Google session restore attempts
    private static var hasAttemptedGoogleRestore = false
    private static var isRestoringGoogleSession = false
    
    init() {
        self.isPreview = false
        loadUserData()
        observeSubscriptionChanges()
    }
    
    /// Preview initializer for showing different states
    init(userName: String?, isSubscribed: Bool, isTrial: Bool = false, subscriptionStartDate: Date? = nil, trialEndDate: Date? = nil, profileImageURL: URL? = nil) {
        self.isPreview = true
        self.userName = userName
        self.profileImageURL = profileImageURL
        self.isSubscribed = isSubscribed
        self.isTrial = isTrial
        self.subscriptionStartDate = subscriptionStartDate
        self.trialEndDate = trialEndDate
    }
    
    // MARK: - Computed Properties
    
    var displayName: String {
        userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    var firstName: String {
        displayName.components(separatedBy: " ").first ?? displayName
    }
    
    var initials: String {
        let components = displayName.components(separatedBy: " ")
        if components.count >= 2,
           let first = components.first?.first,
           let last = components.last?.first {
            return "\(first)\(last)".uppercased()
        } else if let first = displayName.first {
            return String(first).uppercased()
        }
        return ""
    }
    
    var subscriptionStatusText: String {
        if isSubscribed {
            if isTrial {
                return trialStatusText
            }
            if let date = subscriptionStartDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM yyyy"
                return "Premium Member since \(formatter.string(from: date))"
            }
            return "Premium Member"
        }
        return "Free Plan"
    }
    
    private var trialStatusText: String {
        guard let endDate = trialEndDate else {
            return "Trial"
        }
        
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day], from: now, to: endDate)
        let daysLeft = components.day ?? 0
        
        if daysLeft <= 1 {
            return "Trial - Last day!"
        } else {
            return "Trial - \(daysLeft) days left"
        }
    }
    
    // MARK: - Private Methods
    
    private func loadUserData() {
        guard !isPreview else { return }
        userName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)
        
        // Load profile image URL if available (from storage - previously fetched)
        if let imageURLString = SharedUserStorage.retrieve(forKey: .userProfileImageURL, as: String.self),
           let url = URL(string: imageURLString) {
            profileImageURL = url
            print("🖼️ PROFILE_IMAGE: Loaded from storage")
        } else {
            // No stored URL - check if we need to fetch from Google (one-time)
            tryRestoreGoogleProfilePhotoIfNeeded()
        }
        
        isSubscribed = SubscriptionManager.shared.isUserSubscribed
        fetchSubscriptionDate()
    }
    
    /// Attempts to restore Google session to fetch profile photo - only once per app session
    private func tryRestoreGoogleProfilePhotoIfNeeded() {
        // Skip if already attempted or currently restoring
        guard !Self.hasAttemptedGoogleRestore,
              !Self.isRestoringGoogleSession else {
            return
        }
        
        // Check if user is signed in with Google
        guard let currentUser = Auth.auth().currentUser,
              currentUser.providerData.contains(where: { $0.providerID == "google.com" }) else {
            return
        }
        
        // Mark as attempting (prevents duplicate calls)
        Self.isRestoringGoogleSession = true
        Self.hasAttemptedGoogleRestore = true
        
        print("🖼️ PROFILE_IMAGE: Restoring Google session for profile photo...")
        
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            DispatchQueue.main.async {
                Self.isRestoringGoogleSession = false
                
                if let error = error {
                    print("🖼️ PROFILE_IMAGE: Restore failed - \(error.localizedDescription)")
                    return
                }
                
                guard let imageURL = user?.profile?.imageURL(withDimension: 200) else {
                    print("🖼️ PROFILE_IMAGE: No profile image available")
                    return
                }
                
                print("🖼️ PROFILE_IMAGE: Success! Saved profile photo URL")
                self?.profileImageURL = imageURL
                SharedUserStorage.save(value: imageURL.absoluteString, forKey: .userProfileImageURL)
            }
        }
    }
    
    private func observeSubscriptionChanges() {
        guard !isPreview else { return }
        SubscriptionManager.shared.$isUserSubscribed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subscribed in
                self?.isSubscribed = subscribed
                if subscribed {
                    self?.fetchSubscriptionDate()
                } else {
                    self?.subscriptionStartDate = nil
                    self?.trialEndDate = nil
                    self?.isTrial = false
                }
            }
            .store(in: &cancellables)
    }
    
    private func fetchSubscriptionDate() {
        guard !isPreview else { return }
        guard let customerInfo = SubscriptionManager.shared.customerInfo,
              let entitlement = customerInfo.entitlements.active.first?.value else {
            return
        }
        subscriptionStartDate = entitlement.originalPurchaseDate
        isTrial = entitlement.periodType == .trial
        
        if isTrial {
            trialEndDate = entitlement.expirationDate
        } else {
            trialEndDate = nil
        }
    }
    
    func refresh() {
        loadUserData()
    }
}
