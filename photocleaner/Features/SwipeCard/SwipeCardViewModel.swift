import Photos
import SwiftUI
import Combine
import UIKit

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
    
    // Haptic feedback generator
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // Callback for fly-off animation
    var triggerLabelFlyOff: ((String, Color, CGSize) -> Void)? = nil
    
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
            
        // Prepare haptic feedback generator
        feedbackGenerator.prepare()
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
        }
        swipeLabel = nil
    }
    
    func handleSwipeGesture(value: DragGesture.Value) {
        let threshold: CGFloat = 100
        let velocity = value.predictedEndLocation.x - value.location.x
        
        // Check if swipe exceeds threshold or has significant velocity
        if value.translation.width < -threshold || (value.translation.width < -50 && velocity < -300) {
            // Delete swipe (left) - Immediate action 
            triggerDeleteWithAnimation(value)
        } else if value.translation.width > threshold || (value.translation.width > 50 && velocity > 300) {
            // Keep swipe (right) - Immediate action
            triggerKeepWithAnimation(value)
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
    
    private func triggerDeleteWithAnimation(_ value: DragGesture.Value) {
        // Calculate velocity for more natural feeling
        let velocity = value.predictedEndLocation.x - value.location.x
        let velocityFactor = min(abs(velocity) / CGFloat(500.0), CGFloat(1.0))
        let duration = 0.25 - (0.1 * Double(velocityFactor)) // Faster exit
        
        // Capture current state before any animations
        guard let asset = group.asset(at: currentIndex) else { return }
        let capturedIndex = currentIndex
        
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Trigger fly-off animation
        let label = "Delete"
        let color = Color(red: 0.55, green: 0.35, blue: 0.98)
        triggerLabelFlyOff?(label, color, value.translation)
        
        // Start preloading next image silently
        Task {
            if capturedIndex + 1 < group.count {
                await loadImage(at: capturedIndex + 1, quality: .screen)
            }
        }
        
        // Create a fly-off animation that NEVER springs back
        withAnimation(.easeOut(duration: duration)) {
            // Fly off to the left with a bit of vertical movement based on gesture
            offset = CGSize(
                width: -UIScreen.main.bounds.width * 2.0, // Even further to ensure it's off-screen
                height: value.translation.height * 1.5
            )
        }
        
        // Wait until card is completely off-screen before doing state changes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { // Add a small buffer time
            // Important: Disable all animations temporarily
            UIView.setAnimationsEnabled(false)
            
            // Mark for deletion in background
            self.photoManager.markForDeletion(asset)
            
            // Add the current image to the deletion preview if available
            if capturedIndex < self.preloadedImages.count, let currentImage = self.preloadedImages[capturedIndex] {
                self.photoManager.addToDeletedImagesPreview(asset: asset, image: currentImage)
            }
            
            // First update the index while the old card is off screen
            self.currentIndex = capturedIndex + 1
            
            // THEN reset the offset with absolutely no animation 
            self.offset = .zero
            
            // Re-enable animations after state is reset
            UIView.setAnimationsEnabled(true)
            
            // Handle cleanup and next image preparation in background
            Task {
                await self.cleanupOldImages()
                
                // Preload next images after moving to the next card
                if capturedIndex + 2 < self.group.count {
                    await self.loadImage(at: capturedIndex + 2, quality: .screen)
                }
            }
            
            self.toast.show(
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
            } onDismiss: { }
        }
    }
    
    private func triggerKeepWithAnimation(_ value: DragGesture.Value) {
        // Calculate velocity for more natural feeling
        let velocity = value.predictedEndLocation.x - value.location.x
        let velocityFactor = min(abs(velocity) / CGFloat(500.0), CGFloat(1.0))
        let duration = 0.25 - (0.1 * Double(velocityFactor)) // Faster exit
        
        // Capture current state before any animations
        let capturedIndex = currentIndex
        
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Trigger fly-off animation
        let label = "Keep"
        let color = Color.green
        triggerLabelFlyOff?(label, color, value.translation)
        
        // Start preloading next image silently
        Task {
            if capturedIndex + 1 < group.count {
                await loadImage(at: capturedIndex + 1, quality: .screen)
            }
        }
        
        // Create a fly-off animation that NEVER springs back
        withAnimation(.easeOut(duration: duration)) {
            // Fly off to the right with a bit of vertical movement based on gesture
            offset = CGSize(
                width: UIScreen.main.bounds.width * 2.0, // Even further to ensure it's off-screen
                height: value.translation.height * 1.5
            )
        }
        
        // Wait until card is completely off-screen before doing state changes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { // Add a small buffer time
            // Important: Disable all animations temporarily
            UIView.setAnimationsEnabled(false)
            
            // First update the index while the old card is off screen
            self.currentIndex = capturedIndex + 1
            
            // THEN reset the offset with absolutely no animation
            self.offset = .zero
            
            // Re-enable animations after state is reset
            UIView.setAnimationsEnabled(true)
            
            // Handle cleanup and next image preparation in background
            Task {
                await self.cleanupOldImages()
                
                // Preload next images after moving to the next card
                if capturedIndex + 2 < self.group.count {
                    await self.loadImage(at: capturedIndex + 2, quality: .screen)
                }
            }
        }
    }
    
    // Improved version of moveToNext that adds a fade-in animation for the next card
    private func moveToNextWithAnimation() async {
        let nextIndex = currentIndex + 1
        
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
                withAnimation(.none) {
                    offset = .zero
                }
                
                // Now update the index to show the next card
                currentIndex = nextIndex
                
                // Animate the opacity of the next card for a nice transition
                // This is handled in the view
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
        
        toast.show("Photo saved", action: "Undo") {
            // Undo Action - Use capturedIndex
            self.photoManager.removeAsset(asset, fromAlbumNamed: "Saved")
            // self.refreshCard(at: capturedIndex, with: asset) // Use capturedIndex - REMOVED
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
//                await prefetchAssetMetadata(asset: asset)
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
    
    // private func prefetchAssetMetadata(asset: PHAsset) async {
    //     let options = PHContentEditingInputRequestOptions()
    //     options.isNetworkAccessAllowed = true
    //     options.canHandleAdjustmentData = { _ in return false }
        
    //     _ = await withCheckedContinuation { continuation in
    //         asset.requestContentEditingInput(with: options) { input, _ in
    //             continuation.resume(returning: input != nil)
    //         }
    //     }
    // }
    
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
    
    // Update the button methods to use the new animation function
    func triggerDeleteFromButton() {
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Trigger fly-off animation for the label
        let label = "Delete"
        let color = Color(red: 0.55, green: 0.35, blue: 0.98)
        // Create direction without using DragGesture.Value
        let simulatedDirection = CGSize(width: -150, height: 0)
        triggerLabelFlyOff?(label, color, simulatedDirection)
        
        // Duration for animation - faster for smoother experience
        let duration = 0.25
        
        // Animate card flying off screen IMMEDIATELY
        withAnimation(.easeOut(duration: duration)) {
            // Fly off to the left with a slight upward motion
            offset = CGSize(
                width: -UIScreen.main.bounds.width * 1.3,
                height: -50
            )
        }
        
        // Process the action after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.none) {
                self.offset = .zero // Reset immediately (not visible to user)
            }
            
            guard let asset = self.group.asset(at: self.currentIndex) else { return }
            let capturedIndex = self.currentIndex
            
            self.photoManager.markForDeletion(asset)
            
            // Add to deletion preview if image is available
            if self.currentIndex < self.preloadedImages.count, let currentImage = self.preloadedImages[self.currentIndex] {
                self.photoManager.addToDeletedImagesPreview(asset: asset, image: currentImage)
            }
            
            // Load next image and move to it with animation
            Task {
                if capturedIndex + 1 < self.group.count {
                    await self.loadImage(at: capturedIndex + 1, quality: .screen)
                }
                await self.moveToNextWithAnimation()
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
    
    func triggerKeepFromButton() {
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Trigger fly-off animation for the label
        let label = "Keep"
        let color = Color.green
        // Create direction without using DragGesture.Value
        let simulatedDirection = CGSize(width: 150, height: 0)
        triggerLabelFlyOff?(label, color, simulatedDirection)
        
        // Duration for animation - faster for smoother experience
        let duration = 0.25
        
        // Animate card flying off screen IMMEDIATELY
        withAnimation(.easeOut(duration: duration)) {
            // Fly off to the right with a slight upward motion
            offset = CGSize(
                width: UIScreen.main.bounds.width * 1.3,
                height: -50
            )
        }
        
        // Process the action after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.none) {
                self.offset = .zero // Reset immediately (not visible to user)
            }
            
            let capturedIndex = self.currentIndex
            
            // Load next image and move to it with animation
            Task {
                if capturedIndex + 1 < self.group.count {
                    await self.loadImage(at: capturedIndex + 1, quality: .screen)
                }
                await self.moveToNextWithAnimation()
            }
        }
    }
    
    func triggerBookmarkFromButton() {
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Duration for animation - faster for smoother experience
        let duration = 0.25
        
        // Animate card flying off screen IMMEDIATELY
        withAnimation(.easeOut(duration: duration)) {
            // Fly off upward
            offset = CGSize(
                width: 0,
                height: -UIScreen.main.bounds.height * 0.9
            )
        }
        
        // Process the action after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.none) {
                self.offset = .zero // Reset immediately (not visible to user)
            }
            
            guard let asset = self.group.asset(at: self.currentIndex) else { return }
            let capturedIndex = self.currentIndex
            
            self.photoManager.bookmarkAsset(asset)
            self.photoManager.markForFavourite(asset)
            
            // Load next image and move to it with animation
            Task {
                if capturedIndex + 1 < self.group.count {
                    await self.loadImage(at: capturedIndex + 1, quality: .screen)
                }
                await self.moveToNextWithAnimation()
            }
            
            self.toast.show("Photo saved", action: "Undo") {
                // Undo action
                self.photoManager.removeAsset(asset, fromAlbumNamed: "Saved")
                self.photoManager.unmarkForFavourite(asset)
                withAnimation {
                    self.currentIndex = capturedIndex
                    self.offset = .zero
                }
            } onDismiss: { }
        }
    }
} 
