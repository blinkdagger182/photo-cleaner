import Foundation
import SwiftUI
import RevenueCat

@MainActor
class SubscriptionManager: NSObject, ObservableObject, PurchasesDelegate {
    // MARK: - Singleton
    static let shared = SubscriptionManager()
    
    // MARK: - Published Properties
    @Published var isPremium: Bool = false
    @Published var isLoading: Bool = false
    @Published var customerInfo: CustomerInfo?
    @Published var errorMessage: String?
    
    // MARK: - Constants
    private let entitlementID = "Plus"
    
    // MARK: - Initialization
    private override init() {
        super.init()
//        Purchases.shared.delegate = self
    }
    
    // MARK: - Setup
    func configure(apiKey: String) {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = SubscriptionManager.shared
//        Purchases.shared.customerInfoDelegate = self
        
        Task {
            await checkSubscriptionStatus()
        }
    }
    
    // MARK: - User Identification
    func identifyUser(userId: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)
            await MainActor.run {
                self.customerInfo = customerInfo
                self.isPremium = customerInfo.entitlements[entitlementID]?.isActive == true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to identify user: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("❌ Error identifying user: \(error)")
        }
    }
    
    func resetUser() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let customerInfo = try await Purchases.shared.logOut()
            await MainActor.run {
                self.customerInfo = customerInfo
                self.isPremium = customerInfo.entitlements[entitlementID]?.isActive == true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to reset user: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("❌ Error resetting user: \(error)")
        }
    }
    
    // MARK: - Subscription Status
    func checkSubscriptionStatus() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            await MainActor.run {
                self.customerInfo = customerInfo
                self.isPremium = customerInfo.entitlements[entitlementID]?.isActive == true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to check subscription: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("❌ Error checking subscription status: \(error)")
        }
    }
    
    // MARK: - Paywall Presentation
//    func showPaywall() async -> Bool {
//        guard !isPremium else { return true }
//        
//        isLoading = true
//        errorMessage = nil
//        
//        do {
//            // Get offerings to display the paywall
//            let offerings = try await Purchases.shared.offerings()
//            
//            guard let offering = offerings.current else {
//                await MainActor.run {
//                    self.errorMessage = "No offerings available"
//                    self.isLoading = false
//                }
//                return false
//            }
//            
//            // Present the RevenueCat paywall
//            let result = try await Purchases.shared.presentPaywall(offering: offering)
//
//            // Check if purchase was successful
//            if result.purchasedPackage != nil {
//                // Refresh customer info after purchase
//                let customerInfo = try await Purchases.shared.customerInfo()
//                await MainActor.run {
//                    self.customerInfo = customerInfo
//                    self.isPremium = customerInfo.entitlements[entitlementID]?.isActive == true
//                    self.isLoading = false
//                }
//                return true
//            } else {
//                await MainActor.run {
//                    self.isLoading = false
//                }
//                return false
//            }
//        } catch {
//            await MainActor.run {
//                self.errorMessage = "Failed to show paywall: \(error.localizedDescription)"
//                self.isLoading = false
//            }
//            print("❌ Error showing paywall: \(error)")
//            return false
//        }
//    }
    
    func getCurrentOffering() async -> Offering? {
        do {
            let offerings = try await Purchases.shared.offerings()
            return offerings.current
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to fetch offerings: \(error.localizedDescription)"
            }
            return nil
        }
    }

    
    // MARK: - Restore Purchases
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            await MainActor.run {
                self.customerInfo = customerInfo
                self.isPremium = customerInfo.entitlements[entitlementID]?.isActive == true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("❌ Error restoring purchases: \(error)")
        }
    }
    
    // MARK: - CustomerInfoDelegate
    func customerInfoReceived(_ customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.customerInfo = customerInfo
            self.isPremium = customerInfo.entitlements[entitlementID]?.isActive == true
        }
    }
    
    // MARK: - Error Handling
    func clearError() {
        errorMessage = nil
    }
}
