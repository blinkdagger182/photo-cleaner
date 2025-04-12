import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        ZStack {
            // Switch between views based on the current route
            switch coordinator.currentRoute {
            case .onboarding:
                OnboardingView()
                    .environmentObject(coordinator)
                    .transition(.opacity)
            
            case .splash:
                SplashView()
                    .environmentObject(coordinator)
                    .transition(.opacity)
            
            case .main:
                MainView()
                    .environmentObject(coordinator)
                    .transition(.opacity)
            }
        }
        .environmentObject(coordinator.updateService)
        .environmentObject(coordinator.photoManager)
        .environmentObject(coordinator.toastService)
    }
}
