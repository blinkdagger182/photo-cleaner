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
                        .environmentObject(coordinator.photoManager)
                        .environmentObject(coordinator.toastService)
                case .splash:
                    SplashView(viewModel: SplashViewModel(coordinator: coordinator))
                        .environmentObject(coordinator.photoManager)
                        .environmentObject(coordinator.toastService)
                case .main:
                    mainContent
                        .environmentObject(coordinator.mainFlowCoordinator)
                        .environmentObject(coordinator.photoManager)
                        .environmentObject(coordinator.toastService)
                        .environmentObject(coordinator)
                
                default:
                    EmptyView()
                }
                
                // Overlay force update view if required
                if coordinator.appState.forceUpdateRequired {
                    ForceUpdateOverlayView(coordinator: coordinator.updateCoordinator)
                }
            }
            .modifier(WithModalCoordination(coordinator: coordinator.modalCoordinator))
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        // Handle main flow navigation based on MainFlowCoordinator's currentRoute
        switch coordinator.mainFlowCoordinator.currentRoute {
        case .photoGroup:
            PhotoGroupView(viewModel: PhotoGroupViewModel(coordinator: coordinator.mainFlowCoordinator))
        
        case .swipeCard(let photoGroupId):
            if let group = coordinator.photoManager.getPhotoGroup(withId: photoGroupId) {
                SwipeCardView(viewModel: SwipeCardViewModel(
                    group: group,
                    photoManager: coordinator.photoManager,
                    forceRefresh: .constant(false),
                    modalCoordinator: coordinator.modalCoordinator
                ))
            } else {
                // Fallback in case group not found
                PhotoGroupView(viewModel: PhotoGroupViewModel(coordinator: coordinator.mainFlowCoordinator))
            }
            
        default:
            // For any other routes, show photo group
            PhotoGroupView(viewModel: PhotoGroupViewModel(coordinator: coordinator.mainFlowCoordinator))
        }
    }
} 