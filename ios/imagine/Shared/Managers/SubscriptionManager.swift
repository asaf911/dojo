import Foundation
import RevenueCat
import Combine
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

class SubscriptionManager: NSObject, ObservableObject, PurchasesDelegate {
    static let shared = SubscriptionManager()

    @Published private(set) var offerings: Offerings?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isUserSubscribed: Bool = false

    /// Returns true if user must see subscription before playing (post-first-session, not subscribed)
    var shouldGatePlay: Bool {
        let hasCompleted = SharedUserStorage.retrieve(forKey: .hasCompletedFirstSession, as: Bool.self) ?? false
        return hasCompleted && !isUserSubscribed
    }

    #if DEBUG
    /// Log gate state for debugging. Call when play is blocked.
    func logGateState() {
        let hasCompleted = SharedUserStorage.retrieve(forKey: .hasCompletedFirstSession, as: Bool.self) ?? false
        print("📊 [SUBSCRIPTION_GATE] hasCompleted=\(hasCompleted) isSubscribed=\(isUserSubscribed)")
    }
    #else
    func logGateState() {}
    #endif
    
    // Track migration state for better resilience
    private var isMigrationInProgress: Bool = false
    private var migrationGuestId: String?

    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        setupBindings()
        fetchOfferings()
        refreshSubscriptionStatus()
        
        // Set up RevenueCat delegate for real-time updates
        Purchases.shared.delegate = self
        
        // Check for interrupted migrations on app start
        checkForPendingMigrations()

