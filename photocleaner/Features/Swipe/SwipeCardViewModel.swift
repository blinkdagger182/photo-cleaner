import Photos
import SwiftUI
import UIKit

@MainActor
class SwipeCardViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentIndex: Int = 0
    @Published var preloadedImages: [UIImage?] = []
    @Published var loadedCount = 0
    @Published var isLoading = false
    @Published var viewHasAppeared = false
    @Published var hasStartedLoading = false
    @Published var deletePreviewEntries: [DeletePreviewEntry] = []
    @Published var swipeLabel: String? = nil
    @Published var swipeLabelColor: Color = .green
    @Published var offset = CGSize.zero
    @Published var previousImage: UIImage? = nil
    @Published var hasAppeared = false

    // MARK: - Properties
    private let group: PhotoGroup
    var photoManager: PhotoManager
    private var forceRefreshBinding: Binding<Bool>
    private var modalCoordinator: ModalCoordinator?
    private let maxBufferSize = 5  // Keep only 5 images in memory
    private let preloadThreshold = 3  // Start preloading when 3 images away from end
    private let lastViewedIndexKeyPrefix = "LastViewedIndex_"
    
    // Computed properties
    var assets: [PHAsset] {
        return group.assets
    }
    
    var title: String {
        return group.title
    }
    
    // MARK: - Initialization
    init(group: PhotoGroup, photoManager: PhotoManager, forceRefresh: Binding<Bool>, modalCoordinator: ModalCoordinator? = nil) {
        self.group = group
        self.photoManager = photoManager
        self.forceRefreshBinding = forceRefresh
        self.modalCoordinator = modalCoordinator
        
        // Initialize the current index from the stored value
        self.currentIndex = UserDefaults.standard.integer(
            forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
    }
    
    /// Convenience initializer for creating the view model with required dependencies
    static func create(group: PhotoGroup, photoManager: PhotoManager, forceRefresh: Binding<Bool>, modalCoordinator: ModalCoordinator? = nil) -> SwipeCardViewModel {
        return SwipeCardViewModel(group: group, photoManager: photoManager, forceRefresh: forceRefresh, modalCoordinator: modalCoordinator)
    }
    
    // MARK: - Public Methods
    
    func setModalCoordinator(_ coordinator: ModalCoordinator) {
        self.modalCoordinator = coordinator
    }
    
    /// Called when the view appears
    func onAppear() {
        viewHasAppeared = true
        hasAppeared = true
        tryStartPreloading()
        
        // Register for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    /// Called when the view disappears
    func onDisappear() {
        saveProgress()
        clearMemory()
        
        // Remove observer
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        clearMemory()
    }
    
    /// Handles the drag gesture for swiping
    func handleDrag(value: DragGesture.Value) {
        offset = value.translation
        if offset.width > 50 {
            swipeLabel = "Keep"
            swipeLabelColor = .green
        } else if offset.width < -50 {
            swipeLabel = "Delete"
            swipeLabelColor = .red
        } else {
            swipeLabel = nil
        }
    }
    
    /// Handles the end of a drag gesture
    func handleSwipeGesture(_ value: DragGesture.Value) {
        let threshold: CGFloat = 100
        if value.translation.width < -threshold {
            handleLeftSwipe()
        } else if value.translation.width > threshold {
            handleRightSwipe()
        }
        resetOffset()
    }
    
    /// Handles a left swipe (delete)
    func handleLeftSwipe() {
        guard currentIndex < group.assets.count else { return }
        
        let asset = group.assets[currentIndex]
        photoManager.markForDeletion(asset)
        
        Task { await moveToNext() }
    }
    
    /// Handles a bookmark action
    func handleBookmark() {
        guard currentIndex < group.assets.count else { return }
        
        let asset = group.assets[currentIndex]
        photoManager.bookmarkAsset(asset)
        photoManager.markForFavourite(asset)
        
        Task { await moveToNext() }
    }
    
    /// Handles a right swipe (keep)
    func handleRightSwipe() {
        Task { await moveToNext() }
    }
    
    /// Prepares the delete preview
    func prepareDeletePreview() {
        var newEntries: [DeletePreviewEntry] = []
        
        for (index, asset) in group.assets.enumerated() {
            guard photoManager.isMarkedForDeletion(asset) else { continue }
            
            if let optionalImage = preloadedImages[safe: index],
               optionalImage != nil
            {
                // We don't need the actual image, just that it exists
                let entry = DeletePreviewEntry(id: UUID(), asset: asset)
                newEntries.append(entry)
            }
        }
        
        deletePreviewEntries = newEntries
        
        // Use the modal coordinator if available, otherwise fallback to the old behavior
        if let coordinator = modalCoordinator {
            coordinator.showDeletePreview(entries: newEntries, forceRefresh: forceRefreshBinding)
        }
    }
    
    /// Called when a photo is restored to the group
    func restorePhoto(asset: PHAsset) {
        photoManager.restoreToPhotoGroups(asset, inMonth: group.monthDate)
        refreshCard(at: currentIndex, with: asset)
        photoManager.unmarkForDeletion(asset)
    }
    
    /// Called when a photo is removed from saved
    func removeFromSaved(asset: PHAsset) {
        photoManager.removeAsset(asset, fromAlbumNamed: "Saved")
        refreshCard(at: currentIndex, with: asset)
        photoManager.unmarkForDeletion(asset)
    }
    
    // MARK: - Private Methods
    
    private func resetOffset() {
        withAnimation(.spring()) {
            offset = .zero
        }
    }
    
    private func tryStartPreloading() {
        guard viewHasAppeared,
              group.assets.count > 0,
              !hasStartedLoading
        else {
            return
        }
        
        hasStartedLoading = true
        isLoading = true
        
        Task { @MainActor in
            resetViewState()
            
            // First, quickly load thumbnails for the first few images
            await preloadThumbnails(
                from: currentIndex, count: min(5, group.assets.count - currentIndex))
            
            // Then load higher quality for current card
            if currentIndex < group.assets.count {
                await loadHighQualityImage(at: currentIndex)
                
                // Preload next card high quality if available
                if currentIndex + 1 < group.assets.count {
                    await loadHighQualityImage(at: currentIndex + 1)
                }
            }
            
            self.isLoading = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.forceRefreshBinding.wrappedValue.toggle()
            }
        }
    }
    
    private func resetViewState() {
        currentIndex = UserDefaults.standard.integer(
            forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
        if hasAppeared {
            offset = .zero
        } else {
            offset = .zero
        }
        preloadedImages = []
        loadedCount = 0
    }
    
    private func saveProgress() {
        photoManager.updateLastViewedIndex(for: group.id, index: currentIndex)
        UserDefaults.standard.set(
            currentIndex, forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
    }
    
    private func preloadThumbnails(from startIndex: Int, count: Int) async {
        guard startIndex < group.assets.count else { return }
        
        let endIndex = min(startIndex + count, group.assets.count)
        
        // Make sure preloadedImages array has enough slots
        while self.preloadedImages.count < endIndex {
            self.preloadedImages.append(nil)
        }
        
        // Load thumbnails quickly
        for i in startIndex..<endIndex {
            if i >= preloadedImages.count { continue }
            
            let asset = group.assets[i]
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat  // Use fast format for thumbnails
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            // Use a reasonable thumbnail size
            let thumbnailSize = CGSize(width: 300, height: 300)
            
            let image = await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: thumbnailSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, _ in
                    continuation.resume(returning: image)
                }
            }
            
            // Update UI with thumbnail
            if i < self.preloadedImages.count {
                self.preloadedImages[i] = image
            }
        }
        
        self.loadedCount = max(self.loadedCount, endIndex)
    }
    
    private func loadHighQualityImage(at index: Int) async {
        guard index < group.assets.count else { return }
        
        // Make sure preloadedImages array has enough slots
        while self.preloadedImages.count <= index {
            self.preloadedImages.append(nil)
        }
        
        let asset = group.assets[index]
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        // Calculate appropriate image size based on screen
        let scale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(
            width: min(screenSize.width * scale, 1200),  // Cap at 1200px width
            height: min(screenSize.height * scale, 1200)  // Cap at 1200px height
        )
        
        let image = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,  // Use appropriate size, not max size
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
        
        // Update UI with high quality image
        if index < self.preloadedImages.count {
            self.preloadedImages[index] = image
        }
    }
    
    private func moveToNext() async {
        if currentIndex < group.assets.count - 1 {
            currentIndex += 1
            saveProgress()
        } else {
            // We're at the end of the group, refresh the UI with force refresh binding
            if group.monthDate != nil {
                await photoManager.refreshAllPhotoGroups()
                
                // Toggle the force refresh binding to inform the parent view
                forceRefreshBinding.wrappedValue.toggle()
            }
        }
    }
    
    private func cleanupOldImages() async {
        // Keep current and next few images, remove everything before that
        if currentIndex > maxBufferSize {
            // Create a new array with nil for old images to free memory
            var newImages = Array(
                repeating: nil as UIImage?, count: currentIndex - maxBufferSize)
            
            // Append the images we want to keep
            if currentIndex < preloadedImages.count {
                newImages.append(contentsOf: preloadedImages[currentIndex...])
            }
            
            preloadedImages = newImages
            
            // Force a memory cleanup
            autoreleasepool {}
        }
    }
    
    private func clearMemory() {
        // Keep only the current image, clear everything else
        if !preloadedImages.isEmpty && currentIndex < preloadedImages.count {
            let currentImage = preloadedImages[currentIndex]
            preloadedImages = Array(repeating: nil, count: preloadedImages.count)
            if currentIndex < preloadedImages.count {
                preloadedImages[currentIndex] = currentImage
            }
        }
    }
    
    private func refreshCard(at index: Int, with asset: PHAsset) {
        if index < preloadedImages.count {
            preloadedImages[index] = nil
        } else {
            preloadedImages.insert(nil, at: index)
        }
        
        loadedCount = preloadedImages.count
        
        Task {
            await preloadSingleImage(at: index)
        }
        
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }
    
    private func preloadSingleImage(at index: Int) async {
        await loadImageForAsset(group.assets[index], at: index)
    }
    
    private func loadImageForAsset(_ asset: PHAsset, at index: Int) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        // Calculate appropriate image size based on screen
        let scale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(
            width: min(screenSize.width * scale, 1200),  // Cap at 1200px width
            height: min(screenSize.height * scale, 1200)  // Cap at 1200px height
        )
        
        // First load thumbnail
        let thumbnailSize = CGSize(width: 300, height: 300)
        let thumbnail = await loadImage(for: asset, targetSize: thumbnailSize, options: options)
        
        // Update UI with thumbnail
        if index < self.preloadedImages.count {
            self.preloadedImages[index] = thumbnail
        }
        
        // Then load screen-sized image (not full resolution) if needed
        if index >= currentIndex && index < currentIndex + 2 {
            let screenImage = await loadImage(for: asset, targetSize: targetSize, options: options)
            if index < self.preloadedImages.count {
                self.preloadedImages[index] = screenImage
            }
        }
    }
    
    private func loadImage(for asset: PHAsset, targetSize: CGSize, options: PHImageRequestOptions) async -> UIImage? {
        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - Helper Extensions
// The Array+Safe extension is already defined in Extensions/Array+Safe.swift

extension PHAsset {
    var estimatedAssetSize: Int {
        let resources = PHAssetResource.assetResources(for: self)
        return resources.first?.value(forKey: "fileSize") as? Int ?? 0
    }
}
