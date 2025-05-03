import SwiftUI
import Photos

/// A beautiful full-screen loader that displays a slideshow of the user's photos
/// while the app processes and organizes albums.
struct ProcessingImagesLoader: View {
    // MARK: - Properties
    
    // Progress tracking
    var progress: Double
    var totalPhotoCount: Int
    var processedAlbumCount: Int
    
    // Image slideshow state
    @State private var currentImageIndex = 0
    @State private var images: [UIImage] = []
    @State private var opacity = 0.0
    @State private var isLoading = true
    @State private var transitionTask: Task<Void, Never>?
    @State private var loadingTask: Task<Void, Never>?
    
    // Configuration
    private let maxSampleSize = 50
    private let transitionDuration: Double = 0.3
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background blur
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 30) {
                    // Header text
                    Text("Creating Your Photo Albums")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 40)
                    
                    // Slideshow container
                    ZStack {
                        // Background reflection effect
                        if let currentImage = currentImage {
                            Image(uiImage: currentImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                                .blur(radius: 20)
                                .opacity(0.3)
                                .edgesIgnoringSafeArea(.all)
                        }
                        
                        // Main slideshow
                        ZStack {
                            if images.isEmpty {
                                // Placeholder when no images are loaded yet
                                loadingPlaceholder(geometry: geometry)
                            } else if let currentImage = currentImage {
                                // Current image with fade animation
                                Image(uiImage: currentImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width * 0.8, height: geometry.size.width * 0.8)
                                    .cornerRadius(16)
                                    .clipped()
                                    .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
                                    .opacity(opacity)
                            }
                        }
                        .overlay(
                            // Image counter overlay (only when we have images)
                            Group {
                                if !images.isEmpty {
                                    Text("\(currentImageIndex + 1)/\(images.count)")
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                            }
                            .padding(12),
                            alignment: .bottomTrailing
                        )
                        .padding(.bottom, 20)
                    }
                    .frame(height: geometry.size.height * 0.5)
                    
                    // Progress section
                    VStack(spacing: 15) {
                        // Progress text
                        Text("Processing \(totalPhotoCount) photos")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        // Progress bar
                        ProgressBar(progress: progress, width: geometry.size.width * 0.8)
                        
                        // Percentage and album count
                        HStack {
                            Text("\(Int(progress * 100))%")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            if processedAlbumCount > 0 {
                                Text("\(processedAlbumCount) albums created")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .frame(width: geometry.size.width * 0.8)
                    }
                    .padding(.top, 20)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadImages()
            startImageTransitions()
        }
        .onDisappear {
            // Cancel tasks when view disappears
            transitionTask?.cancel()
            loadingTask?.cancel()
        }
    }
    
    // MARK: - Subviews
    
    /// Loading placeholder shown before any images are loaded
    private func loadingPlaceholder(geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: geometry.size.width * 0.8, height: geometry.size.width * 0.8)
            .cornerRadius(16)
            .overlay(
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.6))
                    
                    if isLoading {
                        Text("Loading your photos...")
                            .foregroundColor(.white)
                            .font(.subheadline)
                            .padding(.top, 4)
                        
                        ProgressView()
                            .scaleEffect(1.0)
                            .tint(.white)
                    }
                }
            )
    }
    
    /// Customized progress bar with gradient
    private struct ProgressBar: View {
        var progress: Double
        var width: CGFloat
        
        var body: some View {
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 12)
                
                // Progress indicator
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, CGFloat(progress) * width), height: 12)
                    .animation(.linear(duration: 0.5), value: progress)
            }
            .frame(width: width)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Returns the current image for display or nil if no images are available
    private var currentImage: UIImage? {
        guard !images.isEmpty, currentImageIndex < images.count else { return nil }
        return images[currentImageIndex]
    }
    
    // MARK: - Methods
    
    /// Starts the image transitions with dynamic timing
    private func startImageTransitions() {
        // Cancel any existing task
        transitionTask?.cancel()
        
        // Start with fade-in
        withAnimation(.easeIn(duration: transitionDuration)) {
            opacity = 1.0
        }
        
        // Create a new task for transitions
        transitionTask = Task {
            // Continue until the task is cancelled
            while !Task.isCancelled && !images.isEmpty {
                // Random delay between transitions (0.3-2.0 seconds)
                let delay = Int.random(in: 1...10) <= 8 
                    ? Double.random(in: 0.3...0.7)  // 80% quick transitions
                    : Double.random(in: 1.0...2.0)  // 20% longer pauses
                
                try? await Task.sleep(for: .seconds(delay))
                
                // Exit if task was cancelled during sleep
                if Task.isCancelled { break }
                
                // Transition to next image with crossfade
                await transitionToNextImage()
            }
        }
    }
    
    /// Transitions to the next image with animation
    @MainActor
    private func transitionToNextImage() async {
        guard images.count > 1 else { return }
        
        // Fade out current image
        withAnimation(.easeOut(duration: transitionDuration)) {
            opacity = 0
        }
        
        // Wait for fade-out to complete
        try? await Task.sleep(for: .seconds(transitionDuration))
        
        // Move to next image
        currentImageIndex = (currentImageIndex + 1) % images.count
        
        // Fade in new image
        withAnimation(.easeIn(duration: transitionDuration)) {
            opacity = 1.0
        }
    }
    
    /// Loads sample images from the photo library
    private func loadImages() {
        // Cancel any existing task
        loadingTask?.cancel()
        
        // Create a new task for loading images
        loadingTask = Task {
            do {
                // Set loading state
                await MainActor.run { isLoading = true }
                
                // Try to load user photos first
                let userPhotos = try await loadUserPhotos()
                
                // If we got user photos, update the UI
                if !userPhotos.isEmpty {
                    await MainActor.run {
                        images = userPhotos
                        isLoading = false
                        opacity = 1.0 // Ensure first image is visible
                    }
                } else {
                    // Fallback to system images only if we couldn't load user photos
                    await MainActor.run {
                        images = createFallbackImages()
                        isLoading = false
                        opacity = 1.0
                    }
                }
            } catch {
                // In case of error, use fallback images
                await MainActor.run {
                    images = createFallbackImages()
                    isLoading = false
                    opacity = 1.0
                }
            }
        }
    }
    
    /// Actor to manage photo loading tasks with thread safety
    private actor PhotoLoadingManager {
        private var loadedImages: [UIImage] = []
        private var minImagesNeeded = 10
        
        func addImage(_ image: UIImage) {
            loadedImages.append(image)
        }
        
        func hasEnoughImages() -> Bool {
            return loadedImages.count >= minImagesNeeded
        }
        
        func getImages() -> [UIImage] {
            return loadedImages
        }
    }
    
    /// Loads user photos from the photo library using multiple parallel tasks
    private func loadUserPhotos() async throws -> [UIImage] {
        let manager = PhotoLoadingManager()
        
        // Create parallel loading tasks for better performance
        let loadTasks = 3
        var tasks: [Task<Void, Error>] = []
        
        for taskIndex in 0..<loadTasks {
            let task = Task {
                // Set up fetch options
                let fetchOptions = PHFetchOptions()
                
                // Use different sort orders for variety in each task
                if taskIndex % 3 == 0 {
                    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                } else if taskIndex % 3 == 1 {
                    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
                } else {
                    // Random selection
                    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                }
                
                // Fetch all image assets
                let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                let totalCount = allAssets.count
                
                // Exit early if there are no photos
                if totalCount == 0 {
                    return
                }
                
                // Determine sample size per task
                let samplePerTask = min(maxSampleSize / loadTasks, totalCount)
                var processedCount = 0
                
                // Generate random indices without duplicates
                var selectedIndices = Set<Int>()
                while selectedIndices.count < samplePerTask {
                    // Create different random samples for each task to avoid duplication
                    let randomBase = (taskIndex * totalCount / loadTasks)
                    let range = min(totalCount - randomBase, totalCount / loadTasks * 2)
                    if range <= 0 { break }
                    
                    let randomIndex = Int.random(in: randomBase..<(randomBase + range)) % totalCount
                    selectedIndices.insert(randomIndex)
                }
                
                // Convert to array and sort for deterministic order
                let indices = Array(selectedIndices).sorted()
                
                // Set up image request options
                let requestOptions = PHImageRequestOptions()
                requestOptions.deliveryMode = .highQualityFormat
                requestOptions.resizeMode = .exact
                requestOptions.isNetworkAccessAllowed = true
                requestOptions.isSynchronous = false
                
                // Load images one by one
                for index in indices {
                    // Check if we have enough images already
                    if await manager.hasEnoughImages() {
                        break
                    }
                    
                    // Check if task is cancelled
                    try Task.checkCancellation()
                    
                    // Get the asset
                    let asset = allAssets.object(at: index)
                    
                    // Load image with async/await
                    if let image = try await loadImageFromAsset(asset, with: requestOptions) {
                        // Add to our collection
                        await manager.addImage(image)
                        
                        // Update UI immediately with the first few images
                        processedCount += 1
                        
                        if processedCount <= 3 {
                            // Get current images and update UI
                            let currentImages = await manager.getImages()
                            await MainActor.run {
                                self.images = currentImages
                                if self.images.count == 1 {
                                    // Make first image visible immediately
                                    self.opacity = 1.0
                                }
                            }
                        }
                    }
                }
            }
            
            tasks.append(task)
        }
        
        // Wait for all tasks to complete or the first error
        do {
            // Use a timeout to avoid waiting too long
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(10))
                return true // Return true to indicate timeout
            }
            
            // Racing between timeout and completion of all tasks
            let timedOut = await timeoutTask.value
            
            if !timedOut {
                // Try to wait for all tasks (this is optimistic)
                for task in tasks {
                    try await task.value
                }
            }
            
            // Cancel all tasks
            for task in tasks {
                task.cancel()
            }
            timeoutTask.cancel()
            
            // Get the loaded images
            return await manager.getImages()
        } catch {
            // Cancel all tasks on error
            for task in tasks {
                task.cancel()
            }
            throw error
        }
    }
    
    /// Loads a single image from a PHAsset
    private func loadImageFromAsset(_ asset: PHAsset, with options: PHImageRequestOptions) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            let targetSize = CGSize(width: 800, height: 800)
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Check for cancellation
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                // Check if we got a valid, non-degraded image
                if let image = image,
                   let info = info,
                   info[PHImageResultIsDegradedKey] as? Bool == false,
                   info[PHImageCancelledKey] as? Bool != true,
                   info[PHImageErrorKey] == nil {
                    continuation.resume(returning: image)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Creates fallback system images for when user photos can't be loaded
    private func createFallbackImages() -> [UIImage] {
        let fallbackSymbols = [
            "photo", "photo.on.rectangle", "photo.on.rectangle.angled", 
            "photo.fill", "photo.fill.on.rectangle.fill", "rectangle.stack.fill"
        ]
        
        var fallbackImages: [UIImage] = []
        let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .regular)
        
        for symbol in fallbackSymbols {
            if let symbolImage = UIImage(systemName: symbol, withConfiguration: config) {
                // Create a properly sized and rendered image
                UIGraphicsBeginImageContextWithOptions(CGSize(width: 800, height: 800), false, 0)
                
                // Fill background
                UIColor(white: 0.15, alpha: 1.0).setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 0, width: 800, height: 800)).fill()
                
                // Draw symbol centered
                symbolImage.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(x: 250, y: 250, width: 300, height: 300))
                
                if let renderedImage = UIGraphicsGetImageFromCurrentImageContext() {
                    fallbackImages.append(renderedImage)
                }
                
                UIGraphicsEndImageContext()
            }
        }
        
        return fallbackImages
    }
}

// MARK: - Preview

struct ProcessingImagesLoader_Previews: PreviewProvider {
    static var previews: some View {
        ProcessingImagesLoader(
            progress: 0.65,
            totalPhotoCount: 1250,
            processedAlbumCount: 12
        )
    }
} 