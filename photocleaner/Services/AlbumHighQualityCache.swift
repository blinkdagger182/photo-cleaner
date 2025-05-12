import UIKit
import Photos

/// A dedicated cache for high-quality first images of albums
class AlbumHighQualityCache {
    // Singleton instance
    static let shared = AlbumHighQualityCache()
    
    // Cache for storing high-quality first images with automatic purging
    private let imageCache = NSCache<NSString, UIImage>()
    
    // Track current photo requests to allow cancellation
    private var requestIDs: [String: PHImageRequestID] = [:]
    
    // Track memory pressure
    private var isUnderMemoryPressure = false
    
    // PHImageManager for high-quality requests
    private let imageManager = PHImageManager.default()
    
    // Maximum size for cached images (width/height)
    private let maxCachedImageSize: CGFloat = 1800
    
    private init() {
        // Set cache limits - higher than thumbnail cache since these are important images
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
        imageCache.countLimit = 30 // Max 30 high-quality images
        
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
    }
    
    @objc private func appDidEnterBackground() {
        // Clear cache when app goes to background
        clearCache()
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
    
    /// Pre-cache the first image of a PhotoGroup in high quality
    /// - Parameters:
    ///   - group: The PhotoGroup to cache the first image for
    ///   - completion: Optional completion handler with the cached image
    func cacheFirstImage(for group: PhotoGroup, completion: ((UIImage?) -> Void)? = nil) {
        // Skip if under memory pressure
        if isUnderMemoryPressure {
            completion?(nil)
            return
        }
        
        // Get the first asset
        guard let asset = group.asset(at: 0) else {
            completion?(nil)
            return
        }
        
        // Create a cache key
        let cacheKey = NSString(string: "first_\(group.id.uuidString)")
        
        // Check if image is already in cache
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            // Return cached image immediately
            completion?(cachedImage)
            return
        }
        
        // Cancel any existing request for this asset
        if let existingRequestID = requestIDs[asset.localIdentifier] {
            imageManager.cancelImageRequest(existingRequestID)
            requestIDs.removeValue(forKey: asset.localIdentifier)
        }
        
        // Calculate optimal size based on screen dimensions
        let screenSize = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: min(screenSize.width * scale, maxCachedImageSize),
            height: min(screenSize.height * scale, maxCachedImageSize)
        )
        
        // Set up request options with high quality
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        options.isSynchronous = false
        
        // Request the image
        let requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }
            
            // Check if request was cancelled or has an error
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            let hasError = (info?[PHImageErrorKey] != nil)
            
            if cancelled || hasError {
                completion?(nil)
                return
            }
            
            if let originalImage = image {
                // Process the image if needed to avoid DisplayP3 color space issues
                Task {
                    let processedImage = await self.convertToStandardColorSpaceIfNeeded(originalImage)
                    
                    // Store in cache with cost proportional to image size
                    if let processedImage = processedImage {
                        let cost = Int(processedImage.size.width * processedImage.size.height * 4) // 4 bytes per pixel
                        self.imageCache.setObject(processedImage, forKey: cacheKey, cost: cost)
                        
                        // Remove request ID from tracking
                        self.requestIDs.removeValue(forKey: asset.localIdentifier)
                        
                        // Deliver the final high-quality image on the main thread
                        DispatchQueue.main.async {
                            completion?(processedImage)
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion?(originalImage)
                        }
                    }
                }
            } else {
                completion?(nil)
            }
        }
        
        // Store the request ID for potential cancellation
        requestIDs[asset.localIdentifier] = requestID
    }
    
    /// Pre-cache the first images of multiple PhotoGroups in high quality
    /// - Parameter groups: Array of PhotoGroups to cache first images for
    func cacheFirstImages(for groups: [PhotoGroup]) {
        // Skip if under memory pressure
        if isUnderMemoryPressure {
            return
        }
        
        // Process each group with a small delay between requests to avoid overwhelming the system
        for (index, group) in groups.enumerated() {
            // Add a small delay between requests to avoid overwhelming the system
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) { [weak self] in
                self?.cacheFirstImage(for: group)
            }
        }
    }
    
    /// Get a cached high-quality first image for a PhotoGroup
    /// - Parameter group: The PhotoGroup to get the first image for
    /// - Returns: The cached high-quality image, or nil if not cached
    func getCachedFirstImage(for group: PhotoGroup) -> UIImage? {
        let cacheKey = NSString(string: "first_\(group.id.uuidString)")
        return imageCache.object(forKey: cacheKey)
    }
    
    /// Convert image to standard color space to avoid DisplayP3 issues
    private func convertToStandardColorSpaceIfNeeded(_ image: UIImage) async -> UIImage? {
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
    
    /// Pre-cache a specific image with high priority
    /// This is useful when a user has just selected an album and we want to load the first image quickly
    /// - Parameters:
    ///   - group: The PhotoGroup to cache the first image for
    ///   - completion: Optional completion handler with the cached image
    func preloadFirstImageWithHighPriority(for group: PhotoGroup, completion: ((UIImage?) -> Void)? = nil) {
        // Skip if under memory pressure
        if isUnderMemoryPressure {
            completion?(nil)
            return
        }
        
        // Get the first asset
        guard let asset = group.asset(at: 0) else {
            completion?(nil)
            return
        }
        
        // Create a cache key
        let cacheKey = NSString(string: "first_\(group.id.uuidString)")
        
        // Check if image is already in cache
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            // Return cached image immediately
            completion?(cachedImage)
            return
        }
        
        // Cancel any existing request for this asset
        if let existingRequestID = requestIDs[asset.localIdentifier] {
            imageManager.cancelImageRequest(existingRequestID)
            requestIDs.removeValue(forKey: asset.localIdentifier)
        }
        
        // Calculate optimal size based on screen dimensions - use higher resolution for priority loading
        let screenSize = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: min(screenSize.width * scale * 1.5, maxCachedImageSize),
            height: min(screenSize.height * scale * 1.5, maxCachedImageSize)
        )
        
        // Set up request options with highest quality
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        options.isSynchronous = false
        options.version = .original // Use original version for highest quality
        
        // Set higher priority
        options.isNetworkAccessAllowed = true
        
        // Request the image
        let requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }
            
            // Check if request was cancelled or has an error
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            let hasError = (info?[PHImageErrorKey] != nil)
            
            if cancelled || hasError {
                completion?(nil)
                return
            }
            
            if let originalImage = image {
                // Process the image if needed to avoid DisplayP3 color space issues
                Task {
                    let processedImage = await self.convertToStandardColorSpaceIfNeeded(originalImage)
                    
                    // Store in cache with cost proportional to image size
                    if let processedImage = processedImage {
                        let cost = Int(processedImage.size.width * processedImage.size.height * 4) // 4 bytes per pixel
                        self.imageCache.setObject(processedImage, forKey: cacheKey, cost: cost)
                        
                        // Remove request ID from tracking
                        self.requestIDs.removeValue(forKey: asset.localIdentifier)
                        
                        // Deliver the final high-quality image on the main thread
                        DispatchQueue.main.async {
                            completion?(processedImage)
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion?(originalImage)
                        }
                    }
                }
            } else {
                completion?(nil)
            }
        }
        
        // Store the request ID for potential cancellation
        requestIDs[asset.localIdentifier] = requestID
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 