import SwiftUI
import RevenueCat

@main
struct photocleanerApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @StateObject var updateService = UpdateService.shared
    @StateObject var photoManager = PhotoManager()
    @StateObject var toast = ToastService()
    
    // Lazily initialize these services only if onboarding is complete
    @StateObject var smartAlbumManager: SmartAlbumManager = {
        print("🔄 Initializing SmartAlbumManager - deferred until needed")
        return SmartAlbumManager.shared
    }()
    
    @StateObject var subscriptionManager = SubscriptionManager.shared
    @StateObject var imageViewTracker = ImageViewTracker.shared
    
    // Flag to control eager loading of non-onboarding services
    private var shouldLoadMainServices: Bool {
        hasSeenOnboarding
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding {
                    SplashView()
                        .task {
                            // Only run essential operations at launch
                            let apiKey = "appl_SAJcTFqLeBLEYlRIVBtSSPDBJRe"
                            subscriptionManager.configure(apiKey: apiKey)
                            
                            // Initialize services in background
                            Task.detached(priority: .utility) {
                                // Initialize the high-quality album cache in background
                                _ = AlbumHighQualityCache.shared
                                print("📸 Initialized AlbumHighQualityCache")
                            }
                            
                            // Run essential checks in parallel
                            async let versionCheck = updateService.checkAppVersion()
                            async let statusCheck = photoManager.checkCurrentStatus()
                            async let subscriptionCheck = subscriptionManager.checkSubscriptionStatus()
                            
                            // Wait for essential checks only
                            await versionCheck
                            await statusCheck
                            await subscriptionCheck
                            
                            // Move heavy pre-caching to background - don't block UI
                            Task.detached(priority: .utility) {
                                // Wait a bit for main UI to settle, then start pre-caching
                                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                                
                                let authStatus = await photoManager.authorizationStatus
                                if authStatus == .authorized || authStatus == .limited {
                                    await photoManager.preCacheFirstImages()
                                }
                            }
                        }
                } else {
                    OnboardingView()
                        .onAppear {
                            // Delay any heavy operations during onboarding
                            print("⚠️ Onboarding mode: Deferring heavy operations")
                        }
                }
            }
            .environmentObject(updateService)
            .environmentObject(photoManager)
            .environmentObject(toast)
            // Only attach services that are needed for both onboarding and main app
            // The rest will be attached conditionally based on which view is shown
            .modifier(ConditionalEnvironmentModifier(
                condition: shouldLoadMainServices,
                smartAlbumManager: smartAlbumManager,
                subscriptionManager: subscriptionManager,
                imageViewTracker: imageViewTracker
            ))
        }
    }
    
//    init() {
//        // Configure RevenueCat with your API key
//        let apiKey = "appl_SAJcTFqLeBLEYlRIVBtSSPDBJRe" // Replace with your actual API key
//        subscriptionManager.configure(apiKey: apiKey)
//    }
}

// A conditional modifier that only applies environment objects when needed
struct ConditionalEnvironmentModifier: ViewModifier {
    let condition: Bool
    let smartAlbumManager: SmartAlbumManager
    let subscriptionManager: SubscriptionManager
    let imageViewTracker: ImageViewTracker
    
    func body(content: Content) -> some View {
        if condition {
            // Apply all environment objects when the condition is true (main app)
            content
                .environmentObject(smartAlbumManager)
                .environmentObject(subscriptionManager)
                .environmentObject(imageViewTracker)
        } else {
            // During onboarding, we only include what's absolutely necessary
            // Skip attaching SmartAlbumManager and imageViewTracker until needed
            content
                .environmentObject(subscriptionManager) // Only needed for in-app purchases
        }
    }
}
