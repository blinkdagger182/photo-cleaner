import Photos
import SwiftUI
import Combine
import UIKit
import UniformTypeIdentifiers

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
    @Published var showDeletePreview = false
    @Published var showRCPaywall = false
    @Published var isSharing = false
    @Published var discoverSwipeTracker: DiscoverSwipeTracker? = nil
    
    // MARK: - Internal Properties
    private let group: PhotoGroup
    var photoManager: PhotoManager!
    var toast: ToastService!
    var imageViewTracker: ImageViewTracker?
    var isDiscoverTab: Bool = false
    private var hasStartedLoading = false
    private var viewHasAppeared = false
    private let maxBufferSize = 8  // Reduced from 10 to 8 images in memory to reduce memory pressure
    private let preloadThreshold = 3  // Reduced from 5 to 3 images ahead for preloading
    private let lastViewedIndexKeyPrefix = "LastViewedIndex_"
    private var loadedCount = 0
    private var imageFetchTasks: [Int: Task<UIImage?, Never>] = [:]
    private var imageLoadingTimeouts: [Int: DispatchWorkItem] = [:]
    private var loadRetryCount: [Int: Int] = [:]
    private let maxRetryCount = 2  // Reduced from 3 to 2 for faster failure
    private var concurrentLoadsCount = 0 // Track how many images are loading simultaneously
    private let maxConcurrentLoads = 2 // Limit concurrent loads to avoid overloading
    private var pendingIndices: [Int] = [] // Queue of pending image loads
    
    // Store request IDs for PHImageManager requests
    private var requestIDs: [Int: Int] = [:]
    
    // Haptic feedback generator
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // Callback for fly-off animation
    var triggerLabelFlyOff: ((String, Color, CGSize) -> Void)? = nil
    
    // Track high-quality image loading status separately
    private var highQualityImagesStatus: [Int: Bool] = [:]
    private let highQualityPreloadCount = 5  // Increased from 3 to 5 high-quality images to preload
    
    // Add a reference to the forceRefresh binding
    var forceRefreshCallback: (() -> Void)?
    
    // MARK: - Initialization
    init(group: PhotoGroup, photoManager: PhotoManager? = nil, toast: ToastService? = nil, imageViewTracker: ImageViewTracker? = nil, isDiscoverTab: Bool = false) {
        self.group = group
        self.photoManager = photoManager
        self.toast = toast
        self.imageViewTracker = imageViewTracker
        self.isDiscoverTab = isDiscoverTab
        self.discoverSwipeTracker = isDiscoverTab ? DiscoverSwipeTracker.shared : nil
        
        // Initialize currentIndex from saved value
        self.currentIndex = UserDefaults.standard.integer(
            forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
            
        // Prepare haptic feedback generator
        feedbackGenerator.prepare()
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        guard photoManager != nil, toast != nil else {
            print("Warning: photoManager or toast not set before onAppear")
            return
        }
        
        // Initialize discoverSwipeTracker if this is the discover tab
        if isDiscoverTab && discoverSwipeTracker == nil {
            discoverSwipeTracker = DiscoverSwipeTracker.shared
        }
        
        viewHasAppeared = true
        startPreloading()
    }
    
    func onDisappear() {
        print("SwipeCardViewModel: saving progress with currentIndex = \(currentIndex)")
        saveProgress() // Save the currentIndex for this specific group
        clearMemory()
        cancelAllImageTasks()
    }
    
    func handleDragGesture(value: DragGesture.Value) {
        // Only allow dragging if the image is fully loaded
        if isCurrentImageReadyForInteraction() {
            // Use the full translation value for natural 2D movement
            offset = value.translation
            
            // Update the swipe label based on horizontal movement
            if offset.width > 50 {
                swipeLabel = "Keep"
                swipeLabelColor = .green
            } else if offset.width < -50 {
                swipeLabel = "Delete"
                swipeLabelColor = Color(red: 0.55, green: 0.35, blue: 0.98)
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
            handleSwipeGesture(value: value)
        } else {
            // Even if the image isn't ready for interaction, we need to reset the offset
            // This ensures the card always springs back on the first drag
            withAnimation(.interpolatingSpring(
                stiffness: 300,
                damping: 30,
                initialVelocity: 1.0)) {
                offset = .zero
            }
        }
        swipeLabel = nil
    }
    
    func handleSwipeGesture(value: DragGesture.Value) {
        let threshold: CGFloat = 100
        let velocity = value.predictedEndLocation.x - value.location.x
        
        // Check if swipe exceeds threshold or has significant velocity
        if value.translation.width < -threshold || (value.translation.width < -50 && velocity < -300) {
            // Delete swipe (left) - call our direct animation method instead
            triggerDeleteAnimationDirectly() 
        } else if value.translation.width > threshold || (value.translation.width > 50 && velocity > 300) {
            // Keep swipe (right) - call our direct animation method instead
            triggerKeepAnimationDirectly()
        } else {
            // Non-action territory - Spring back to center
            let springResponse = 0.55 // Faster spring for more responsive feel
            let springDampingFraction = 0.7 // Good balance of bounce and control
            
            withAnimation(.interpolatingSpring(
                stiffness: 300,
                damping: 30,
                initialVelocity: CGFloat(abs(velocity)) / 500.0)) {
                offset = .zero
            }
        }
    }
    
    // Improved version of moveToNext that adds a fade-in animation for the next card
    // and tracks image views for subscription threshold
    private func moveToNextWithAnimation() async {
        let nextIndex = currentIndex + 1
        
        await MainActor.run {
            // Preload the next image
            preloadNextImageIfNeeded()

            // Track image view count for general subscription threshold
            imageViewTracker?.incrementViewCount()
            
            // Note: We don't increment the swipe count here anymore as it's now handled
            // directly in the trigger methods to avoid double counting
            // However, we still need to update the paywall state in case it wasn't checked elsewhere
            if isDiscoverTab && !SubscriptionManager.shared.isPremium {
                if discoverSwipeTracker == nil {
                    discoverSwipeTracker = DiscoverSwipeTracker.shared
                }
                showRCPaywall = discoverSwipeTracker?.showRCPaywall ?? false
            }

        }
        
        if nextIndex < group.count {
            // Store the current image as previous before moving to next
            if currentIndex < preloadedImages.count, let currentImage = preloadedImages[currentIndex] {
                await MainActor.run {
                    previousImage = currentImage
                }
            }
            
            // Update the index with nice animation for the next card
            await MainActor.run {
                // Reset offset first (not visible since we'll animate in the card)
                // withAnimation(.none) {
                //     offset = .zero
                // }
                
                // // Now update the index to show the next card
                // currentIndex = nextIndex
                
                // Animate the opacity of the next card for a nice transition
                // This is handled in the view
                currentIndex = nextIndex
                offset = .zero
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
    
    // These methods should not be called directly now, all logic is moved to the animation handlers
    func handleLeftSwipe() {
        guard let asset = group.asset(at: currentIndex) else { return }
        let capturedIndex = currentIndex
        
        // Start loading next image immediately
        Task {
            if capturedIndex + 1 < group.count {
                await loadImage(at: capturedIndex + 1, quality: .screen)
            }
        }
        
        photoManager.markForDeletion(asset)
        
        // Add the current image to the deletion preview if available
        if currentIndex < preloadedImages.count, let currentImage = preloadedImages[currentIndex] {
            // Add image to deleted preview collection
            photoManager.addToDeletedImagesPreview(asset: asset, image: currentImage)
        }
        
        // Move to next immediately instead of waiting for toast dismissal
        Task { await self.moveToNext() }
        
        toast.show(
            "Marked for deletion. Press Next to permanently delete from storage.", action: "Undo"
        ) {
            // Undo Action - Use capturedIndex
            self.photoManager.restoreToPhotoGroups(asset, inMonth: self.group.monthDate)
            self.photoManager.unmarkForDeletion(asset)
            // Animate the state reset using capturedIndex
            withAnimation {
                self.currentIndex = capturedIndex
                self.offset = .zero
            }
        } onDismiss: {
            // No need to move to next as it already happened
        }
    }
    
    func handleRightSwipe() {
        // Capture the index before moving to next
        let capturedIndex = currentIndex
        
        // Start loading next image immediately
        Task {
            if capturedIndex + 1 < group.count {
                await loadImage(at: capturedIndex + 1, quality: .screen)
            }
        }
        
        Task { await moveToNext() }
    }
    
    func handleBookmark() {
        guard let asset = group.asset(at: currentIndex) else { return }
        // Capture the index *before* showing the toast
        let capturedIndex = currentIndex
        
        // Start loading next image immediately
        Task {
            if capturedIndex + 1 < group.count {
                await loadImage(at: capturedIndex + 1, quality: .screen)
            }
        }
        
        photoManager.bookmarkAsset(asset)
        photoManager.markForFavourite(asset)
        
        // Move to next immediately instead of waiting for toast dismissal
        Task { await self.moveToNext() }
        
        toast.show("Photo marked as Maybe?", action: "Undo") {
            // Undo Action - Use capturedIndex
            self.photoManager.removeAsset(asset, fromAlbumNamed: "Maybe?")
            self.photoManager.unmarkForFavourite(asset)
            // Animate the state reset using capturedIndex
            withAnimation {
                self.currentIndex = capturedIndex // Use capturedIndex
                self.offset = .zero
            }
        } onDismiss: {
            // No need to move to next as it already happened
        }
    }
    
    func prepareDeletePreview() {
        // First, ensure any images from current group are added to the PhotoManager's tracking
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
        
        // Simply show the delete preview
        showDeletePreview = true
    }
    
    func onDeletePreviewDismissed() {
        // Just set the flag to false
        showDeletePreview = false
    }
    
    func isCurrentImageReadyForInteraction() -> Bool {
        guard currentIndex < preloadedImages.count else { return false }
        
        // Check if the current image is loaded in high quality or at least exists
        // This ensures we don't get stuck on a loading spinner if the image is visible
        return preloadedImages[currentIndex] != nil && 
              (highQualityImagesStatus[currentIndex] == true || highQualityImagesStatus[currentIndex] == nil)
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
        
        await MainActor.run {
            // Track image view count for general subscription threshold
            imageViewTracker?.incrementViewCount()
            
            // Note: We don't increment the swipe count here anymore as it's now handled
            // directly in the trigger methods to avoid double counting
            // However, we still need to update the paywall state in case it wasn't checked elsewhere
            if isDiscoverTab && !SubscriptionManager.shared.isPremium {
                if discoverSwipeTracker == nil {
                    discoverSwipeTracker = DiscoverSwipeTracker.shared
                }
                showRCPaywall = discoverSwipeTracker?.showRCPaywall ?? false
            }
        }
        
        if nextIndex < group.count {
            // Store the current image as previous before moving to next
            if currentIndex < preloadedImages.count, let currentImage = preloadedImages[currentIndex] {
                await MainActor.run {
                    previousImage = currentImage
                }
            }
            
            // Reset the offset to zero before updating the index
            // This ensures the next card appears in the center
            await MainActor.run {
                withAnimation(.none) {
                    offset = .zero
                }
                // Now update the index after resetting the position
                currentIndex = nextIndex
            }
            
            // Set preloading flag to prevent unnecessary reloads
            photoManager.setPreloadingState(true)
            
            // Clean up old images to free memory with our improved sliding window
            await cleanupOldImages()
            
            // Always ensure we have thumbnails loaded for at least the next 5 images
            // regardless of what loadedCount says
            let thumbnailEndIndex = min(nextIndex + 5, group.count)
            for i in nextIndex..<thumbnailEndIndex {
                if i >= preloadedImages.count || preloadedImages[i] == nil {
                    await loadImage(at: i, quality: .thumbnail)
                }
            }
            
            // Update loadedCount to ensure it reflects our actual progress
            loadedCount = max(loadedCount, thumbnailEndIndex)
            
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
            // Implement a true sliding window approach that works beyond the buffer size
            
            // Calculate window boundaries - keep images from (currentIndex - 5) to (currentIndex + 5)
            let windowStart = max(0, currentIndex - 5)
            let windowEnd = min(group.count - 1, currentIndex + 5)
            
            // Ensure the preloadedImages array has enough slots
            while preloadedImages.count < windowEnd + 1 {
                preloadedImages.append(nil)
            }
            
            // Clear images outside the window to free memory
            for i in 0..<preloadedImages.count {
                if i < windowStart || i > windowEnd {
                    preloadedImages[i] = nil
                    highQualityImagesStatus.removeValue(forKey: i)
                    
                    // Cancel any pending tasks for this index
                    imageFetchTasks[i]?.cancel()
                    imageFetchTasks.removeValue(forKey: i)
                    
                    // Cancel any pending timeouts
                    if let timeoutItem = imageLoadingTimeouts[i] {
                        timeoutItem.cancel()
                        imageLoadingTimeouts.removeValue(forKey: i)
                    }
                }
            }
            
            // Force a memory cleanup
            autoreleasepool {}
            
            // Proactively start loading images in the forward part of the window
            Task {
                // Prioritize loading the current and next few images
                for i in currentIndex..<min(currentIndex + 5, group.count) {
                    if i < preloadedImages.count && (preloadedImages[i] == nil || highQualityImagesStatus[i] != true) {
                        // First try to get a thumbnail quickly
                        if preloadedImages[i] == nil {
                            _ = await loadImage(at: i, quality: .thumbnail)
                        }
                        
                        // Then get high quality if needed
                        if highQualityImagesStatus[i] != true {
                            _ = await loadImage(at: i, quality: .screen)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Image Loading
    
    enum ImageQuality {
        case thumbnail
        case screen
        case highQuality
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
        
        // Load images in parallel but with limited concurrency (max 3 concurrent loads)
        await withTaskGroup(of: (Int, UIImage?).self, returning: Void.self) { group in
            // Limit concurrency to 3 to prevent memory issues and reduce contention
            let maxConcurrentLoads = 3
            var activeLoads = 0
            
            for i in startIndex..<endIndex {
                // Wait if we already have max concurrent loads
                if activeLoads >= maxConcurrentLoads {
                    // Wait for a load to complete before starting a new one
                    _ = await group.next()
                    activeLoads -= 1
                }
                
                group.addTask {
                    activeLoads += 1
                    let image = await self.loadImage(at: i, quality: quality)
                    return (i, image)
                }
            }
            
            // Process all remaining results
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
    
    @MainActor
    func loadImage(at index: Int, quality: ImageQuality = .screen) async -> UIImage? {
        print("SwipeCardViewModel: Loading image at index \(index), concurrent loads: \(concurrentLoadsCount)")
        
        // Return existing image if we already have it
        if index < preloadedImages.count, let existingImage = preloadedImages[index] {
            return existingImage
        }
        
        // Make sure the index is valid
        guard index >= 0, index < group.count else {
            print("SwipeCardViewModel: Invalid index \(index)")
            return nil
        }
        
        // Make sure we don't exceed the maximum concurrent loads
        let shouldQueue = concurrentLoadsCount >= maxConcurrentLoads
        if shouldQueue {
            // Add to pending queue if too many concurrent loads
            if !pendingIndices.contains(index) {
                pendingIndices.append(index)
                print("SwipeCardViewModel: Queuing index \(index), current queue: \(pendingIndices)")
            }
            return nil
        }
        
        // Cancel any existing task for this index
        cancelImageTask(index: index)
        
        // Get the asset for this index
        guard let asset = group.asset(at: index) else {
            print("SwipeCardViewModel: No asset at index \(index)")
            return nil
        }
        
        // Track this load
        concurrentLoadsCount += 1
        
        // Calculate target size based on screen scale for more efficient loading
        let screenSize = UIScreen.main.bounds.size
        let screenScale = UIScreen.main.scale
        var targetSize = CGSize(
            width: screenSize.width * screenScale * 1.2,
            height: screenSize.height * screenScale * 1.2
        )
        
        if quality == .thumbnail {
            // Smaller size for thumbnails
            targetSize = CGSize(
                width: targetSize.width * 0.5,
                height: targetSize.height * 0.5
            )
        }
        
        // Create PHImageRequestOptions with appropriate settings
        let options = PHImageRequestOptions()
        options.deliveryMode = quality == .highQuality ? .highQualityFormat : .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        // Set a timeout for image loading
        let timeoutDuration: TimeInterval = quality == .highQuality ? 5.0 : 3.0
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            print("SwipeCardViewModel: Image load timeout for index \(index)")
            
            // Clean up the pending request
            DispatchQueue.main.async {
                self.cancelImageTask(index: index)
                self.imageLoadingTimeouts.removeValue(forKey: index)
                self.concurrentLoadsCount = max(0, self.concurrentLoadsCount - 1)
                self.processNextPendingLoad()
            }
        }
        
        // Store the timeout item
        imageLoadingTimeouts[index] = timeoutItem
        
        // Schedule the timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDuration, execute: timeoutItem)
        
        // Create a task to load the image
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self = self else { return nil }
            
            // Return result for async/await
            return await withCheckedContinuation { continuation in
                // Flag to track if continuation has been resumed
                var hasResumed = false
                
                // Function to safely resume continuation only once
                func safeResume(with image: UIImage?) {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: image)
                }
                
                let requestId = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: options
                ) { [weak self] image, info in
                    guard let self = self else {
                        safeResume(with: nil)
                        return
                    }
                    
                    // Cancel the timeout
                    if let timeoutItem = self.imageLoadingTimeouts[index] {
                        timeoutItem.cancel()
                        self.imageLoadingTimeouts.removeValue(forKey: index)
                    }
                    
                    // Check if the request was cancelled
                    if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                        print("SwipeCardViewModel: Image request was cancelled for index \(index)")
                        safeResume(with: nil)
                        return
                    }
                    
                    // Check for errors
                    if let error = info?[PHImageErrorKey] as? Error {
                        print("SwipeCardViewModel: Image load error for index \(index): \(error.localizedDescription)")
                        safeResume(with: nil)
                        return
                    }
                    
                    // Check if we got a valid image
                    guard let image = image else {
                        print("SwipeCardViewModel: No image returned for index \(index)")
                        safeResume(with: nil)
                        return
                    }
                    
                    // If this is a degraded image and we requested high quality, 
                    // we might get a better version later, but still return this one
                    if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, 
                       degraded && quality == .highQuality {
                        print("SwipeCardViewModel: Degraded image for high quality request at index \(index)")
                    }
                    
                    safeResume(with: image)
                }
                
                // Store request ID for cancellation
                if let requestId = requestId as? Int {
                    self.requestIDs[index] = requestId
                }
            }
        }
        
        // Store the task for later cancellation
        imageFetchTasks[index] = task
        
        do {
            // Wait for the task to complete
            let result = await task.value
            
            // Clear the task and update state
            imageFetchTasks.removeValue(forKey: index)
            
            // If we got an image, update the preloaded images array
            if let image = result {
                // Ensure the preloadedImages array is large enough
                ensurePreloadedImagesCapacity(upToIndex: index)
                
                // Update the image in the array
                await MainActor.run {
                    preloadedImages[index] = image
                }
            }
            
            // Decrement the concurrent loads count
            concurrentLoadsCount = max(0, concurrentLoadsCount - 1)
            
            // Process the next pending load
            processNextPendingLoad()
            
            return result
        } catch {
            print("SwipeCardViewModel: Image load task error for index \(index): \(error.localizedDescription)")
            
            // Clean up resources
            imageFetchTasks.removeValue(forKey: index)
            concurrentLoadsCount = max(0, concurrentLoadsCount - 1)
            
            // Process the next pending load
            processNextPendingLoad()
            
            return nil
        }
    }

    private func cancelImageTask(index: Int) {
        // Cancel any existing task for this index
        if let task = imageFetchTasks[index] {
            task.cancel()
            imageFetchTasks.removeValue(forKey: index)
        }
        
        // Cancel any pending PHImageManager request
        if let requestId = requestIDs[index] {
            PHImageManager.default().cancelImageRequest(PHImageRequestID(requestId))
            requestIDs.removeValue(forKey: index)
        }
        
        // Cancel any timeout
        if let timeoutItem = imageLoadingTimeouts[index] {
            timeoutItem.cancel()
            imageLoadingTimeouts.removeValue(forKey: index)
        }
    }
    
    private func processNextPendingLoad() {
        // Check if we can process a pending load
        if concurrentLoadsCount < maxConcurrentLoads && !pendingIndices.isEmpty {
            // Get the next index from the queue
            let nextIndex = pendingIndices.removeFirst()
            print("SwipeCardViewModel: Processing queued index \(nextIndex)")
            
            // Load the image in a new task
            Task {
                await loadImage(at: nextIndex)
            }
        }
    }
    
    private func ensurePreloadedImagesCapacity(upToIndex index: Int) {
        // Ensure the preloadedImages array is large enough
        Task { @MainActor in
            while preloadedImages.count <= index {
                preloadedImages.append(nil)
            }
        }
    }

    func preloadNextImageIfNeeded() {
        // Don't preload if we're already at the end
        guard currentIndex < group.count - 1 else { return }
        
        // Preload the next image if it's not already loaded
        let nextIndex = currentIndex + 1
        if nextIndex >= preloadedImages.count || preloadedImages[nextIndex] == nil {
            Task {
                await loadImage(at: nextIndex)
            }
        }
    }
    
    func cancelAllImageTasks() {
        // Cancel all pending image tasks
        for (index, _) in imageFetchTasks {
            cancelImageTask(index: index)
        }
        
        // Clear all pending indices
        pendingIndices.removeAll()
        
        // Reset concurrent loads count
        concurrentLoadsCount = 0
    }
    
    // MARK: - Sharing Functionality
    
    /// Shares the current image in original quality with a promotional link
    func shareCurrentImage() {
        // Check if user has premium subscription
        if !SubscriptionManager.shared.isPremium {
            // Show the paywall after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                self.showRCPaywall = true
            }
            return
        }
        
        guard let asset = group.asset(at: currentIndex) else {
            toast?.show("Unable to share this image", duration: 2.0)
            return
        }
        
        // Set sharing state to true
        isSharing = true
        
        // Show loading indicator
        toast?.show("Preparing high-quality image...", duration: 1.5)
        
        // Load original quality image
        Task {
            do {
                // Try to get the original quality image
                let originalImage = await loadOriginalQualityImage(from: asset)
                
                await MainActor.run {
                    // Check if we have an image - either the high quality one or the current displayed one
                    let imageToShare: UIImage
                    if let originalImage = originalImage {
                        imageToShare = originalImage
                    } else if currentIndex < preloadedImages.count, 
                              let currentDisplayedImage = preloadedImages[currentIndex] {
                        // Fall back to the currently displayed image
                        imageToShare = currentDisplayedImage
                    } else {
                        // If all else fails, use a placeholder
                        if let placeholderImage = UIImage(systemName: "photo") {
                            imageToShare = placeholderImage
                        } else {
                            // Even the placeholder failed, show error and exit
                            toast?.show("Failed to prepare image for sharing", duration: 2.0)
                            isSharing = false
                            return
                        }
                    }
                    
                    // Create sharing sources
                    let imageSource = PhotoSharingActivityItemSource(image: imageToShare, albumTitle: group.title)
                    let textSource = TextSharingActivityItemSource(text: "Organized with PhotoCleaner - The smart way to declutter your photo library!")
                    
                    // Get the rootmost presented view controller
                    func getTopViewController() -> UIViewController? {
                        // Get the root view controller
                        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                              let rootViewController = windowScene.windows.first?.rootViewController else {
                            return nil
                        }
                        
                        var topController = rootViewController
                        
                        // Navigate through presented controllers to find the topmost one
                        while let presentedViewController = topController.presentedViewController {
                            topController = presentedViewController
                        }
                        
                        return topController
                    }
                    
                    // Create and prepare the share sheet
                    let activityViewController = UIActivityViewController(
                        activityItems: [imageSource, textSource],
                        applicationActivities: nil
                    )
                    
                    // Add completion handler to reset sharing state
                    activityViewController.completionWithItemsHandler = { [weak self] _, completed, _, _ in
                        self?.isSharing = false
                        
                        // Show success message if the share was completed
                        if completed {
                            self?.toast?.show("Photo shared successfully!", duration: 1.5)
                        }
                    }
                    
                    // Exclude certain activity types that don't make sense for this content
                    activityViewController.excludedActivityTypes = [
                        .assignToContact,
                        .addToReadingList,
                        .openInIBooks
                    ]
                    
                    // Present the share sheet on the topmost view controller
                    if let topViewController = getTopViewController() {
                        // For iPad, we need to specify where the popover should appear
                        if let popoverController = activityViewController.popoverPresentationController {
                            popoverController.sourceView = topViewController.view
                            popoverController.sourceRect = CGRect(x: UIScreen.main.bounds.midX, 
                                                                 y: UIScreen.main.bounds.midY, 
                                                                 width: 0, height: 0)
                            popoverController.permittedArrowDirections = []
                        }
                        
                        // Ensure we're dismissing any view controller that might be presented first
                        if topViewController.presentedViewController != nil {
                            topViewController.dismiss(animated: true) {
                                topViewController.present(activityViewController, animated: true)
                            }
                        } else {
                            topViewController.present(activityViewController, animated: true)
                        }
                    } else {
                        // Fallback in case we can't get a valid view controller
                        toast?.show("Unable to share: no valid view controller found", duration: 2.0)
                        isSharing = false
                    }
                }
            } catch {
                await MainActor.run {
                    toast?.show("Error preparing image: \(error.localizedDescription)", duration: 2.0)
                    isSharing = false
                }
            }
        }
    }
    
    /// Loads the original quality image from a PHAsset
    private func loadOriginalQualityImage(from asset: PHAsset) async -> UIImage? {
        do {
            // First, try to get the highest quality image through PHImageManager
            let highQualityImage = try await loadHighestQualityImage(from: asset)
            if let highQualityImage = highQualityImage {
                return highQualityImage
            }
            
            // If that fails, try to access and convert the original asset resource data
            return try await loadOriginalAssetResource(from: asset)
        } catch {
            print("Error loading original quality image: \(error)")
            
            // Fallback to using any cached image we already have
            if currentIndex < preloadedImages.count, let cachedImage = preloadedImages[currentIndex] {
                return cachedImage
            }
            
            return nil
        }
    }
    
    /// Loads the highest quality image through PHImageManager
    private func loadHighestQualityImage(from asset: PHAsset) async throws -> UIImage? {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .original
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .none
            options.isSynchronous = false
            
            var requestID: PHImageRequestID = 0
            var degradedImage: UIImage? = nil
            
            // Add a flag to track if continuation has been resumed
            var hasResumed = false
            
            // Helper function to safely resume continuation only once
            func safeResumeWithImage(_ image: UIImage?) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
            
            func safeResumeWithError(_ error: Error) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: error)
            }
            
            // Create the request for full-size image
            requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let image = image,
                   let info = info,
                   info[PHImageResultIsDegradedKey] as? Bool == false {
                    // We got a high-quality image
                    safeResumeWithImage(image)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    safeResumeWithError(error)
                } else if info?[PHImageCancelledKey] as? Bool == true {
                    safeResumeWithError(NSError(domain: "Share", code: 2, userInfo: [NSLocalizedDescriptionKey: "Image request was cancelled"]))
                } else if let image = image, info?[PHImageResultIsDegradedKey] as? Bool == true {
                    // Store the degraded image as a fallback
                    degradedImage = image
                    
                    // If the image is in iCloud, don't wait too long
                    if info?[PHImageResultIsInCloudKey] as? Bool == true {
                        // Set a short timeout to avoid waiting forever
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second wait
                            // If we haven't already resumed the continuation, do it now with the degraded image
                            PHImageManager.default().cancelImageRequest(requestID)
                            safeResumeWithImage(degradedImage)
                        }
                    }
                }
            }
            
            // Set a timeout for the entire request
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 second timeout
                PHImageManager.default().cancelImageRequest(requestID)
                // If we haven't resumed yet, use the degraded image if available, or resume with nil
                if let degradedImage = degradedImage {
                    safeResumeWithImage(degradedImage)
                } else {
                    safeResumeWithImage(nil)
                }
            }
        }
    }
    
    /// Loads the original asset resource data and converts it to an image
    private func loadOriginalAssetResource(from asset: PHAsset) async throws -> UIImage? {
        return try await withCheckedThrowingContinuation { continuation in
            // Get all resources for this asset
            let resources = PHAssetResource.assetResources(for: asset)
            
            // Find the original resource
            let originalResource = resources.first { resource in
                resource.type == .photo || resource.type == .fullSizePhoto
            }
            
            guard let resource = originalResource else {
                continuation.resume(returning: nil)
                return
            }
            
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            
            // Create a temporary file to store the data
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            
            // Add a flag to track if continuation has been resumed
            var hasResumed = false
            
            // Helper function to safely resume continuation only once
            func safeResumeWithImage(_ image: UIImage?) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
            
            func safeResumeWithError(_ error: Error) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: error)
            }
            
            // Request the data
            PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { data in
                // Data is received in chunks, so we need to append it to our file
                if let fileHandle = try? FileHandle(forWritingTo: tempURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                } else {
                    // First chunk, create the file
                    try? data.write(to: tempURL)
                }
            }, completionHandler: { error in
                if let error = error {
                    try? FileManager.default.removeItem(at: tempURL)
                    safeResumeWithError(error)
                    return
                }
                
                // Create an image from the file
                if let imageData = try? Data(contentsOf: tempURL),
                   let image = UIImage(data: imageData) {
                    try? FileManager.default.removeItem(at: tempURL)
                    safeResumeWithImage(image)
                } else {
                    try? FileManager.default.removeItem(at: tempURL)
                    safeResumeWithImage(nil)
                }
            })
            
            // Set a timeout
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 second timeout
                try? FileManager.default.removeItem(at: tempURL)
                safeResumeWithImage(nil)
            }
        }
    }
    
    // MARK: - Image Preloading
    
    /// Custom class to handle different types of sharing content
    class PhotoSharingActivityItemSource: NSObject, UIActivityItemSource {
        private let image: UIImage
        private let albumTitle: String
        
        init(image: UIImage, albumTitle: String) {
            self.image = image
            self.albumTitle = albumTitle
            super.init()
        }
        
        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            return image
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            return image
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
            return "Photo from \(albumTitle)"
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
            // Create a thumbnail version for the activity controller
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
            return UTType.image.identifier
        }
    }
    
    /// Class to handle text content for sharing
    class TextSharingActivityItemSource: NSObject, UIActivityItemSource {
        private let text: String
        
        init(text: String) {
            self.text = text
            super.init()
        }
        
        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            return text
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            // Customize text based on the sharing platform
            if activityType == .message || activityType == .mail {
                // For messages and email, include a more detailed message
                return "Check out this photo I organized with PhotoCleaner!\n\nPhotoCleaner helps me declutter my photo library automatically. Try it: https://photocleaner.app"
            } else if activityType == .postToFacebook || activityType == .postToTwitter || activityType == .postToWeibo {
                // For social media, keep it shorter
                return "Organized with Cln. - Swipe To Clean - The smart way to declutter your photo library! https://cln.it.com"
            }
            
            // Default sharing text
            return "Organized with Cln. - Swipe To Clean. Get it: https://cln.it.com"
        }
    }
    
    // Add a method to preload images for the given array of indices
    private func preloadNextImage() {
        let indicesToPreload = [currentIndex, currentIndex + 1]
        for index in indicesToPreload {
            guard index < group.count else { continue }
            if index >= preloadedImages.count || preloadedImages[index] == nil {
                Task {
                    await loadImage(at: index, quality: .screen)
                }
            }
        }
    }
    
    // MARK: - Button Actions
    
    func triggerDeleteFromButton() {
        // Instead of simulating a DragGesture.Value, directly call the animation
        // with a direction vector to indicate left (delete) swipe
        triggerDeleteAnimationDirectly()
    }
    
    func triggerKeepFromButton() {
        // Instead of simulating a DragGesture.Value, directly call the animation
        // with a direction vector to indicate right (keep) swipe
        triggerKeepAnimationDirectly()
    }
    
    func triggerBookmarkFromButton() {
        // Handle bookmark operation
        guard let asset = group.asset(at: currentIndex) else { return }
        
        // Capture the index before showing the toast
        let capturedIndex = currentIndex
        
        // Start loading next image immediately
        Task {
            if capturedIndex + 1 < group.count {
                await loadImage(at: capturedIndex + 1, quality: .screen)
            }
        }
        
        // Perform bookmark operations
        photoManager.bookmarkAsset(asset)
        photoManager.markForFavourite(asset)
        
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Add some randomness to the animation
        let randomVerticalOffset = CGFloat.random(in: -30...30)
        let randomDuration = Double.random(in: 0.2...0.3)
        
        // Trigger fly-off animation with yellow color for "Maybe?"
        let label = "Maybe?"
        let color = Color.yellow
        let direction = CGSize(width: 100, height: randomVerticalOffset)
        triggerLabelFlyOff?(label, color, direction)
        
        // Create a fly-off animation that NEVER springs back
        withAnimation(.easeOut(duration: randomDuration)) {
            // Fly off to the right
            offset = CGSize(
                width: UIScreen.main.bounds.width * 2.0,
                height: randomVerticalOffset * 1.5
            )
        }
        
        // Wait until card is completely off-screen before doing state changes
        DispatchQueue.main.asyncAfter(deadline: .now() + randomDuration + 0.05) {
            // Important: Disable all animations temporarily
            UIView.setAnimationsEnabled(false)
            
            // First update the index while the old card is off screen
            self.currentIndex = capturedIndex + 1
            
            // THEN reset the offset with absolutely no animation
            self.offset = .zero
            
            // Re-enable animations after state is reset
            UIView.setAnimationsEnabled(true)
            
            // Show the toast message
            self.toast.show("Photo marked as Maybe?", action: "Undo") {
                // Undo Action - Use capturedIndex
                self.photoManager.removeAsset(asset, fromAlbumNamed: "Maybe?")
                self.photoManager.unmarkForFavourite(asset)
                // Animate the state reset using capturedIndex
                withAnimation {
                    self.currentIndex = capturedIndex
                    self.offset = .zero
                }
            } onDismiss: {
                // No additional action needed
            }
        }
    }
    
    // Direct animation triggers without relying on DragGesture.Value
    
    private func triggerDeleteAnimationDirectly() {
        // Capture current state
        guard let asset = group.asset(at: currentIndex) else { return }
        let capturedIndex = currentIndex
        
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Add some randomness to the animation
        let randomVerticalOffset = CGFloat.random(in: -30...30)
        let randomDuration = Double.random(in: 0.2...0.3)
        
        // Trigger fly-off animation
        let label = "Delete"
        let color = Color(red: 0.55, green: 0.35, blue: 0.98)
        let direction = CGSize(width: -100, height: randomVerticalOffset)
        triggerLabelFlyOff?(label, color, direction)
        
        // Start preloading next image silently
        Task {
            if capturedIndex + 1 < group.count {
                await loadImage(at: capturedIndex + 1, quality: .screen)
            }
        }
        
        // Create a fly-off animation that NEVER springs back
        withAnimation(.easeOut(duration: randomDuration)) {
            // Fly off to the left with a bit of vertical movement
            offset = CGSize(
                width: -UIScreen.main.bounds.width * 2.0,
                height: randomVerticalOffset * 1.5
            )
        }
        
        // Wait until card is completely off-screen before doing state changes
        DispatchQueue.main.asyncAfter(deadline: .now() + randomDuration + 0.05) {
            // Important: Disable all animations temporarily
            UIView.setAnimationsEnabled(false)
            
            // Mark for deletion in background
            self.photoManager.markForDeletion(asset)
            
            // Add the current image to the deletion preview if available
            if capturedIndex < self.preloadedImages.count, let currentImage = self.preloadedImages[capturedIndex] {
                self.photoManager.addToDeletedImagesPreview(asset: asset, image: currentImage)
            }
            
            // First update the index while the old card is off screen - increment by exactly 1
            self.currentIndex = capturedIndex + 1
            
            // THEN reset the offset with absolutely no animation 
            self.offset = .zero
            
            // Re-enable animations after state is reset
            UIView.setAnimationsEnabled(true)
            
            // Track swipe count for Discover tab paywall
            if self.isDiscoverTab && !SubscriptionManager.shared.isPremium {
                // Make sure we have a reference to the tracker
                if self.discoverSwipeTracker == nil {
                    self.discoverSwipeTracker = DiscoverSwipeTracker.shared
                }
                
                // Increment count and check if swipe should be undone
                let shouldUndo = self.discoverSwipeTracker?.incrementSwipeCount() ?? false
                
                if shouldUndo {
                    // Show the paywall
                    self.showRCPaywall = true
                    
                    // Undo the deletion action
                    self.photoManager.unmarkForDeletion(asset)
                    
                    // Animate back to the original position
                    withAnimation {
                        self.currentIndex = capturedIndex
                        self.offset = .zero
                    }
                    
                    // Show message explaining why the swipe was undone
                    self.toast.show("You've reached your daily swipe limit. Subscribe to continue.", duration: 2.5)
                } else {
                    Task {
                        // Just ensure the next image is available
                        if capturedIndex + 1 < self.group.count {
                            await self.loadImage(at: capturedIndex + 1, quality: .screen)
                        }
                    }
                    
                    self.toast.show(
                        "Marked for deletion. Press Next to permanently delete from storage.", action: "Undo"
                    ) {
                        // Undo action
                        self.photoManager.restoreToPhotoGroups(asset, inMonth: self.group.monthDate)
                        self.photoManager.unmarkForDeletion(asset)
                        withAnimation {
                            self.currentIndex = capturedIndex
                            self.offset = .zero
                        }
                    } onDismiss: { }
                }
            } else {
                // Non-discover tab - normal flow continues
                Task {
                    // Just ensure the next image is available
                    if capturedIndex + 1 < self.group.count {
                        await self.loadImage(at: capturedIndex + 1, quality: .screen)
                    }
                }
                
                self.toast.show(
                    "Marked for deletion. Press Next to permanently delete from storage.", action: "Undo"
                ) {
                    // Undo action
                    self.photoManager.restoreToPhotoGroups(asset, inMonth: self.group.monthDate)
                    self.photoManager.unmarkForDeletion(asset)
                    withAnimation {
                        self.currentIndex = capturedIndex
                        self.offset = .zero
                    }
                } onDismiss: { }
            }
        }
    }
    
    private func triggerKeepAnimationDirectly() {
        // Capture current state
        let capturedIndex = currentIndex
        
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Add some randomness to the animation
        let randomVerticalOffset = CGFloat.random(in: -30...30)
        let randomDuration = Double.random(in: 0.2...0.3)
        
        // Trigger fly-off animation
        let label = "Keep"
        let color = Color.green
        let direction = CGSize(width: 100, height: randomVerticalOffset)
        triggerLabelFlyOff?(label, color, direction)
        
        // Start preloading next image silently
        Task {
            if capturedIndex + 1 < group.count {
                await loadImage(at: capturedIndex + 1, quality: .screen)
            }
        }
        
        // Create a fly-off animation that NEVER springs back
        withAnimation(.easeOut(duration: randomDuration)) {
            // Fly off to the right
            offset = CGSize(
                width: UIScreen.main.bounds.width * 2.0,
                height: randomVerticalOffset * 1.5
            )
        }
        
        // Wait until card is completely off-screen before doing state changes
        DispatchQueue.main.asyncAfter(deadline: .now() + randomDuration + 0.05) {
            // Important: Disable all animations temporarily
            UIView.setAnimationsEnabled(false)
            
            // First update the index while the old card is off screen
            self.currentIndex = capturedIndex + 1
            
            // THEN reset the offset with absolutely no animation
            self.offset = .zero
            
            // Re-enable animations after state is reset
            UIView.setAnimationsEnabled(true)
            
            // Track swipe count for Discover tab paywall
            if self.isDiscoverTab && !SubscriptionManager.shared.isPremium {
                // Make sure we have a reference to the tracker
                if self.discoverSwipeTracker == nil {
                    self.discoverSwipeTracker = DiscoverSwipeTracker.shared
                }
                
                // Increment count and check if swipe should be undone
                let shouldUndo = self.discoverSwipeTracker?.incrementSwipeCount() ?? false
                
                if shouldUndo {
                    // Show the paywall
                    self.showRCPaywall = true
                    
                    // Animate back to the original position
                    withAnimation {
                        self.currentIndex = capturedIndex
                        self.offset = .zero
                    }
                    
                    // Show message explaining why the swipe was undone
                    self.toast.show("You've reached your daily swipe limit. Subscribe to continue.", duration: 2.5)
                } else {
                    // Just ensure the next image is available
                    Task {
                        if capturedIndex + 1 < self.group.count {
                            await self.loadImage(at: capturedIndex + 1, quality: .screen)
                        }
                    }
                }
            } else {
                // Load next image
                Task {
                    if capturedIndex + 1 < self.group.count {
                        await self.loadImage(at: capturedIndex + 1, quality: .screen)
                    }
                }
            }
        }
    }
} 
