import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var isPurchasing = false
    @State private var selectedPackageIndex = 1  // Default to annual (middle option)
    @State private var showError = false
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 25) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.gray)
                            .padding()
                    }
                }
                
                // Title and description
                VStack(spacing: 16) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 70, height: 70)
                        .foregroundColor(.blue)
                    
                    Text("Unlimited Access")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("Clean and organize unlimited photos with a premium subscription")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                // Features list
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "infinity", title: "Unlimited photo cleaning")
                    FeatureRow(icon: "lock.shield", title: "No more daily limits")
                    FeatureRow(icon: "bell.badge.slash", title: "No ads")
                    FeatureRow(icon: "arrow.clockwise", title: "New features first")
                }
                .padding(.horizontal, 30)
                .padding(.vertical)
                
                // Subscription options
                if subscriptionManager.isLoadingOfferings {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                } else if let offering = subscriptionManager.currentOffering {
                    // Only show if we have packages to display
                    if !offering.availablePackages.isEmpty {
                        VStack(spacing: 12) {
                            // Filter for just the key subscription packages we want to show
                            let packages = getPackagesToDisplay(from: offering.availablePackages)
                            
                            ForEach(Array(packages.enumerated()), id: \.offset) { index, package in
                                SubscriptionOptionCard(
                                    package: package,
                                    isSelected: selectedPackageIndex == index,
                                    action: {
                                        selectedPackageIndex = index
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        Text("No subscription options available")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Unable to load subscription options")
                        .foregroundColor(.secondary)
                }
                
                // Purchase button
                Button(action: {
                    purchaseSelectedPackage()
                }) {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(height: 20)
                    } else {
                        Text("Continue")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(16)
                .padding(.horizontal)
                .disabled(isPurchasing || subscriptionManager.currentOffering == nil)
                
                // Restore purchases
                Button("Restore Purchases") {
                    restorePurchases()
                }
                .font(.footnote)
                .padding(.bottom)
                
                // Terms and privacy
                HStack(spacing: 4) {
                    Text("By continuing, you agree to our")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button("Terms") {
                        // Open terms URL
                    }
                    .font(.caption2)
                    
                    Text("and")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button("Privacy Policy") {
                        // Open privacy URL
                    }
                    .font(.caption2)
                }
                .padding(.bottom, 8)
            }
            .padding(.vertical)
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Purchase Failed"),
                message: Text(subscriptionManager.errorMessage ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            subscriptionManager.fetchOfferings()
        }
    }
    
    private func getPackagesToDisplay(from availablePackages: [Package]) -> [Package] {
        // Filter and sort packages to display
        // Priority: monthly, annual, lifetime (if available)
        let packageTypes: [PackageType] = [.monthly, .annual]
        
        var result: [Package] = []
        
        // Add packages in our preferred order
        for type in packageTypes {
            if let package = availablePackages.first(where: { $0.packageType == type }) {
                result.append(package)
            }
        }
        
        // If empty, just return all available packages
        return result.isEmpty ? availablePackages : result
    }
    
    private func purchaseSelectedPackage() {
        guard let offering = subscriptionManager.currentOffering else { return }
        let packages = getPackagesToDisplay(from: offering.availablePackages)
        
        // Make sure we have a valid index
        guard selectedPackageIndex < packages.count else { return }
        
        let selectedPackage = packages[selectedPackageIndex]
        isPurchasing = true
        
        Task {
            let success = await subscriptionManager.purchase(package: selectedPackage)
            
            // Update UI on main thread
            await MainActor.run {
                isPurchasing = false
                
                if success {
                    dismiss()
                } else if let errorMessage = subscriptionManager.errorMessage {
                    showError = true
                }
            }
        }
    }
    
    private func restorePurchases() {
        isPurchasing = true
        
        Task {
            await subscriptionManager.restorePurchases()
            
            await MainActor.run {
                isPurchasing = false
                
                if subscriptionManager.isSubscribed {
                    dismiss()
                } else if let errorMessage = subscriptionManager.errorMessage, !errorMessage.isEmpty {
                    showError = true
                }
            }
        }
    }
}

// Feature row component
struct FeatureRow: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.system(size: 20))
                .frame(width: 26, height: 26)
            
            Text(title)
                .font(.body)
        }
    }
}

// Subscription option card
struct SubscriptionOptionCard: View {
    let package: Package
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(packageTitle)
                        .font(.headline)
                    
                    if let duration = packageDuration {
                        Text(duration)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(package.localizedPriceString)
                        .font(.headline)
                    
                    if let perMonthPrice = calculatePricePerMonth() {
                        Text(perMonthPrice)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .padding(.leading, 8)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(UIColor.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var packageTitle: String {
        switch package.packageType {
        case .monthly:
            return "Monthly"
        case .annual:
            return "Annual"
        case .lifetime:
            return "Lifetime"
        default:
            return package.identifier
        }
    }
    
    private var packageDuration: String? {
        switch package.packageType {
        case .monthly:
            return "Billed monthly"
        case .annual:
            return "Billed annually"
        case .lifetime:
            return "One-time purchase"
        default:
            return nil
        }
    }
    
    private func calculatePricePerMonth() -> String? {
        switch package.packageType {
        case .annual:
            // For annual packages, get the monthly equivalent price
            // Get the price as NSNumber
            let annualPrice = package.storeProduct.price
            
            // Calculate monthly price (annual ÷ 12)
            // Convert Decimal to Double using NSDecimalNumber
            let annualPriceDecimal = annualPrice as NSDecimalNumber
            let monthlyPriceValue = annualPriceDecimal.doubleValue / 12.0
            
            // Format it as currency
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            
            // Use the price's locale or default to current locale
            if let formattedPrice = formatter.string(from: NSNumber(value: monthlyPriceValue)) {
                return "\(formattedPrice)/month"
            }
            return nil
        default:
            return nil
        }
    }
}

#Preview {
    PaywallView()
} 