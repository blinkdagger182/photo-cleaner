import SwiftUI
import RevenueCat

@main
struct photocleanerApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @StateObject var updateService = UpdateService.shared
    @StateObject var photoManager = PhotoManager()
    @StateObject var toast = ToastService()
    
    // Initialize and access the shared subscription manager
    @StateObject var subscriptionManager = SubscriptionManager.shared
    
    // Access the swipe tracker
    private let swipeTracker = SwipeTracker.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding {
                    SplashView()
                        .task {
                            await updateService.checkAppVersion()
                            await photoManager.checkCurrentStatus()
                            
                            // Check subscription status on app launch
                            subscriptionManager.refreshSubscriptionStatus()
                            
                            // Check if we need to reset the swipe counter
                            swipeTracker.checkAndResetIfNeeded()
                            
                            // Configure PaywallUI appearance options
                            configurePaywallAppearance()
                        }
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(updateService)
            .environmentObject(photoManager)
            .environmentObject(toast)
            .environmentObject(subscriptionManager)
            .accentColor(.blue) // Set the app's tint color to match paywalls
        }

        WindowGroup("Launch Screen", id: "Launch Screen") {
            LaunchScreen()
        }
    }
    
    // Configure global appearance settings for RevenueCat paywalls
    private func configurePaywallAppearance() {
        // You can customize the paywall appearance here
        // For example, set custom colors, fonts, etc.
        
        // Enable logging for development
        #if DEBUG
        // Debug logging will use the standard RevenueCat debugging
        Purchases.logLevel = .debug
        #endif
    }
}
