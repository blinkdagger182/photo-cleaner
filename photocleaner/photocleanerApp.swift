import SwiftUI

@main
struct photocleanerApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @StateObject var updateService = UpdateService.shared
    @StateObject var photoManager = PhotoManager()
    @StateObject var toast = ToastService()

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding {
                    SplashView()
                        .task {
                            await updateService.checkAppVersion()
                            
                            await photoManager.checkCurrentStatus()
                        }
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(updateService)
            .environmentObject(photoManager)
            .environmentObject(toast)
        }
    }
}
