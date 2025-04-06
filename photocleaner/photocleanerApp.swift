import SwiftUI

@main
struct photocleanerApp: App {
    @StateObject var updateService = UpdateService.shared
    @StateObject var photoManager = PhotoManager()
    @StateObject var toast = ToastService()

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(updateService)
                .environmentObject(photoManager)
                .environmentObject(toast)
                .task {
                    await updateService.checkAppVersion()
                }
        }

        WindowGroup("Launch Screen", id: "Launch Screen") {
            LaunchScreen()
        }
    }
}
