import SwiftUI

class SplashViewModel: ObservableObject {
    @Published var isLoading = false
    
    private let coordinator: AppCoordinator
    private let photoManager = PhotoManager.shared
    
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
    
    func loadInitialData() {
        isLoading = true
        
        Task {
            // Load photos
            await photoManager.loadAssets()
            
            // Simulate minimum loading time
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            await MainActor.run {
                isLoading = false
                coordinator.completeStartup()
            }
        }
    }
} 