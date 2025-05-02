import UIKit
import Photos

/// A memory-efficient photo cache manager that handles large photo libraries
class OptimizedPhotoCache {
    // Singleton instance
    static let shared = OptimizedPhotoCache()
    
    // PHCachingImageManager is more memory efficient than PHImageManager
    private let imageManager = PHCachingImageManager()
    
    // Cache for storing downsampled thumbnails with automatic purging
    private let imageCache = NSCache<NSString, UIImage>()
    
    // Track current photo requests to allow cancellation
    private var requestIDs: [String: PHImageRequestID] = [:]
    
    // Track memory pressure
    private var isUnderMemoryPressure = false
    
    private init() {
        // Set cache limits to prevent memory issues
        imageCache.totalCostLimit = 25 * 1024 * 1024 // 25MB limit
        imageCache.countLimit = 100 // Max 100 images
        
        // Register for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Register for app lifecycle notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        // Clear cache when app goes to background
        clearCache()
    }
    
    @objc private func handleAppWillEnterForeground() {
        // Reset memory pressure flag when app comes to foreground
        isUnderMemoryPressure = false
    }
    
    @objc private func didReceiveMemoryWarning() {
        // Set memory pressure flag
        isUnderMemoryPressure = true
        
        // Clear the cache
        clearCache()
    }
    
    /// Clears the image cache to free up memory
    func clearCache() {
        imageCache.removeAllObjects()
        
        // Cancel all pending requests
        for (_, requestID) in requestIDs {
            imageManager.cancelImageRequest(requestID)
        }
        
        requestIDs.removeAll()
    }
    
    /// Prefetch thumbnails for a set of assets
    /// - Parameters:
    ///   - assets: The assets to prefetch
    ///   - size: The thumbnail size
    func prefetchThumbnails(for assets: [PHAsset], size: CGSize) {
        // Skip if under memory pressure
        if isUnderMemoryPressure {
            return
        }
        
        // Tell the PHCachingImageManager to start caching
        imageManager.startCachingImages(
            for: assets,
            targetSize: size,
            contentMode: .aspectFill,
            options: nil
        )
    }
    
    /// Stop prefetching thumbnails for a set of assets
    /// - Parameters:
    ///   - assets: The assets to stop prefetching
    ///   - size: The thumbnail size
    func stopPrefetchingThumbnails(for assets: [PHAsset], size: CGSize) {
        imageManager.stopCachingImages(
            for: assets,
            targetSize: size,
            contentMode: .aspectFill,
            options: nil
        )
    }
    
    /// Load a thumbnail image for an asset with memory-efficient caching and lazy loading
    /// - Parameters:
    ///   - asset: The asset to load
    ///   - targetSize: The desired thumbnail size
    ///   - contentMode: The content mode
    ///   - completion: Completion handler with the thumbnail image
    func loadThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        completion: @escaping (UIImage?) -> Void
    ) {
        // Use a larger size for better quality while maintaining performance
        let limitedSize = CGSize(
            width: min(targetSize.width * 2, 1024),  // Doubled size with 1024 max
            height: min(targetSize.height * 2, 1024) // Doubled size with 1024 max
        )
        
        // Create a cache key
        let cacheKey = NSString(string: "\(asset.localIdentifier)_\(Int(limitedSize.width))x\(Int(limitedSize.height))")
        
        // Check if image is already in cache
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            // Return cached image immediately
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }
        
        // For lazy loading, provide a placeholder immediately if needed
        let placeholderImage = UIImage(systemName: "photo")
        DispatchQueue.main.async {
            completion(placeholderImage)
        }
        
        // Cancel any existing request for this asset
        if let existingRequestID = requestIDs[asset.localIdentifier] {
            imageManager.cancelImageRequest(existingRequestID)
            requestIDs.removeValue(forKey: asset.localIdentifier)
        }
        
        // Set up request options with improved quality
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // Request high quality images
        options.isNetworkAccessAllowed = true // Allow fetching from iCloud if needed
        options.resizeMode = .exact // Use exact resizing for better quality
        options.isSynchronous = false // Keep asynchronous for performance
        
        // Request the image with background priority for lazy loading
        let requestID = imageManager.requestImage(
            for: asset,
            targetSize: limitedSize,
            contentMode: contentMode,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }
            
            // Check if request was cancelled or has an error
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            let hasError = (info?[PHImageErrorKey] != nil)
            
            if cancelled || hasError {
                return // Don't call completion again as we already provided a placeholder
            }
            
            if let originalImage = image {
                // Downsample the image to ensure it's not too large for CoreAnimation
                let downsampledImage = self.downsampleImageIfNeeded(originalImage, to: limitedSize)
                
                // Store in cache with cost proportional to image size
                let cost = Int(downsampledImage.size.width * downsampledImage.size.height * 4) // 4 bytes per pixel
                self.imageCache.setObject(downsampledImage, forKey: cacheKey, cost: cost)
                
                // Remove request ID from tracking
                self.requestIDs.removeValue(forKey: asset.localIdentifier)
                
                // Deliver the final high-quality image on the main thread
                DispatchQueue.main.async {
                    completion(downsampledImage)
                }
            }
        }
        
        // Store the request ID for potential cancellation
        requestIDs[asset.localIdentifier] = requestID
    }
    
    /// Downsample an image if it exceeds the maximum dimensions
    /// - Parameters:
    ///   - image: The original image
    ///   - targetSize: The target size
    /// - Returns: A properly sized image
    private func downsampleImageIfNeeded(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        // If image is already smaller than target, return it as is
        if image.size.width <= targetSize.width && image.size.height <= targetSize.height {
            return image
        }
        
        // Aggressive downsampling for memory efficiency
        let scale = UIScreen.main.scale
        let scaledTargetSize = CGSize(
            width: targetSize.width * scale,
            height: targetSize.height * scale
        )
        
        // Create a bitmap context for downsampling
        guard let cgImage = image.cgImage else { return image }
        
        let imageRect = CGRect(origin: .zero, size: scaledTargetSize)
        
        // Use UIGraphicsImageRenderer for better memory management
        let renderer = UIGraphicsImageRenderer(size: scaledTargetSize)
        let downsampledImage = renderer.image { context in
            // Draw the image in the context at the target size
            context.cgContext.interpolationQuality = .medium
            context.cgContext.draw(cgImage, in: imageRect)
        }
        
        return downsampledImage
    }
    
    /// Load a very small thumbnail for cell display
    /// - Parameters:
    ///   - asset: The asset to load
    ///   - completion: Completion handler with the thumbnail image
    func loadCellThumbnail(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        // Use a very small size for cells to prevent memory issues
        let cellSize = CGSize(width: 150, height: 150)
        loadThumbnail(for: asset, targetSize: cellSize, completion: completion)
    }
    
    /// Cancel loading for an asset
    /// - Parameter asset: The asset to cancel
    func cancelLoading(for asset: PHAsset) {
        if let requestID = requestIDs[asset.localIdentifier] {
            imageManager.cancelImageRequest(requestID)
            requestIDs.removeValue(forKey: asset.localIdentifier)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
