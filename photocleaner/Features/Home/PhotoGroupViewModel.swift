import SwiftUI
import Photos
import PhotosUI

class PhotoGroupViewModel: ObservableObject {
    @Published var yearGroups: [YearGroup] = []
    @Published var savedAlbums: [PhotoGroup] = []
    @Published var viewByYear: Bool = true
    @Published var isLimitedAuthorization: Bool = false
    
    private let coordinator: MainFlowCoordinator
    private let photoManager: PhotoManager
    
    init(coordinator: MainFlowCoordinator, photoManager: PhotoManager = PhotoManager.shared) {
        self.coordinator = coordinator
        self.photoManager = photoManager
        checkAuthorizationStatus()
    }
    
    func loadPhotoGroups() {
        Task {
            await photoManager.refreshAllPhotoGroups()
            
            await MainActor.run {
                self.yearGroups = photoManager.yearGroups
                self.savedAlbums = photoManager.photoGroups.filter { $0.title == "Saved" }
            }
        }
    }
    
    func checkAuthorizationStatus() {
        Task {
            _ = await photoManager.requestAuthorization()
            
//            await MainActor.run {
//                self.isLimitedAuthorization = (status == .limited)
//            }
        }
    }
    
    func presentLimitedLibraryPicker() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
        }
    }
    
    func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
} 
