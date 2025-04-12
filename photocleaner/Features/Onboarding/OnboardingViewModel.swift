import SwiftUI
import Photos

class OnboardingViewModel: ObservableObject {
    @Published var showPermissionDenied = false
    
    private let coordinator: AppCoordinator
    private let photoManager = PhotoManager.shared
    
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
    
    func requestPhotoAccess() {
        Task {
            await photoManager.requestAuthorization()
            
            await MainActor.run {
                switch photoManager.authorizationStatus {
                case .authorized, .limited:
                    // Access granted, proceed to the app
                    showPermissionDenied = false
                    coordinator.completeOnboarding()
                    
                default:
                    // Access denied, show error
                    showPermissionDenied = true
                }
            }
        }
    }
} 