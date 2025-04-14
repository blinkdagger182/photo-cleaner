import Photos
import SwiftUI
import Combine

@MainActor
class SwipeCardViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentIndex: Int = 0
    @Published var offset = CGSize.zero
    @Published var preloadedImages: [UIImage?] = []
    @Published var isLoading = false
    @Published var previousImage: UIImage? = nil
    @Published var swipeLabel: String? = nil
    @Published var swipeLabelColor: Color = .green
    @Published var deletePreviewEntries: [DeletePreviewEntry] = []
    @Published var showDeletePreview = false
    
    // MARK: - Internal Properties
    private let group: PhotoGroup
    var photoManager: PhotoManager!
    var toast: ToastService!
    private var hasStartedLoading = false
    private var viewHasAppeared = false
    private let maxBufferSize = 5  // Keep only 5 images in memory
    private let preloadThreshold = 3  // Start preloading when 3 images away from end
    private let lastViewedIndexKeyPrefix = "LastViewedIndex_"
    private var loadedCount = 0
    private var imageFetchTasks: [Int: Task<UIImage?, Never>] = [:]
    
    // Track high-quality image loading status separately
    private var highQualityImagesStatus: [Int: Bool] = [:]
    private let highQualityPreloadCount = 3  // Number of high-quality images to preload ahead
    
    // Add a reference to the forceRefresh binding
    var forceRefreshCallback: (() -> Void)?
    
    // MARK: - Initialization
    init(group: PhotoGroup, photoManager: PhotoManager? = nil, toast: ToastService? = nil) {
        self.group = group
        self.photoManager = photoManager
        self.toast = toast
        
        // Initialize currentIndex from saved value
        self.currentIndex = UserDefaults.standard.integer(
            forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        guard photoManager != nil, toast != nil else {
            print("Warning: photoManager or toast not set before onAppear")
            return
        }
        
        viewHasAppeared = true
        startPreloading()
    }
    
    func onDisappear() {
        saveProgress()
        clearMemory()
        cancelAllImageTasks()
    }
    
    func handleDragGesture(value: DragGesture.Value) {
        // Only allow dragging if the image is fully loaded
        if isCurrentImageReadyForInteraction() {
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
        } else {
            // Don't update offset but show swipe label briefly
            if abs(value.translation.width) > 20 && !toast.isVisible {
                // Reset offset to zero to prevent any card movement
                offset = .zero
                toast.show("Please wait for the image to fully load before swiping", duration: 2.0)
            }
        }
    }
    
    func handleDragGestureEnd(value: DragGesture.Value) {
        if isCurrentImageReadyForInteraction() {
            handleSwipeGesture(value)
        }
        swipeLabel = nil
    }
    
    func handleLeftSwipe() {
        guard let asset = group.asset(at: currentIndex) else { return }
        
        photoManager.markForDeletion(asset)
        
        // Add the current image to the deletion preview if available
        if currentIndex < preloadedImages.count, let currentImage = preloadedImages[currentIndex] {
            // Add image to deleted preview collection
            photoManager.addToDeletedImagesPreview(asset: asset, image: currentImage)
        }
        
        toast.show(
            "Marked for deletion. Press Next to permanently delete from storage.", action: "Undo"
        ) {
            self.photoManager.restoreToPhotoGroups(asset, inMonth: self.group.monthDate)
            self.refreshCard(at: self.currentIndex, with: asset)
            self.photoManager.unmarkForDeletion(asset)
        }
        
        Task { await moveToNext() }
    }
    
    func handleRightSwipe() {
        Task { await moveToNext() }
    }
    
    func handleBookmark() {
        guard let asset = group.asset(at: currentIndex) else { return }
        
        photoManager.bookmarkAsset(asset)
        photoManager.markForFavourite(asset)
        
        toast.show("Photo saved", action: "Undo") {
            self.photoManager.removeAsset(asset, fromAlbumNamed: "Saved")
            self.refreshCard(at: self.currentIndex, with: asset)
            self.photoManager.unmarkForDeletion(asset)
        }
        
        Task { await moveToNext() }
    }
    
    func prepareDeletePreview() {
        // First, add any images from current group that might be missing in the preview
        for index in 0..<group.count {
            guard let asset = group.asset(at: index) else { continue }
            
            if photoManager.isMarkedForDeletion(asset) {
                // If the asset is marked but not already in preview, add it
                let existingEntry = photoManager.deletedImagesPreview.contains { $0.asset.localIdentifier == asset.localIdentifier }
                
                if !existingEntry, let optionalImage = preloadedImages[safe: index], let loadedImage = optionalImage {
                    photoManager.addToDeletedImagesPreview(asset: asset, image: loadedImage)
                }
            }
        }
        
        // Use the shared collection of deleted images for preview
        deletePreviewEntries = photoManager.deletedImagesPreview
        showDeletePreview = true
    }
    
    func isCurrentImageReadyForInteraction() -> Bool {
        guard currentIndex < preloadedImages.count else { return false }
        
        // Check if the current image is loaded in high quality
        return preloadedImages[currentIndex] != nil && highQualityImagesStatus[currentIndex] == true
    }
    
    // MARK: - Private Methods
    
    private func startPreloading() {
        guard viewHasAppeared, group.count > 0, !hasStartedLoading else { return }
        
        hasStartedLoading = true
        isLoading = true
        
        // Set preloading flag to true to prevent unnecessary reloads
        photoManager.setPreloadingState(true)
        
        Task {
            resetViewState()
            
            // First, load thumbnails for the first few images
            await loadImagesInRange(
                from: currentIndex,
                count: min(maxBufferSize, group.count - currentIndex),
                quality: .thumbnail
            )
            
            // Then load higher quality for current card and next few cards
            let preloadCount = min(highQualityPreloadCount, group.count - currentIndex)
            for i in 0..<preloadCount {
                let index = currentIndex + i
                if index < group.count {
                    await loadImage(at: index, quality: .screen)
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
            
            // Reset preloading flag
            photoManager.setPreloadingState(false)
            
            // Trigger UI refresh after initial loading is complete
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.forceRefreshCallback?()
                }
            }
        }
    }
    
    private func resetViewState() {
        currentIndex = UserDefaults.standard.integer(
            forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
        withAnimation(.none) {
            offset = .zero
        }
        preloadedImages = []
        loadedCount = 0
        highQualityImagesStatus = [:]
    }
    
    private func saveProgress() {
        photoManager.updateLastViewedIndex(for: group.id, index: currentIndex)
        UserDefaults.standard.set(
            currentIndex, forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
    }
    
    private func moveToNext() async {
        let nextIndex = currentIndex + 1
        
        if nextIndex < group.count {
            // Store the current image as previous before moving to next
            if currentIndex < preloadedImages.count, let currentImage = preloadedImages[currentIndex] {
                await MainActor.run {
                    previousImage = currentImage
                }
            }
            
            // Update the index to maintain UI responsiveness
            await MainActor.run {
                currentIndex = nextIndex
            }
            
            // Set preloading flag to prevent unnecessary reloads
            photoManager.setPreloadingState(true)
            
            // Clean up old images to free memory
            await cleanupOldImages()
            
            // Check if we need to preload more thumbnails
            let thumbnailPreloadThreshold = 3
            if nextIndex + thumbnailPreloadThreshold >= loadedCount && loadedCount < group.count {
                // Load the next batch of thumbnails
                let nextBatchStart = loadedCount
                let nextBatchCount = min(maxBufferSize, group.count - nextBatchStart)
                
                if nextBatchCount > 0 {
                    await loadImagesInRange(
                        from: nextBatchStart, 
                        count: nextBatchCount,
                        quality: .thumbnail
                    )
                }
            }
            
            // Proactively load high-quality images for the next few indices
            for offset in 0..<highQualityPreloadCount {
                let indexToLoad = nextIndex + offset
                if indexToLoad < group.count && highQualityImagesStatus[indexToLoad] != true {
                    await loadImage(at: indexToLoad, quality: .screen)
                }
            }
            
            // Reset preloading flag after all loading is complete
            photoManager.setPreloadingState(false)
        }
    }
    
    private func refreshCard(at index: Int, with asset: PHAsset) {
        if index < preloadedImages.count {
            preloadedImages[index] = nil
            highQualityImagesStatus[index] = false
        } else {
            preloadedImages.insert(nil, at: index)
        }
        
        loadedCount = preloadedImages.count
        
        Task {
            await loadImage(at: index, quality: .screen)
        }
        
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }
    
    func clearMemory() {
        // Set preloading flag to prevent unnecessary reloads
        photoManager.setPreloadingState(true)
        
        // Keep only the current image, clear everything else
        if !preloadedImages.isEmpty && currentIndex < preloadedImages.count {
            let currentImage = preloadedImages[currentIndex]
            preloadedImages = Array(repeating: nil, count: preloadedImages.count)
            highQualityImagesStatus = [:]
            
            if currentIndex < preloadedImages.count {
                preloadedImages[currentIndex] = currentImage
                highQualityImagesStatus[currentIndex] = true
            }
        }
        
        // Reset preloading flag after memory cleanup
        photoManager.setPreloadingState(false)
    }
    
    private func cleanupOldImages() async {
        await MainActor.run {
            // Keep current and next few images, remove everything before that
            if currentIndex > maxBufferSize {
                // Determine the cutoff point - we want to keep only from (currentIndex - n) onwards
                let cutoffIndex = currentIndex - maxBufferSize
                
                // Create a new array with nil for old images to free memory
                var newImages = Array(repeating: nil as UIImage?, count: cutoffIndex)
                
                // Append the images we want to keep
                if currentIndex < preloadedImages.count {
                    newImages.append(contentsOf: preloadedImages[cutoffIndex...])
                }
                
                preloadedImages = newImages
                
                // Also clean up the high-quality status dictionary
                var newStatus: [Int: Bool] = [:]
                for (index, status) in highQualityImagesStatus where index >= cutoffIndex {
                    newStatus[index] = status
                }
                highQualityImagesStatus = newStatus
                
                // Cancel tasks for indices that are no longer needed
                for (index, task) in imageFetchTasks where index < cutoffIndex {
                    task.cancel()
                    imageFetchTasks.removeValue(forKey: index)
                }
                
                // Force a memory cleanup
                autoreleasepool {}
            }
        }
    }
    
    private func handleSwipeGesture(_ value: DragGesture.Value) {
        let threshold: CGFloat = 100
        if value.translation.width < -threshold {
            handleLeftSwipe()
        } else if value.translation.width > threshold {
            handleRightSwipe()
        }
        withAnimation(.spring()) {
            withAnimation(.none) {
                offset = .zero
            }
        }
    }
    
    // MARK: - Image Loading
    
    enum ImageQuality {
        case thumbnail
        case screen
    }
    
    private func loadImagesInRange(from startIndex: Int, count: Int, quality: ImageQuality) async {
        guard startIndex < group.count else { return }
        
        let endIndex = min(startIndex + count, group.count)
        
        // Make sure preloadedImages array has enough slots
        await MainActor.run {
            while preloadedImages.count < endIndex {
                preloadedImages.append(nil)
            }
        }
        
        // Load images in parallel but with limited concurrency
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for i in startIndex..<endIndex {
                group.addTask {
                    let image = await self.loadImage(at: i, quality: quality)
                    return (i, image)
                }
            }
            
            // Process results as they complete
            for await (index, image) in group {
                if quality == .thumbnail {
                    // Only update if there's no high-quality image already
                    await MainActor.run {
                        if index < self.preloadedImages.count && self.highQualityImagesStatus[index] != true {
                            self.preloadedImages[index] = image
                        }
                    }
                }
            }
        }
        
        loadedCount = max(loadedCount, endIndex)
    }
    
    private func loadImage(at index: Int, quality: ImageQuality) async -> UIImage? {
        guard index < group.count, let asset = group.asset(at: index) else { return nil }
        
        // For high-quality requests, check if we already have this loaded
        if quality == .screen && highQualityImagesStatus[index] == true {
            return preloadedImages[index]
        }
        
        // Cancel any existing task for this index if it's the same quality level or upgrading from thumbnail
        // We don't want to cancel a high-quality request when a thumbnail request comes in
        let taskKey = "\(index)-\(quality == .screen ? "high" : "low")"
        imageFetchTasks[index]?.cancel()
        
        // Create and store a new task
        let task = Task {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.version = .current
            
            // Configure based on quality level
            switch quality {
            case .thumbnail:
                options.deliveryMode = .fastFormat
                options.resizeMode = .fast
            case .screen:
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
            }
            
            // Determine target size based on quality
            let targetSize: CGSize
            switch quality {
            case .thumbnail:
                targetSize = CGSize(width: 300, height: 300)
            case .screen:
                let scale = UIScreen.main.scale
                let screenSize = UIScreen.main.bounds.size
                targetSize = CGSize(
                    width: min(screenSize.width * scale, 1200),
                    height: min(screenSize.height * scale, 1200)
                )
            }
            
            let image = await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, _ in
                    continuation.resume(returning: image)
                }
            }
            
            // Process the image if needed to avoid DisplayP3 color space issues
            let processedImage = await convertToStandardColorSpaceIfNeeded(image)
            
            // Update UI with image
            if !Task.isCancelled {
                await MainActor.run {
                    // Check if we're still in a valid range
                    if index < self.preloadedImages.count {
                        // If this is a high-quality image, always update
                        if quality == .screen {
                            self.preloadedImages[index] = processedImage
                            self.highQualityImagesStatus[index] = true
                        } 
                        // If it's a thumbnail, only update if we don't have the high-quality yet
                        else if self.highQualityImagesStatus[index] != true {
                            self.preloadedImages[index] = processedImage
                        }
                    }
                }
            }
            
            // Also prefetch metadata in background to avoid warnings
            if !Task.isCancelled {
                await prefetchAssetMetadata(asset: asset)
            }
            
            return processedImage
        }
        
        imageFetchTasks[index] = task
        
        do {
            return try await task.value
        } catch {
            return nil
        }
    }
    
    private func prefetchAssetMetadata(asset: PHAsset) async {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        options.canHandleAdjustmentData = { _ in return false }
        
        _ = await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: input != nil)
            }
        }
    }
    
    private func convertToStandardColorSpaceIfNeeded(_ image: UIImage?) async -> UIImage? {
        guard let image = image else { return nil }
        
        // Check if the image is using DisplayP3 color space
        if let colorSpace = image.cgImage?.colorSpace,
           let colorSpaceName = colorSpace.name as String?,
           colorSpaceName.contains("P3") {
            // Convert to sRGB to avoid the DisplayP3 headroom errors
            return await Task.detached {
                let format = UIGraphicsImageRendererFormat()
                format.preferredRange = .standard
                format.scale = image.scale
                
                let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
                let convertedImage = renderer.image { context in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
                
                return convertedImage
            }.value
        }
        
        return image
    }
    
    private func cancelAllImageTasks() {
        for (_, task) in imageFetchTasks {
            task.cancel()
        }
        imageFetchTasks.removeAll()
    }
} 
