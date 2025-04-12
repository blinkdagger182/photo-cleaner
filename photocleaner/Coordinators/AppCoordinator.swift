import SwiftUI
import Combine
import Photos

// Define the possible routes in the app
enum AppRoute {
    case onboarding
    case splash
    case main
}

// App state class to track application state
//class AppState: ObservableObject {
//    @Published var forceUpdateRequired: Bool = false
//}

class AppCoordinator: ObservableObject {
    // Published property to control navigation
    @Published var currentRoute: AppRoute
    
    // App state
    let appState = AppState()
    
    // Services and managers
    let updateService: UpdateService
    let photoManager: PhotoManager
    let toastService: ToastService
    
    // Modal coordinator for handling modals and sheet presentations
    let modalCoordinator: ModalCoordinator
    
    // User preferences
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    
    @MainActor
    init() {
        // Initialize services first
        self.updateService = UpdateService.shared
        self.photoManager = PhotoManager.shared
        self.toastService = ToastService.shared
        self.modalCoordinator = ModalCoordinator()
        
        // Initialize currentRoute with a temporary value
        self.currentRoute = .splash
        
        // Now that all properties are initialized, we can safely check hasSeenOnboarding
        if !hasSeenOnboarding {
            self.currentRoute = .onboarding
        }
    }
    
    // Method to handle navigation to a specific route
    func navigate(to route: AppRoute) {
        withAnimation {
            currentRoute = route
        }
    }
    
    // Method to complete onboarding
    func completeOnboarding() {
        hasSeenOnboarding = true
        navigate(to: .splash)
    }
    
    // Method to complete splash and go to main content
    func completeStartup() {
        navigate(to: .main)
    }
}
