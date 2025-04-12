import SwiftUI
import Combine
import Photos

class MainFlowCoordinator: ObservableObject {
    // Reference to parent coordinator
    weak var parent: AppCoordinator?
    
    // Current route within the main flow
    @Published var currentRoute: NavigationRoute = .photoGroup
    
    // Modal presentation states
    @Published var showingDeletePreview = false
    @Published var deletePreviews: [DeletePreviewEntry] = []
    
    // Services
    private let photoManager = PhotoManager.shared
    private let toastService = ToastService.shared
    
    init(parent: AppCoordinator) {
        self.parent = parent
    }
    
    // Navigate to a specific photo group for swiping
    func navigateToSwipeCards(photoGroupId: String) {
        withAnimation {
            currentRoute = .swipeCard(photoGroupId: photoGroupId)
        }
    }
    
    // Return to photo groups list
    func navigateToPhotoGroups() {
        withAnimation {
            currentRoute = .photoGroup
        }
    }
    
    // Show delete preview modal with selected photos
    func showDeletePreview(photos: [DeletePreviewEntry]) {
        self.deletePreviews = photos
        self.showingDeletePreview = true
    }
    
    // Hide delete preview modal
    func hideDeletePreview() {
        self.showingDeletePreview = false
        self.deletePreviews = []
    }
    
    // Confirm deletion of photos
    func confirmDeletion(of photos: [DeletePreviewEntry]) {
        Task {
            await photoManager.deletePhotos(from: photos)
            await MainActor.run {
                hideDeletePreview()
                toastService.show(message: "Photos deleted", type: .success)
            }
        }
    }
} 