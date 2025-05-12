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
    private let maxBufferSize = 10  // Increased from 5 to 10 images in memory
    private let preloadThreshold = 5  // Increased from 3 to 5 images ahead for preloading
    private let lastViewedIndexKeyPrefix = "LastViewedIndex_"
    private var loadedCount = 0
    private var imageFetchTasks: [Int: Task<UIImage?, Never>] = [:]
    private var imageLoadingTimeouts: [Int: DispatchWorkItem] = [:]
    private var loadRetryCount: [Int: Int] = [:]
    private let maxRetryCount = 3
    
    // Haptic feedback generator
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // Callback for fly-off animation
    var triggerLabelFlyOff: ((String, Color, CGSize) -> Void)? = nil
    
    // Track high-quality image loading status separately
    private var highQualityImagesStatus: [Int: Bool] = [:]
    private let highQualityPreloadCount = 5  // Increased from 3 to 5 high-quality images to preload
    
    // Add a reference to the forceRefresh binding
    var forceRefreshCallback: (() -> Void)?
    
    // Initial high-quality image for first card
    private var initialHighQualityImage: UIImage?
    
    // MARK: - Initialization
    init(group: PhotoGroup, photoManager: PhotoManager? = nil, toast: ToastService? = nil, imageViewTracker: ImageViewTracker? = nil, isDiscoverTab: Bool = false, initialHighQualityImage: UIImage? = nil) {
        self.group = group
        self.photoManager = photoManager
        self.toast = toast
        self.imageViewTracker = imageViewTracker
        self.isDiscoverTab = isDiscoverTab
        self.discoverSwipeTracker = isDiscoverTab ? DiscoverSwipeTracker.shared : nil
        self.initialHighQualityImage = initialHighQualityImage
        
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
                Task { @MainActor in
                    toast.showWarning("Please wait for the image to fully load before swiping", duration: 2.0)
                }
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
        
        // Check if this is the last image
        let isLastImage = capturedIndex == group.count - 1
        
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
            // Get the asset again in case things changed
            guard let asset = self.group.asset(at: capturedIndex) else { return }
            
            // Mark the asset for deletion
            self.photoManager.markForDeletion(asset)
            
            // Add the current image to the deletion preview if available
            if capturedIndex < self.preloadedImages.count, let currentImage = self.preloadedImages[capturedIndex] {
                self.photoManager.addToDeletedImagesPreview(asset: asset, image: currentImage)
            }
            
            // Track swipe count
            self.incrementSwipeCount()
            
            // Check if we've reached the swipe limit
            if self.isDiscoverTab && !SubscriptionManager.shared.isPremium {
                // Make sure we have a reference to the tracker
                if self.discoverSwipeTracker == nil {
                    self.discoverSwipeTracker = DiscoverSwipeTracker.shared
                }
                
                // Check if we need to show the discover tab paywall
                if self.discoverSwipeTracker?.showRCPaywall == true {
                    // Show the paywall
                    self.showRCPaywall = true
                    
                    // Undo the deletion action
                    self.photoManager.unmarkForDeletion(asset)
                    
                    // Animate back to the original position
                    withAnimation {
                        self.currentIndex = capturedIndex
                        self.offset = .zero
                    }
                    
                    return
                }
            }
            
            // Important: Disable all animations temporarily
            UIView.setAnimationsEnabled(false)
            
            // Update the index while the old card is off screen
            self.currentIndex = capturedIndex + 1
            
            // THEN reset the offset with absolutely no animation 
            self.offset = .zero
            
            // Re-enable animations after state is reset
            UIView.setAnimationsEnabled(true)
            
            // If this is the last image, show delete preview
            if isLastImage {
                // Small delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.prepareDeletePreview()
                }
                return
            }
            
            // Load next image and perform cleanup
            Task {
                if capturedIndex + 1 < self.group.count {
                    await self.loadImage(at: capturedIndex + 1, quality: .screen)
                }
                await self.cleanupOldImages()
            }
            
            // Show the deletion toast message
            Task { @MainActor in
                self.toast.show(
                    "Marked for deletion. Press Next to permanently delete from storage.", 
                    action: "Undo",
                    duration: 3.0,
                    onAction: {
                        // Undo Action - Use capturedIndex
                        self.photoManager.restoreToPhotoGroups(asset, inMonth: self.group.monthDate)
                        self.photoManager.unmarkForDeletion(asset)
                        // Animate the state reset using capturedIndex
                        withAnimation {
                            self.currentIndex = capturedIndex
                            self.offset = .zero
                        }
                    },
                    type: .info
                )
            }
        }
    }
    
    private func triggerKeepWithAnimation(_ value: DragGesture.Value) {
        // Calculate velocity for more natural feeling
        let velocity = value.predictedEndLocation.x - value.location.x
        let velocityFactor = min(abs(velocity) / CGFloat(500.0), CGFloat(1.0))
        let duration = 0.25 - (0.1 * Double(velocityFactor)) // Faster exit for more satisfied feel
        
        // Capture current state before any animations
        guard let asset = group.asset(at: currentIndex) else { return }
        let capturedIndex = currentIndex
        
        // Check if this is the last image
        let isLastImage = capturedIndex == group.count - 1
        
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
        
        // Create a fly-off animation
        withAnimation(.easeOut(duration: duration)) {
            // Fly off to the right with a bit of vertical movement based on gesture
            offset = CGSize(
                width: UIScreen.main.bounds.width * 2.0, // Even further to ensure it's off-screen
                height: value.translation.height * 1.5
            )
        }
        
        // Wait until card is completely off-screen before doing state changes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.none) {
                self.offset = .zero // Reset immediately (not visible to user)
            }
            
            // Keep the photo
            self.photoManager.keepAsset(asset)
            
            // Track swipe count
            self.incrementSwipeCount()
            
            // Check if we've reached the swipe limit
            if self.isDiscoverTab && !SubscriptionManager.shared.isPremium {
                // Make sure we have a reference to the tracker
                if self.discoverSwipeTracker == nil {
                    self.discoverSwipeTracker = DiscoverSwipeTracker.shared
                }
                
                // Check if we need to show the discover tab paywall
                if self.discoverSwipeTracker?.showRCPaywall == true {
                    // Show the paywall
                    self.showRCPaywall = true
                    
                    // Animate back to the original position
                    withAnimation {
                        self.offset = .zero
                    }
                    
                    return
                }
            }
            
            // Important: Disable all animations temporarily
            UIView.setAnimationsEnabled(false)
            
            // Update the index while the old card is off screen
            self.currentIndex = capturedIndex + 1
            
            // THEN reset the offset with absolutely no animation 
            self.offset = .zero
            
            // Re-enable animations after state is reset
            UIView.setAnimationsEnabled(true)
            
            // If this is the last image, show delete preview
            if isLastImage {
                // Small delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.prepareDeletePreview()
                }
                return
            }
            
            // Load next image and clean up old ones
            Task {
                if capturedIndex + 1 < self.group.count {
                    await self.loadImage(at: capturedIndex + 1, quality: .screen)
                }
                await self.cleanupOldImages()
            }
        }
    }
    
    // Improved version of moveToNext that adds a fade-in animation for the next card
    // and tracks image views for subscription threshold
    private func moveToNextWithAnimation() async {
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
        
        // Update the current index directly
        currentIndex = capturedIndex + 1
        offset = .zero
        
        // Make sure we're on the main actor for toast display
        Task { @MainActor in
            toast.show(
                "Marked for deletion. Press Next to permanently delete from storage.", 
                action: "Undo",
                duration: 3.0,
                onAction: {
                    // Undo Action - Use capturedIndex
                    self.photoManager.restoreToPhotoGroups(asset, inMonth: self.group.monthDate)
                    self.photoManager.unmarkForDeletion(asset)
                    // Animate the state reset using capturedIndex
                    withAnimation {
                        self.currentIndex = capturedIndex
                        self.offset = .zero
                    }
                },
                type: .info
            )
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
        
        // Update the current index directly
        currentIndex = capturedIndex + 1
        offset = .zero
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
        
        // Ensure UI is refreshed to show updated Maybe? album
        Task {
            await photoManager.refreshAllPhotoGroups()
        }
        
        // Update the current index directly
        currentIndex = capturedIndex + 1
        offset = .zero
        
        // Make sure we're on the main actor for toast display
        Task { @MainActor in
            toast.show(
                "Photo marked as Maybe?", 
                action: "Undo",
                duration: 3.0,
                onAction: {
                    // Undo Action - Use capturedIndex
                    self.photoManager.removeAsset(asset, fromAlbumNamed: "Maybe?")
                    self.photoManager.unmarkForFavourite(asset)
                    withAnimation {
                        self.currentIndex = capturedIndex
                        self.offset = .zero
                    }
                }
            )
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
        
        // An image is ready for interaction when:
        // 1. It exists (not nil)
        // 2. AND either it's explicitly marked as high quality OR we're allowing interaction for visible images
        //    that haven't yet been marked but are displayed (fallback case)
        
        let imageExists = preloadedImages[currentIndex] != nil
        let isHighQuality = highQualityImagesStatus[currentIndex] == true
        
        // Only allow interaction if we have an image and either:
        // - It's high quality
        // - OR highQualityImagesStatus is nil (not explicitly tracked)
        // - OR the image has been displayed for more than 1 second (fallback for visible but not marked images)
        return imageExists && (isHighQuality || highQualityImagesStatus[currentIndex] == nil)
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
            
            // If we have an initial high-quality image, use it for the first card
            if let initialImage = initialHighQualityImage, currentIndex == 0 {
                await MainActor.run {
                    // Make sure preloadedImages array has enough slots
                    while preloadedImages.count <= currentIndex {
                        preloadedImages.append(nil)
                    }
                    
                    // Set the initial high-quality image
                    preloadedImages[currentIndex] = initialImage
                    highQualityImagesStatus[currentIndex] = true
                    
                    // Mark as loaded
                    loadedCount = max(loadedCount, currentIndex + 1)
                }
            }
            
            // First, load thumbnails for the first few images (skip first if we already have it)
            let startIndex = (initialHighQualityImage != nil && currentIndex == 0) ? 1 : currentIndex
            let count = min(maxBufferSize, group.count - startIndex)
            
            if count > 0 {
                await loadImagesInRange(
                    from: startIndex,
                    count: count,
                    quality: .thumbnail
                )
            }
            
            // Then load higher quality for current card (if needed) and next few cards
            let preloadCount = min(highQualityPreloadCount, group.count - currentIndex)
            for i in 0..<preloadCount {
                let index = currentIndex + i
                
                // Skip the first image if we already have a high-quality version
                if index == currentIndex && initialHighQualityImage != nil && highQualityImagesStatus[index] == true {
                    continue
                }
                
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
        
        // Keep only the current image, next image, and previous image, clear everything else
        if !preloadedImages.isEmpty && currentIndex < preloadedImages.count {
            // Save the current image
            let currentImage = preloadedImages[currentIndex]
            
            // Save the next image if available
            let nextIndex = currentIndex + 1
            let nextImage = nextIndex < preloadedImages.count ? preloadedImages[nextIndex] : nil
            
            // Save the previous image if available
            let prevIndex = currentIndex - 1
            let prevImage = prevIndex >= 0 && prevIndex < preloadedImages.count ? preloadedImages[prevIndex] : nil
            
            // Clear all images
            preloadedImages = Array(repeating: nil, count: preloadedImages.count)
            highQualityImagesStatus = [:]
            
            // Restore the current image
            if currentIndex < preloadedImages.count {
                preloadedImages[currentIndex] = currentImage
                highQualityImagesStatus[currentIndex] = true
            }
            
            // Restore the next image if available
            if nextIndex < preloadedImages.count && nextImage != nil {
                preloadedImages[nextIndex] = nextImage
                highQualityImagesStatus[nextIndex] = true
            }
            
            // Restore the previous image if available
            if prevIndex >= 0 && prevIndex < preloadedImages.count && prevImage != nil {
                preloadedImages[prevIndex] = prevImage
                highQualityImagesStatus[prevIndex] = true
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
                        if index < self.preloadedImages.count && self.highQualityImagesStatus[index] != true && image != nil {
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
        
        // Cancel any existing timeout for this index
        if let existingTimeout = imageLoadingTimeouts[index] {
            existingTimeout.cancel()
            imageLoadingTimeouts.removeValue(forKey: index)
        }
        
        // Track retry count
        if quality == .screen {
            loadRetryCount[index] = (loadRetryCount[index] ?? 0) + 1
        }
        
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
                // Increase maximum target size for high-resolution devices
                targetSize = CGSize(
                    width: min(screenSize.width * scale, 2400),  // Increased from 1200 to 2400
                    height: min(screenSize.height * scale, 2400) // Increased from 1200 to 2400
                )
            }
            
            // Create a timeout handler to fall back to lower quality if needed
            let timeoutHandler = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    // Timeout occurred, cancel the current task
                    self.imageFetchTasks[index]?.cancel()
                    self.imageFetchTasks.removeValue(forKey: index)
                    
                    // Only try fallback if we're still on this index or close to it
                    if abs(index - self.currentIndex) <= 5 {
                        if quality == .screen && (self.loadRetryCount[index] ?? 0) < self.maxRetryCount {
                            // If high quality failed, try medium quality
                            print("⚠️ Timeout loading high-quality image at index \(index). Falling back to thumbnail.")
                            _ = await self.loadImage(at: index, quality: .thumbnail)
                        } else if index == self.currentIndex {
                            // If we've exhausted retries and it's the current image, allow user to proceed anyway
                            print("⚠️ Failed to load image at index \(index) after multiple attempts.")
                            
                            // Update UI to show the image is problematic but still allow interaction
                            await MainActor.run {
                                // Set a placeholder or fallback image if possible
                                if self.preloadedImages.count > index {
                                    if self.preloadedImages[index] == nil {
                                        self.preloadedImages[index] = UIImage(systemName: "exclamationmark.triangle")
                                    }
                                    self.highQualityImagesStatus[index] = true // Mark as "loaded" to allow interaction
                                }
                                
                                // Show toast notification
                                self.toast?.showWarning("Image couldn't be loaded fully. You can still proceed.", duration: 2.5)
                            }
                        }
                    }
                }
            }
            
            // Store the timeout handler and schedule it
            await MainActor.run {
                self.imageLoadingTimeouts[index] = timeoutHandler
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutHandler)
            }
            
            let image = await withCheckedContinuation { continuation in
                // Add a flag to track if we've already resumed the continuation
                var hasResumedContinuation = false
                var receivedHighQualityImage = false
                
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    // Check if the image is a result of a degraded quality delivery
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
                    
                    // Skip if the request was cancelled and we've already received a high-quality image
                    if isCancelled && receivedHighQualityImage {
                        return
                    }
                    
                    // If we got a non-degraded image, this is our high-quality result
                    if !isDegraded && image != nil {
                        receivedHighQualityImage = true
                        if !hasResumedContinuation {
                            hasResumedContinuation = true
                            continuation.resume(returning: image)
                        }
                        return
                    }
                    
                    // For a high-quality request, we want to avoid immediately returning a degraded image
                    if quality == .screen && isDegraded {
                        // Store the degraded image in case we need it later
                        let degradedImage = image
                        
                        // Check if we're in a timeout situation
                        if let timeoutItem = self.imageLoadingTimeouts[index], timeoutItem.isCancelled {
                            // We're timing out, so use the degraded image if we haven't resumed yet
                            if !hasResumedContinuation {
                                hasResumedContinuation = true
                                continuation.resume(returning: degradedImage)
                            }
                        }
                        
                        // Don't resume the continuation yet for degraded images unless it's a timeout
                        // The high-quality image should arrive shortly
                    } else if !hasResumedContinuation && image != nil {
                        // This is either a non-screen quality request or a non-degraded image
                        hasResumedContinuation = true
                        continuation.resume(returning: image)
                    }
                }
                
                // Handle the case where only a degraded image might be delivered
                // Set a short timeout to ensure we eventually return something
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !hasResumedContinuation {
                        hasResumedContinuation = true
                        // If the high-quality image hasn't arrived after 1.5 seconds,
                        // we'll fall back to whatever image the PHImageManager has provided
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
            
            // Cancel the timeout handler as we got a result
            await MainActor.run {
                if let timeoutItem = self.imageLoadingTimeouts[index] {
                    timeoutItem.cancel()
                    self.imageLoadingTimeouts.removeValue(forKey: index)
                }
            }
            
            // Process the image if needed to avoid DisplayP3 color space issues
            let processedImage = await convertToStandardColorSpaceIfNeeded(image)
            
            // Update UI with image
            if !Task.isCancelled {
                await MainActor.run {
                    // Check if we're still in a valid range
                    if index < self.preloadedImages.count {
                        if quality == .screen {
                            // Always update with high-quality image and mark as high quality
                            if let processedImage = processedImage {
                                self.preloadedImages[index] = processedImage
                                self.highQualityImagesStatus[index] = true
                                self.loadRetryCount[index] = 0 // Reset retry count on success
                            } else {
                                // If high-quality failed but we already have a thumbnail, keep it
                                // but don't mark as high-quality
                                if self.preloadedImages[index] == nil {
                                    // Only if we have nothing, try to set the potentially nil processed image
                                    self.preloadedImages[index] = processedImage
                                }
                                // Don't set highQualityImagesStatus to true since we don't have a high-quality image
                            }
                        } else if self.highQualityImagesStatus[index] != true && processedImage != nil {
                            // For thumbnails, only update if we don't have any image yet or the high-quality flag is not set
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
            print("❌ Error loading image at index \(index): \(error)")
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
    
    // Update the button methods to use the new animation function
    func triggerDeleteFromButton() {
        // Check if this is the last image
        let isLastImage = currentIndex == group.count - 1
        
        // Capture current state before any animations
        guard let asset = group.asset(at: currentIndex) else { return }
        let capturedIndex = currentIndex
        
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Add the current image to the deletion preview if available
        if capturedIndex < preloadedImages.count, let currentImage = preloadedImages[capturedIndex] {
            photoManager.addToDeletedImagesPreview(asset: asset, image: currentImage)
        }
        
        // Mark for deletion
        photoManager.markForDeletion(asset)
        
        // Trigger fly-off animation with default values (no gesture)
        let label = "Delete"
        let color = Color(red: 0.55, green: 0.35, blue: 0.98)
        triggerLabelFlyOff?(label, color, CGSize(width: -100, height: 0))
        
        // Create a fly-off animation
        withAnimation(.easeOut(duration: 0.25)) {
            // Fly off to the left
            offset = CGSize(width: -UIScreen.main.bounds.width * 2.0, height: 0)
        }
        
        // Wait until card is completely off-screen before doing state changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + 0.05) {
            // Reset index and offset
            UIView.setAnimationsEnabled(false)
            self.currentIndex = capturedIndex + 1
            self.offset = .zero
            UIView.setAnimationsEnabled(true)
            
            // If this is the last image, show delete preview
            if isLastImage {
                // Small delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.prepareDeletePreview()
                }
                return
            }
            
            // Track swipe count for Discover tab paywall
            self.incrementSwipeCount()
            
            // Load next image
            Task {
                if capturedIndex + 1 < self.group.count {
                    await self.loadImage(at: capturedIndex + 1, quality: .screen)
                }
                await self.cleanupOldImages()
            }
            
            // Show the deletion toast message
            Task { @MainActor in
                self.toast.show(
                    "Marked for deletion. Press Next to permanently delete from storage.", 
                    action: "Undo",
                    duration: 3.0,
                    onAction: {
                        // Undo Action - Use capturedIndex
                        self.photoManager.restoreToPhotoGroups(asset, inMonth: self.group.monthDate)
                        self.photoManager.unmarkForDeletion(asset)
                        // Animate the state reset using capturedIndex
                        withAnimation {
                            self.currentIndex = capturedIndex
                            self.offset = .zero
                        }
                    },
                    type: .info
                )
            }
        }
    }
    
    func triggerKeepFromButton() {
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Duration for animation - faster for smoother experience
        let duration = 0.25
        
        // Get the current asset
        guard let asset = group.asset(at: currentIndex) else { return }
        let capturedIndex = currentIndex
        
        // Check if this is the last image
        let isLastImage = capturedIndex == group.count - 1
        
        // Trigger fly-off animation with green color
        triggerLabelFlyOff?("Keep", .green, CGSize(width: 100, height: 0))
        
        // Animate card flying off screen IMMEDIATELY  
        withAnimation(.easeOut(duration: duration)) {
            // Fly off to the right with a bit of vertical movement based on gesture
            offset = CGSize(
                width: UIScreen.main.bounds.width,
                height: 0
            )
        }
        
        // Process after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.none) {
                self.offset = .zero // Reset immediately (not visible to user)
            }
            
            // Mark the asset as kept
            self.photoManager.keepAsset(asset)
            
            // Track swipe count
            self.incrementSwipeCount()
            
            // Check if we've reached the swipe limit
            if self.isDiscoverTab && !SubscriptionManager.shared.isPremium {
                // Make sure we have a reference to the tracker
                if self.discoverSwipeTracker == nil {
                    self.discoverSwipeTracker = DiscoverSwipeTracker.shared
                }
                
                // Check if we need to show the discover tab paywall
                if self.discoverSwipeTracker?.showRCPaywall == true {
                    // Show the paywall
                    self.showRCPaywall = true
                    
                    // Animate back to the original position
                    withAnimation {
                        self.currentIndex = capturedIndex
                        self.offset = .zero
                    }
                    
                    return
                }
            }
            
            // Reset index and offset
            UIView.setAnimationsEnabled(false)
            self.currentIndex = capturedIndex + 1
            self.offset = .zero
            UIView.setAnimationsEnabled(true)
            
            // If this is the last image, show delete preview
            if isLastImage {
                // Small delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.prepareDeletePreview()
                }
                return
            }
            
            // Load next image
            Task {
                if capturedIndex + 1 < self.group.count {
                    await self.loadImage(at: capturedIndex + 1, quality: .screen)
                }
                await self.cleanupOldImages()
            }
        }
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
            Task { @MainActor in
                toast?.showWarning("Unable to share this image", duration: 2.0)
            }
            return
        }

        // Set sharing state to true
        isSharing = true

        // Show loading indicator
        Task { @MainActor in
            toast?.showInfo("Preparing high-quality image...", duration: 1.5)
        }
        
        // Load original quality image
        Task {
            do {
                let originalImage = await loadOriginalQualityImage(from: asset)
                
                await MainActor.run {
                    if let originalImage = originalImage {
                        // Create sharing sources
                        let imageSource = PhotoSharingActivityItemSource(image: originalImage, albumTitle: group.title)
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
                                Task { @MainActor [weak self] in
                                    self?.toast?.showSuccess("Photo shared successfully!", duration: 1.5)
                                }
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
                            Task { @MainActor in
                                toast?.showWarning("Unable to share: no valid view controller found", duration: 2.0)
                            }
                            isSharing = false
                        }
                    } else {
                        Task { @MainActor in
                            toast?.showWarning("Failed to prepare image for sharing", duration: 2.0)
                        }
                        isSharing = false
                    }
                }
            } catch {
                await MainActor.run {
                    toast?.showError("Error preparing image: \(error.localizedDescription)", duration: 2.0)
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
    
    private func incrementSwipeCount() {
        // Check if user is premium
        if SubscriptionManager.shared.isPremium {
            return // Premium users don't have swipe limits
        }
        
        // For discover tab, also update the discover-specific tracker
        if isDiscoverTab && !SubscriptionManager.shared.isPremium {
            // Make sure we have a reference to the tracker
            if discoverSwipeTracker == nil {
                discoverSwipeTracker = DiscoverSwipeTracker.shared
            }
            
            // Increment count and check if swipe should be undone
            let shouldShowPaywall = discoverSwipeTracker?.incrementSwipeCount() ?? false
            
            // Only set showRCPaywall if we've actually hit the limit
            if shouldShowPaywall {
                showRCPaywall = true
                
                // Show message explaining why the swipe was undone
                Task { @MainActor in
                    self.toast.showWarning("You've reached your daily limit of \(discoverSwipeTracker?.threshold ?? 30) swipes. Subscribe to continue.", duration: 2.5)
                }
            }
        }
    }
    
    func triggerBookmarkFromButton() {
        // Trigger haptic feedback
        feedbackGenerator.impactOccurred()
        
        // Duration for animation - faster for smoother experience
        let duration = 0.25
        
        // Get the current asset
        guard let asset = group.asset(at: currentIndex) else { return }
        let capturedIndex = currentIndex
        
        // Check if this is the last image
        let isLastImage = capturedIndex == group.count - 1
        
        // Trigger fly-off animation with yellow color
        triggerLabelFlyOff?("Maybe", .yellow, CGSize(width: 0, height: -100))
        
        // Animate card flying off screen IMMEDIATELY
        withAnimation(.easeOut(duration: duration)) {
            // Fly off upward
            offset = CGSize(
                width: 0,
                height: -UIScreen.main.bounds.height
            )
        }
        
        // Process after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.none) {
                self.offset = .zero // Reset immediately (not visible to user)
            }
            
            // Create an album or add to existing album
            self.photoManager.bookmarkAsset(asset)
            self.photoManager.markForFavourite(asset)
            
            // Ensure UI is refreshed to show updated Maybe? album
            Task {
                await self.photoManager.refreshAllPhotoGroups()
            }
            
            // Track swipe count
            self.incrementSwipeCount()
            
            // Check if we've reached the swipe limit
            if !SubscriptionManager.shared.isPremium, 
               let tracker = self.discoverSwipeTracker, 
               tracker.isLimitReached {
                // Undo the bookmark action
                self.photoManager.removeAsset(asset, fromAlbumNamed: "Maybe?")
                self.photoManager.unmarkForFavourite(asset)
                
                // Animate back to the original position
                withAnimation {
                    self.currentIndex = capturedIndex
                    self.offset = .zero
                }
                
                return
            }
            
            // Check the discover tab swipe limit
            if self.isDiscoverTab && !SubscriptionManager.shared.isPremium {
                // Make sure we have a reference to the tracker
                if self.discoverSwipeTracker == nil {
                    self.discoverSwipeTracker = DiscoverSwipeTracker.shared
                }
                
                // Check if we need to show the discover tab paywall
                if self.discoverSwipeTracker?.showRCPaywall == true {
                    // Show the paywall
                    self.showRCPaywall = true
                    
                    // Undo the bookmark action
                    self.photoManager.removeAsset(asset, fromAlbumNamed: "Maybe?")
                    self.photoManager.unmarkForFavourite(asset)
                    
                    // Animate back to the original position
                    withAnimation {
                        self.currentIndex = capturedIndex
                        self.offset = .zero
                    }
                    
                    return
                }
            }
            
            // Reset index and offset
            UIView.setAnimationsEnabled(false)
            self.currentIndex = capturedIndex + 1
            self.offset = .zero
            UIView.setAnimationsEnabled(true)
            
            // If this is the last image, show delete preview
            if isLastImage {
                // Small delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.prepareDeletePreview()
                }
                return
            }
            
            // Load next image and perform cleanup
            Task {
                if capturedIndex + 1 < self.group.count {
                    await self.loadImage(at: capturedIndex + 1, quality: .screen)
                }
                await self.cleanupOldImages()
            }
            
            // Show toast message for "Maybe" action
            Task { @MainActor in
                self.toast.show(
                    "Photo marked as Maybe?", 
                    action: "Undo",
                    duration: 3.0,
                    onAction: {
                        // Undo action
                        self.photoManager.removeAsset(asset, fromAlbumNamed: "Maybe?")
                        self.photoManager.unmarkForFavourite(asset)
                        withAnimation {
                            self.currentIndex = capturedIndex
                            self.offset = .zero
                        }
                    }
                )
            }
        }
    }
} 
