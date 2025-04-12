import SwiftUI
import Photos

class PhotoGroupViewModel: ObservableObject {
    @Published var yearGroups: [YearGroup] = []
    @Published var savedAlbums: [PhotoGroup] = []
    @Published var viewByYear: Bool = true
    @Published var isLimitedAuthorization: Bool = false
    
    private let coordinator: MainFlowCoordinator
    private let photoManager = PhotoManager.shared
    
    init(coordinator: MainFlowCoordinator) {
        self.coordinator = coordinator
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
            let status = await photoManager.requestAuthorization()
            
            await MainActor.run {
                self.isLimitedAuthorization = (status == .limited)
            }
        }
    }
    
    func presentLimitedLibraryPicker() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            let selector = NSSelectorFromString("presentLimitedLibraryPickerFromViewController:")
            if PHPhotoLibrary.shared().responds(to: selector) {
                PHPhotoLibrary.shared().perform(selector, with: root)
            }
        }
    }
    
    func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
} 