        // Migrate existing users: if they have completed sessions, mark hasCompletedFirstSession
        migrateHasCompletedFirstSession()
    }

    /// One-time migration: users with session count > 0 should have hasCompletedFirstSession = true
    private func migrateHasCompletedFirstSession() {
        guard SharedUserStorage.retrieve(forKey: .hasCompletedFirstSession, as: Bool.self) == nil else { return }
        guard StatsManager.shared.getSessionCount() > 0 else { return }
        SharedUserStorage.save(value: true, forKey: .hasCompletedFirstSession)
        logger.eventMessage("SubscriptionManager: Migrated hasCompletedFirstSession for existing user")
    }
    
    init(isUserSubscribed: Bool) {
        super.init()
        self.isUserSubscribed = isUserSubscribed
    }

    private func setupBindings() {
        refreshSubscriptionStatus()
        
        // Listen for Firebase auth state changes to refresh subscription status
        Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            guard let self = self else { return }
            if let user = user {
                logger.eventMessage("User state changed: \(user.uid)")
                // Simply refresh subscription status - RevenueCat handles user transitions automatically
                self.refreshSubscriptionStatus()
            } else {
                logger.eventMessage("User signed out - refreshing subscription status")
                self.refreshSubscriptionStatus()
            }
        }
    }
    
    // Add a method to check for pending migrations (app restarts during migration)
    private func checkForPendingMigrations() {
        if SharedUserStorage.retrieve(forKey: .migrationInProgress, as: Bool.self) == true {
            logger.eventMessage("Found pending migration from previous session")
            
            // Check if we have the necessary data
            if let guestId = SharedUserStorage.retrieve(forKey: .previousGuestId, as: String.self),
               let currentUser = Auth.auth().currentUser {
                
                logger.eventMessage("Resuming interrupted migration from guest ID: \(guestId) to user ID: \(currentUser.uid)")
                
                // Resume migration
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.migrateSubscriptionFromGuest(guestId, userId: currentUser.uid)
                }
            } else {
                // Can't resume, clear flags
                logger.eventMessage("Cannot resume migration, missing data. Clearing flags.")
                SharedUserStorage.delete(forKey: .migrationInProgress)
                SharedUserStorage.delete(forKey: .previousGuestId)
            }
        }
    }
    
    // Handle account creation notification
    @objc private func handleAccountCreation(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let userId = userInfo["userId"] as? String,
           let previousGuestId = userInfo["previousGuestId"] as? String {
            
            logger.eventMessage("Received account creation notification, triggering migration")
            migrateSubscriptionFromGuest(previousGuestId, userId: userId)
        }
    }

    // MARK: - Subscription Type Helpers

    /// Derives subscription type from a RevenueCat Package (canonical source).
    static func subscriptionType(from package: Package) -> String {
        switch package.packageType {
        case .annual:       return "yearly"
        case .monthly:      return "monthly"
        default:
            let id = package.storeProduct.productIdentifier.lowercased()
            if id.contains("monthly") { return "monthly" }
            if id.contains("yearly") || id.contains("annual") { return "yearly" }
            return "unknown"
        }
    }

    /// Derives subscription type from a product identifier string (fallback for contexts without a Package).
    static func subscriptionType(fromProductId id: String) -> String {
        let lowered = id.lowercased()
        if lowered.contains("monthly") { return "monthly" }
        if lowered.contains("yearly") || lowered.contains("annual") { return "yearly" }
        return "unknown"
    }

    // MARK: - Offerings

    func fetchOfferings() {
        Purchases.shared.getOfferings { [weak self] (offerings, error) in
            if let offerings = offerings {
                self?.offerings = offerings
            } else {
                logger.errorMessage("Error fetching offerings: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    func fetchCustomerInfo() {
        Purchases.shared.getCustomerInfo { [weak self] (customerInfo, error) in
            if let customerInfo = customerInfo {
                logger.eventMessage("CustomerInfo fetched: \(customerInfo)")
                self?.updateSubscriptionStatus(customerInfo: customerInfo)
            } else {
                logger.errorMessage("Error fetching customer info: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    func purchase(package: Package, completion: @escaping (Bool) -> Void) {
        Purchases.shared.purchase(package: package) { [weak self] (transaction, customerInfo, error, userCancelled) in
            guard let self = self else { return }
            if let error = error {
                logger.eventMessage("Purchase failed: \(error.localizedDescription)")
                AnalyticsManager.shared.logEvent("subscription_failed_or_cancelled", parameters: [
                    "package_id": package.identifier,
                    "error_message": error.localizedDescription
                ])
                completion(false)
            } else if let customerInfo = customerInfo {
                self.updateSubscriptionStatus(customerInfo: customerInfo)

                let subscriptionType = Self.subscriptionType(from: package)
                let activeEntitlement = customerInfo.entitlements.active.values.first
                let isTrial = activeEntitlement?.periodType == .trial
                    || activeEntitlement?.periodType == .intro

                // Fire exactly one event: trial_started OR subscription_success.
                // Revenue is tracked server-side by RevenueCat — these are non-revenue funnel signals.
                if isTrial {
                    let trialDays = package.storeProduct.introductoryDiscount?.subscriptionPeriod.value ?? 0
                    AnalyticsManager.shared.logEvent("trial_started", parameters: [
                        "package_id": package.identifier,
                        "subscription_type": subscriptionType,
                        "trial_duration_days": trialDays
                    ])
                } else {
                    AnalyticsManager.shared.logEvent("subscription_success", parameters: [
                        "package_id": package.identifier,
                        "subscription_type": subscriptionType,
                        "localized_price": package.localizedPriceString
                    ])
                }

                // Persist periodType for deferred trial→paid detection (see checkForTrialConversion).
                let periodStr = isTrial ? "trial" : "normal"
                SharedUserStorage.save(value: periodStr, forKey: .lastKnownPeriodType)

                if SenseiOnboardingState.shared.isComplete {
                    AnalyticsManager.shared.logEvent("ai_onboarding_subscription_success", parameters: [
                        "steps_completed": SenseiOnboardingState.shared.stepsCompletedBeforeExit,
                        "completed_meditation": SenseiOnboardingState.shared.completedMeditation
                    ])
                }

                completion(!userCancelled)
            } else {
                completion(false)
            }
        }
    }
    
    private func updateSubscriptionStatus(customerInfo: CustomerInfo?) {
        let previousStatus = self.isUserSubscribed
        
        guard let customerInfo = customerInfo else {
            self.isUserSubscribed = false
            SharedUserStorage.save(value: false, forKey: .isUserSubscribed)
            SharedUserStorage.delete(forKey: .lastKnownPeriodType)
            logger.eventMessage("Subscription status updated: Unsubscribed")
            
            if previousStatus != self.isUserSubscribed {
                logger.eventMessage("Subscription status CHANGED from \(previousStatus) to \(self.isUserSubscribed) - notifying observers")
                AnalyticsManager.shared.logEvent("subscription_status_changed", parameters: [
                    "previous_status": previousStatus,
                    "new_status": self.isUserSubscribed,
                    "user_id": Auth.auth().currentUser?.uid ?? "",
                    "change_source": "revenueCat_update_no_customer_info"
                ])
            }
            NotificationCenter.default.post(name: Notification.Name.subscriptionStatusUpdated, object: nil)
            return
        }

        self.customerInfo = customerInfo
        
        let entitlements = customerInfo.entitlements.all
        let activeEntitlements = entitlements.filter { $0.value.isActive }
        
        self.isUserSubscribed = !activeEntitlements.isEmpty
        SharedUserStorage.save(value: self.isUserSubscribed, forKey: .isUserSubscribed)

        logger.eventMessage("Subscription status updated: \(self.isUserSubscribed ? "Subscribed" : "Unsubscribed")")
        
        if previousStatus != self.isUserSubscribed {
            logger.eventMessage("Subscription status CHANGED from \(previousStatus) to \(self.isUserSubscribed) - notifying observers")
            AnalyticsManager.shared.logEvent("subscription_status_changed", parameters: [
                "previous_status": previousStatus,
                "new_status": self.isUserSubscribed,
                "user_id": Auth.auth().currentUser?.uid ?? "",
                "change_source": "revenueCat_update",
                "has_active_entitlements": !activeEntitlements.isEmpty
            ])
        }
        
        if let activeEntitlement = activeEntitlements.first?.value {
            let subscriptionType = Self.subscriptionType(fromProductId: activeEntitlement.productIdentifier)
            let isTrial = activeEntitlement.periodType == .trial

            // Detect deferred trial→paid conversion.
            // When the user's trial period ends and converts to a paid subscription,
            // RevenueCat updates periodType from .trial to .normal. We fire af_subscribe
            // exactly once for this transition (the purchase callback only fires af_start_trial
            // at the moment of trial start).
            let lastPeriod = SharedUserStorage.retrieve(forKey: .lastKnownPeriodType, as: String.self)
            let currentPeriod: String = isTrial ? "trial" : "normal"

            if lastPeriod == "trial" && currentPeriod == "normal" {
                logger.eventMessage("Trial→paid conversion detected — firing subscription_success (af_subscribe)")
                AnalyticsManager.shared.logEvent("subscription_success", parameters: [
                    "package_id": activeEntitlement.productIdentifier,
                    "subscription_type": subscriptionType,
                    "conversion_source": "trial_to_paid"
                ])
            }

            SharedUserStorage.save(value: currentPeriod, forKey: .lastKnownPeriodType)

            if isTrial {
                let trialStartDate = activeEntitlement.originalPurchaseDate ?? Date()
                let trialTimestamp = Int(trialStartDate.timeIntervalSince1970)
                pushService.setTag(key: "trial_start_date", value: String(trialTimestamp))
                logger.eventMessage("Set trial_start_date tag: \(trialTimestamp)")
            }
            
            if Auth.auth().currentUser != nil {
                let originalPurchaseDateTimestamp: Any
                if let originalPurchaseDate = activeEntitlement.originalPurchaseDate {
                    originalPurchaseDateTimestamp = Timestamp(date: originalPurchaseDate)
                } else {
                    originalPurchaseDateTimestamp = NSNull()
                }

                let latestPurchaseDateTimestamp: Any
                if let latestPurchaseDate = activeEntitlement.latestPurchaseDate {
                    latestPurchaseDateTimestamp = Timestamp(date: latestPurchaseDate)
                } else {
                    latestPurchaseDateTimestamp = NSNull()
                }

                let endDateTimestamp: Any
                if let endDate = activeEntitlement.expirationDate {
                    endDateTimestamp = Timestamp(date: endDate)
                } else {
                    endDateTimestamp = NSNull()
                }

                let subscriptionData: [String: Any] = [
                    "isSubscribed": true,
                    "subscriptionType": subscriptionType,
                    "startDate": originalPurchaseDateTimestamp,
                    "endDate": endDateTimestamp,
                    "entitlementIDs": Array(activeEntitlements.keys),
                    "platform": "iOS",
                    "originalPurchaseDate": originalPurchaseDateTimestamp,
                    "latestPurchaseDate": latestPurchaseDateTimestamp,
                    "isTrial": isTrial
                ]
                FirestoreManager.shared.updateSubscriptionData(subscriptionData)
            }
        } else {
            // No active entitlement — subscription expired or was cancelled.
            SharedUserStorage.delete(forKey: .lastKnownPeriodType)
        }
        
        NotificationCenter.default.post(name: Notification.Name.subscriptionStatusUpdated, object: nil)
    }

    func refreshSubscriptionStatus() {
        Purchases.shared.getCustomerInfo { [weak self] (customerInfo, error) in
            guard let self = self else { return }
            if let customerInfo = customerInfo {
                logger.eventMessage("CustomerInfo refreshed: \(customerInfo)")
                self.updateSubscriptionStatus(customerInfo: customerInfo)
            } else {
                logger.errorMessage("Error refreshing customer info: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    private func hashEmail(_ email: String) -> String {
        let inputData = Data(email.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
    
    func resetSubscriptionStatusForGuest() {
        logger.eventMessage("Resetting subscription status for guest user.")
        self.isUserSubscribed = false
        SharedUserStorage.save(value: false, forKey: .isUserSubscribed)
        refreshSubscriptionStatus()
    }

    // MARK: - Migration Logic
    
    // Add this method to handle the RevenueCat subscription migration process
    @objc func migrateSubscriptionFromGuest(_ guestId: String, userId: String) {
        print("📱 SUB_MANAGER: Beginning migration from guest ID \(guestId) to user ID \(userId)")
        
        // Set migration flags
        self.isMigrationInProgress = true
        self.migrationGuestId = guestId
        SharedUserStorage.save(value: true, forKey: .migrationInProgress)
        SharedUserStorage.save(value: guestId, forKey: .previousGuestId)
        
        // First check if the guest was subscribed - check all possible indicators
        let wasGuestSubscribed = SharedUserStorage.retrieve(forKey: .wasSubscribedBeforeMigration, as: Bool.self) ?? 
                               SharedUserStorage.retrieve(forKey: .isUserSubscribed, as: Bool.self) ?? 
                               self.isUserSubscribed
                               
        print("📱 SUB_MANAGER: Guest was subscribed? \(wasGuestSubscribed)")
        
        // Save subscription status for redundancy
        SharedUserStorage.save(value: wasGuestSubscribed, forKey: .wasSubscribedBeforeMigration)
        
        // Force set subscription status during migration
        if wasGuestSubscribed {
            self.isUserSubscribed = true
            SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
            print("📱 SUB_MANAGER: Forced subscription status to true during migration")
        }
        
        // Log analytics event for subscription migration
        AnalyticsManager.shared.logEvent("subscription_migration_started", parameters: [
            "guest_id": guestId,
            "user_id": userId,
            "was_subscribed": wasGuestSubscribed
        ])
        
        // Execute migration in sequence for maximum reliability
        executeSubscriptionMigration(guestId: guestId, userId: userId, wasSubscribed: wasGuestSubscribed)
    }

    private func executeSubscriptionMigration(guestId: String, userId: String, wasSubscribed: Bool) {
        // Step 1: Log in to RevenueCat with the new user ID
        print("📱 SUB_MANAGER: Logging in to RevenueCat with new user ID: \(userId)")
        
        // CRITICAL: Before migration, force subscription status to be preserved
        if wasSubscribed {
            self.isUserSubscribed = true
            SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
            print("📱 SUB_MANAGER: Setting subscription status to true before migration")
        }
        
        // First fetch customer info for the guest to confirm subscription status
        if wasSubscribed {
            // Try fetching info with the guest ID first to confirm subscription
            Purchases.shared.logIn(guestId) { [weak self] (guestInfo, _, _) in
                guard let self = self else { return }
                
                let guestHasEntitlements = guestInfo?.entitlements.active.isEmpty == false
                print("📱 SUB_MANAGER: Guest ID entitlements check: \(guestHasEntitlements)")
                
                // Now perform the actual migration to the new user ID
                self.performRevenueCatLogin(userId: userId, wasSubscribed: wasSubscribed || guestHasEntitlements)
            }
        } else {
            // Not subscribed, just perform the migration directly
            performRevenueCatLogin(userId: userId, wasSubscribed: wasSubscribed)
        }
    }
    
    private func performRevenueCatLogin(userId: String, wasSubscribed: Bool) {
        // Perform the actual login to RevenueCat with the new user ID
        Purchases.shared.logIn(userId) { [weak self] (customerInfo, created, error) in
            guard let self = self else { return }
            
            if let error = error {
                                        print("📱 SUB_MANAGER: Error during RevenueCat migration: \(error.localizedDescription)")
                
                // Handle migration error - try fallback methods if needed
                if wasSubscribed {
                                                print("📱 SUB_MANAGER: Error during migration for subscribed user, trying fallbacks")
                    self.attemptSubscriptionRestoration(userId: userId)
                } else {
                    // Not subscribed, just clear flags
                    self.clearMigrationFlags()
                }
            } else {
                                  print("📱 SUB_MANAGER: RevenueCat login successful during migration")
                
                // Check if the subscription was successfully migrated
                if let info = customerInfo {
                    let hasActiveEntitlements = !info.entitlements.active.isEmpty
                    print("📱 SUB_MANAGER: User has active entitlements after migration? \(hasActiveEntitlements)")
                    
                    if hasActiveEntitlements {
                                                  print("📱 SUB_MANAGER: Migration successful - user has active subscription")
                        
                        // Update subscription status
                        self.isUserSubscribed = true
                        SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                        
                        // Migration successful, update customer info 
                        self.customerInfo = info
                        
                        // Clear migration flags
                        self.clearMigrationFlags()
                        
                        // Notify observers
                        NotificationCenter.default.post(name: Notification.Name.subscriptionStatusUpdated, object: nil)
                        
                        // Sync subscription data to Firestore
                        if let user = Auth.auth().currentUser {
                            self.syncSubscriptionToFirestore(userId: user.uid)
                        }
                    } else if wasSubscribed {
                        // The user should have a subscription, but it's not showing up
                                                      print("📱 SUB_MANAGER: Migration incomplete - missing entitlements, attempting restoration")
                        
                        // Force subscription status to be true during restoration attempts
                        self.isUserSubscribed = true
                        SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                        
                        // Try to restore the subscription
                        self.attemptSubscriptionRestoration(userId: userId)
                    } else {
                        // User wasn't subscribed, no problem
                                                  print("📱 SUB_MANAGER: Migration complete for non-subscribed user")
                        
                        // Clear migration flags
                        self.clearMigrationFlags()
                    }
                } else if wasSubscribed {
                    // No customer info returned but user was subscribed - attempt restoration
                                          print("📱 SUB_MANAGER: No customer info returned but user was subscribed, attempting restoration")
                    self.isUserSubscribed = true
                    SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                    self.attemptSubscriptionRestoration(userId: userId)
                } else {
                    // Not subscribed and no customer info, just clear flags
                    self.clearMigrationFlags()
                }
            }
        }
    }
    
    // Helper method to clear all migration-related flags
    private func clearMigrationFlags() {
                  print("📱 SUB_MANAGER: Clearing migration flags")
        self.isMigrationInProgress = false
        self.migrationGuestId = nil
        SharedUserStorage.delete(forKey: .migrationInProgress)
        SharedUserStorage.delete(forKey: .previousGuestId)
        SharedUserStorage.delete(forKey: .wasSubscribedBeforeMigration)
    }

    private func attemptSubscriptionRestoration(userId: String) {
                  print("📱 SUB_MANAGER: Attempting subscription restoration")
        
        // Force subscription to be active during restoration attempts
        self.isUserSubscribed = true
        SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
        
        // Try standard restore
        Purchases.shared.restorePurchases { [weak self] (customerInfo, error) in
            guard let self = self else { return }
            
            if let error = error {
                                  print("📱 SUB_MANAGER: Error during subscription restoration: \(error.localizedDescription)")
                
                // Even with error, force subscription to remain active
                self.isUserSubscribed = true
                SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                
                // Try a second restoration after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.performFinalRestoration()
                }
            } else if let customerInfo = customerInfo {
                // Check if restore was successful
                let hasActiveEntitlements = !customerInfo.entitlements.active.isEmpty
                                  print("📱 SUB_MANAGER: User has active entitlements after restore? \(hasActiveEntitlements)")
                
                if hasActiveEntitlements {
                                          print("📱 SUB_MANAGER: Restoration successful")
                    
                    // Update subscription status
                    self.isUserSubscribed = true
                    SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                    
                    // Update customer info
                    self.customerInfo = customerInfo
                    
                    // Clear migration flags
                    SharedUserStorage.delete(forKey: .migrationInProgress)
                    SharedUserStorage.delete(forKey: .previousGuestId)
                    SharedUserStorage.delete(forKey: .wasSubscribedBeforeMigration)
                    
                    // Notify observers
                    NotificationCenter.default.post(name: Notification.Name.subscriptionStatusUpdated, object: nil)
                    
                    // Sync subscription data to Firestore
                    if let user = Auth.auth().currentUser {
                        self.syncSubscriptionToFirestore(userId: user.uid)
                    }
                } else {
                    // Restoration didn't work, try final attempt
                                          print("📱 SUB_MANAGER: Restore didn't recover subscription, trying final attempt")
                    
                    // Force subscription to remain active
                    self.isUserSubscribed = true
                    SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                    
                    // Try final restoration
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.performFinalRestoration()
                    }
                }
            } else {
                // No customer info returned, try final restoration
                                  print("📱 SUB_MANAGER: No customer info returned from restore, trying final attempt")
                self.isUserSubscribed = true
                SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.performFinalRestoration()
                }
            }
        }
    }

    private func performFinalRestoration() {
                  print("📱 SUB_MANAGER: Performing final restoration attempt")
        
        // Force subscription to be active during final restoration attempt
        self.isUserSubscribed = true
        SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
        
        // Force refresh from network
        Purchases.shared.getCustomerInfo { [weak self] (customerInfo, error) in
            guard let self = self else { return }
            
            if let error = error {
                                  print("📱 SUB_MANAGER: Error during final restoration: \(error.localizedDescription)")
                
                // Keep forced subscription status even with error
                self.isUserSubscribed = true
                SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                
                // Notify observers
                NotificationCenter.default.post(name: Notification.Name.subscriptionStatusUpdated, object: nil)
            } else if let customerInfo = customerInfo {
                // Check status
                let hasActiveEntitlements = !customerInfo.entitlements.active.isEmpty
                                  print("📱 SUB_MANAGER: User has active entitlements after final attempt? \(hasActiveEntitlements)")
                
                if hasActiveEntitlements {
                                          print("📱 SUB_MANAGER: Final restoration successful")
                    
                    // Update status
                    self.isUserSubscribed = true
                    SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                    
                    // Update customer info
                    self.customerInfo = customerInfo
                    
                    // Clear migration flags
                    SharedUserStorage.delete(forKey: .migrationInProgress)
                    SharedUserStorage.delete(forKey: .previousGuestId)
                    SharedUserStorage.delete(forKey: .wasSubscribedBeforeMigration)
                    
                    // Sync subscription data to Firestore after final restoration attempt
                    if let user = Auth.auth().currentUser, self.isUserSubscribed {
                        self.syncSubscriptionToFirestore(userId: user.uid)
                    }
                } else {
                                          print("📱 SUB_MANAGER: Final restoration failed - maintaining forced subscription")
                    
                    // Force subscription status as last resort
                    self.isUserSubscribed = true
                    SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                }
                
                // Always notify observers
                NotificationCenter.default.post(name: Notification.Name.subscriptionStatusUpdated, object: nil)
            } else {
                // No customer info returned, maintain forced subscription
                                  print("📱 SUB_MANAGER: No customer info returned from final attempt - maintaining forced subscription")
                self.isUserSubscribed = true
                SharedUserStorage.save(value: true, forKey: .isUserSubscribed)
                
                // Notify observers
                NotificationCenter.default.post(name: Notification.Name.subscriptionStatusUpdated, object: nil)
            }
        }
    }
    
    // Helper method to sync subscription data to Firestore
    private func syncSubscriptionToFirestore(userId: String) {
                  print("📱 SUB_MANAGER: Syncing subscription data to Firestore for user \(userId)")
        
        // Get latest customer info
        Purchases.shared.getCustomerInfo { [weak self] (customerInfo, error) in
            guard let self = self else { return }
            
            if let error = error {
                                  print("📱 SUB_MANAGER: Error getting customer info for Firestore sync: \(error.localizedDescription)")
                return
            }
            
            if let customerInfo = customerInfo {
                let activeEntitlements = customerInfo.entitlements.active
                
                if !activeEntitlements.isEmpty {
                    if let activeEntitlement = activeEntitlements.first?.value {
                        let subscriptionType = Self.subscriptionType(fromProductId: activeEntitlement.productIdentifier)
                        let isTrial = activeEntitlement.periodType == .trial
                        
                        // Create timestamps for Firestore
                        let originalPurchaseDateTimestamp = activeEntitlement.originalPurchaseDate.map { Timestamp(date: $0) } ?? Timestamp()
                        let latestPurchaseDateTimestamp = activeEntitlement.latestPurchaseDate.map { Timestamp(date: $0) } ?? Timestamp()
                        let endDateTimestamp = activeEntitlement.expirationDate.map { Timestamp(date: $0) } ?? Timestamp(date: Date().addingTimeInterval(86400 * 365))
                        
                        // Create subscription data
                        let subscriptionData: [String: Any] = [
                            "isSubscribed": true,
                            "subscriptionType": subscriptionType,
                            "startDate": originalPurchaseDateTimestamp,
                            "endDate": endDateTimestamp,
                            "entitlementIDs": Array(activeEntitlements.keys),
                            "platform": "iOS",
                            "originalPurchaseDate": originalPurchaseDateTimestamp,
                            "latestPurchaseDate": latestPurchaseDateTimestamp,
                            "isTrial": isTrial,
                            "lastUpdated": Timestamp(),
                            "migrated": true
                        ]
                        
                        // Update Firestore
                        FirestoreManager.shared.updateSubscriptionData(subscriptionData)
                        print("📱 SUB_MANAGER: Successfully synced subscription data to Firestore")
                    }
                } else if self.isUserSubscribed {
                    // Fallback - if we think the user is subscribed but RevenueCat doesn't show it
                                          print("📱 SUB_MANAGER: No active entitlements found, but user marked as subscribed. Using fallback data.")
                    
                    let subscriptionData: [String: Any] = [
                        "isSubscribed": true,
                        "subscriptionType": "unknown",
                        "startDate": Timestamp(),
                        "endDate": Timestamp(date: Date().addingTimeInterval(86400 * 365)),
                        "platform": "iOS",
                        "lastUpdated": Timestamp(),
                        "migrated": true,
                        "isFallbackData": true
                    ]
                    
                    // Update Firestore
                    FirestoreManager.shared.updateSubscriptionData(subscriptionData)
                }
            }
        }
    }
}

// MARK: - PurchasesDelegate

extension SubscriptionManager {
    /// Called whenever RevenueCat receives updated customer info
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        logger.eventMessage("RevenueCat: Received updated customer info - real-time subscription update")
        print("📱 SUB_MANAGER: RevenueCat delegate triggered - updating subscription status in real-time")
        updateSubscriptionStatus(customerInfo: customerInfo)
    }
}

// MARK: - SubscriptionServiceProtocol Conformance

extension SubscriptionManager: SubscriptionServiceProtocol {
    var isUserSubscribedPublisher: AnyPublisher<Bool, Never> {
        $isUserSubscribed.eraseToAnyPublisher()
    }
    
    // Protocol conformance is automatic for:
    // - var isUserSubscribed: Bool { get }
    // - func refreshSubscriptionStatus()
    // - func resetSubscriptionStatusForGuest()
}
