import SwiftUI
import RevenueCat
import RevenueCatUI

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var offering: Offering?
    @State private var isLoading: Bool = true
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        Group {
            if let offering = offering {
                RevenueCatUI.PaywallView(offering: offering)
            } else {
                VStack {
                    ProgressView("Loading subscription options…")
                        .padding()
                    
                    Button("Restore Purchases") {
                        Task {
                            isLoading = true
                            await subscriptionManager.restorePurchases()
                            isLoading = false

                            if subscriptionManager.isPremium {
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            Task {
                offering = await subscriptionManager.getCurrentOffering()
                isLoading = false

                if subscriptionManager.isPremium {
                    dismiss()
                }
            }
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: subscriptionManager.errorMessage) { newValue in
            if let error = newValue {
                errorMessage = error
                showError = true
                subscriptionManager.clearError()
            }
        }
    }
}
