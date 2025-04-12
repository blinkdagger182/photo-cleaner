import SwiftUI

@main
struct photocleanerApp: App {
    // Create a single instance of the AppCoordinator to manage navigation
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        WindowGroup {
            // Use the RootView which handles navigation based on the coordinator's state
            RootView()
                .environmentObject(coordinator)
        }

        // Keep the Launch Screen window group
        WindowGroup("Launch Screen", id: "Launch Screen") {
            LaunchScreen()
        }
    }
}
