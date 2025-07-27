import SwiftUI
import Photos
import Combine

@MainActor
class PhotoGroupViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedGroup: PhotoGroup?
    @Published var viewByYear = true
    @Published var shouldForceRefresh = false
    @Published var fadeIn = false
    @Published var yearGroups: [YearGroup] = []
    @Published var photoGroups: [PhotoGroup] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    private let photoManager: PhotoManager
    
    // MARK: - Computed Properties
    // This property filters photoGroups to only show system albums in "My Albums" view
    var filteredPhotoGroups: [PhotoGroup] {
        if viewByYear {
            // This shouldn't be used when viewByYear is true, but return empty for safety
            return []
        } else {
            // Show only system albums in the "My Albums" view
            let systemAlbumNames = ["Maybe?", "Deleted"]
            return photoGroups.filter { systemAlbumNames.contains($0.title) }
        }
    }
    
    // MARK: - Initialization
    init(photoManager: PhotoManager) {
        self.photoManager = photoManager
        
        // Set up bindings to photoManager
        setupBindings()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Create bindings to photoManager properties
        photoManager.$yearGroups.assign(to: &$yearGroups)
        photoManager.$photoGroups.assign(to: &$photoGroups)
        photoManager.$authorizationStatus.assign(to: &$authorizationStatus)
    }
    
    // MARK: - Public Methods
    func triggerFadeInAnimation() {
        withAnimation(.easeIn(duration: 0.5)) {
            fadeIn = true
        }
    }
    
    func openPhotoLibraryPicker(from viewController: UIViewController) {
        let selector = NSSelectorFromString("presentLimitedLibraryPickerFromViewController:")
        if PHPhotoLibrary.shared().responds(to: selector) {
            PHPhotoLibrary.shared().perform(selector, with: viewController)
        }
    }
    
    func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    func updateSelectedGroup(_ group: PhotoGroup?) {
        selectedGroup = group
    }
    
    func toggleViewMode() {
        viewByYear.toggle()
    }
    
    func saveLastViewedIndex(for group: PhotoGroup, index: Int) {
        photoManager.saveLastViewedIndex(index, for: group.id)
    }
    
    func loadLastViewedIndex(for group: PhotoGroup) -> Int {
        photoManager.loadLastViewedIndex(for: group.id)
    }
    
    func refreshData() async {
        await photoManager.refreshAllPhotoGroups()
    }
    
    /// Refreshes photo library data by reloading all photo groups
    /// Used for pull-to-refresh functionality
    func refreshPhotoLibrary() async {
        await photoManager.refreshAllPhotoGroups()
    }
} 