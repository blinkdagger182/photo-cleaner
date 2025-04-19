import Foundation
import RevenueCat
import Combine
import SwiftUI

class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // Published properties to observe subscription state
    @Published var isSubscribed = false
    @Published var currentOffering: Offering?
    @Published var isLoadingOfferings = false
    @Published var purchaseInProgress = false
    @Published var errorMessage: String?
    
    // Keep track of subscriber info
    private var customerInfo: CustomerInfo?
    private let entitlementID = "premium_access"
    private var cancellables = Set<AnyCancellable>()
    
    // Paywall configuration
    let offeringIdentifier = "default"  // Replace with your offering identifier from RevenueCat dashboard
    
    private init() {
        // Setup RevenueCat SDK
        setupRevenueCat()
        
        // Check subscription status on initialization
        refreshSubscriptionStatus()
    }
    
    // Configure RevenueCat with your API key
    private func setupRevenueCat() {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_SAJcTFqLeBLEYlRIVBtSSPDBJRe")
        
        // Register for notifications using the string-based notification name
        NotificationCenter.default.publisher(for: NSNotification.Name("com.revenuecat.purchases.customer_info_updated"))
            .sink { [weak self] _ in
                self?.refreshSubscriptionStatus()
            }
            .store(in: &cancellables)
    }
    
    // Fetch available offerings
    func fetchOfferings() {
        isLoadingOfferings = true
        errorMessage = nil
        
        Purchases.shared.getOfferings { [weak self] offerings, error in
            DispatchQueue.main.async {
                self?.isLoadingOfferings = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                self?.currentOffering = offerings?.current
            }
        }
    }
    
    // Refresh the subscription status
    func refreshSubscriptionStatus() {
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                self.customerInfo = customerInfo
                self.isSubscribed = customerInfo?.entitlements[self.entitlementID]?.isActive == true
                
                // If the user is now subscribed, reset the swipe counter
                if self.isSubscribed {
                    SwipeTracker.shared.resetSwipeCount()
                }
            }
        }
    }
    
    // Purchase a package
    func purchase(package: Package) async -> Bool {
        purchaseInProgress = true
        errorMessage = nil
        
        do {
            let result = try await Purchases.shared.purchase(package: package)
            purchaseInProgress = false
            
            // Check entitlement status
            let isActive = result.customerInfo.entitlements[entitlementID]?.isActive == true
            isSubscribed = isActive
            customerInfo = result.customerInfo
            
            return isActive
        } catch {
            errorMessage = error.localizedDescription
            purchaseInProgress = false
            return false
        }
    }
    
    // Restore purchases
    func restorePurchases() async {
        purchaseInProgress = true
        errorMessage = nil
        
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            purchaseInProgress = false
            
            // Update subscription status
            self.customerInfo = customerInfo
            isSubscribed = customerInfo.entitlements[entitlementID]?.isActive == true
            
            // Reset swipe counter if restored successfully
            if isSubscribed {
                SwipeTracker.shared.resetSwipeCount()
            }
        } catch {
            errorMessage = error.localizedDescription
            purchaseInProgress = false
        }
    }
    
    // Check if the paywall should be shown
    func shouldShowPaywall() -> Bool {
        // Only show if not subscribed and has reached the limit
        return !isSubscribed && SwipeTracker.shared.hasReachedLimit
    }
    
    // Handle purchase completion
    func handlePurchaseCompletion(_ customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        isSubscribed = customerInfo.entitlements[entitlementID]?.isActive == true
        
        // Reset the swipe counter after successful purchase
        if isSubscribed {
            SwipeTracker.shared.resetSwipeCount()
        }
    }
    
    // Handle restore completion
    func handleRestoreCompletion(_ customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        isSubscribed = customerInfo.entitlements[entitlementID]?.isActive == true
        
        // Reset the swipe counter after successful restore
        if isSubscribed {
            SwipeTracker.shared.resetSwipeCount()
        }
    }
} 