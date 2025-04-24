import SwiftUI
import RevenueCat

@main
struct photocleanerApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @StateObject var updateService = UpdateService.shared
    @StateObject var photoManager = PhotoManager()
    @StateObject var toast = ToastService()
    @StateObject var smartAlbumManager = SmartAlbumManager.shared
    @StateObject var subscriptionManager = SubscriptionManager.shared
    @StateObject var imageViewTracker = ImageViewTracker.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding {
                    SplashView()
                        .task {
                            let apiKey = "api_key_here"
                            subscriptionManager.configure(apiKey: apiKey)
                            
                            await updateService.checkAppVersion()
                            await photoManager.checkCurrentStatus()
                            await subscriptionManager.checkSubscriptionStatus()
                        }
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(updateService)
            .environmentObject(photoManager)
            .environmentObject(toast)
            .environmentObject(smartAlbumManager)
            .environmentObject(subscriptionManager)
            .environmentObject(imageViewTracker)
        }
    }
    
//    init() {
//        // Configure RevenueCat with your API key
//        let apiKey = "appl_SAJcTFqLeBLEYlRIVBtSSPDBJRe" // Replace with your actual API key
//        subscriptionManager.configure(apiKey: apiKey)
//    }
}
