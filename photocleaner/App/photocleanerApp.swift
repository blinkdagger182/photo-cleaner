import SwiftUI

@main
struct photocleanerApp: App {
    // Create a single instance of the AppCoordinator to manage navigation
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Display the appropriate view based on the current route
                switch coordinator.currentRoute {
                case .onboarding:
                    OnboardingView(viewModel: OnboardingViewModel(coordinator: coordinator))
                case .splash:
                    SplashView(viewModel: SplashViewModel(coordinator: coordinator))
                case .main:
                    PhotoGroupView(viewModel: PhotoGroupViewModel(coordinator: coordinator.mainFlowCoordinator))
                        .environmentObject(coordinator.mainFlowCoordinator)
                default:
                    EmptyView()
                }
                
                // Overlay force update view if required
                if coordinator.appState.forceUpdateRequired {
                    ForceUpdateOverlayView(coordinator: coordinator.updateCoordinator)
                }
            }
        }
    }
} 