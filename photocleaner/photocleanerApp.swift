import SwiftUI
import RevenueCat

@main
struct photocleanerApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @StateObject var updateService = UpdateService.shared
    @StateObject var photoManager = PhotoManager()
    @StateObject var toast = ToastService()
    
    // Access the shared instances to initialize them at app startup
    private let subscriptionManager = SubscriptionManager.shared
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
                        }
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(updateService)
            .environmentObject(photoManager)
            .environmentObject(toast)
        }

        WindowGroup("Launch Screen", id: "Launch Screen") {
            LaunchScreen()
        }
    }
}
