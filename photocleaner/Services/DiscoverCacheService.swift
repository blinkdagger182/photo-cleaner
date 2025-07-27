import Foundation
import Photos
import CoreData
import Combine

/// Service that manages intelligent caching for the Discover feature
/// Monitors photo library changes and validates cache freshness
class DiscoverCacheService: NSObject, ObservableObject {
    static let shared = DiscoverCacheService()
    
    // MARK: - Published Properties
    @Published var isCacheValid: Bool = false
    @Published var lastCacheUpdate: Date?
    @Published var photoLibraryHash: String = ""
    
    // MARK: - Private Properties
    private let persistence = PersistenceController.shared
    private var cancellables = Set<AnyCancellable>()
    private let cacheValidityHours: TimeInterval = 24 // Cache valid for 24 hours
    private let userDefaults = UserDefaults.standard
    
    // UserDefaults Keys
    private let lastCacheUpdateKey = "DiscoverCacheLastUpdate"
    private let photoLibraryHashKey = "DiscoverPhotoLibraryHash"
    private let cachedAlbumCountKey = "DiscoverCachedAlbumCount"
    
    private override init() {
        super.init()
        setupPhotoLibraryObserver()
        loadCacheMetadata()
        validateCacheOnInit()
    }
    
    // MARK: - Public Methods
    
    /// Check if cached albums are valid and should be used
    func shouldUseCachedAlbums() -> Bool {
        return isCacheValid && hasCachedAlbums()
    }
    
    /// Mark cache as updated with new album generation
    func markCacheUpdated(albumCount: Int) {
        let now = Date()
        lastCacheUpdate = now
        photoLibraryHash = generateCurrentPhotoLibraryHash()
        
        // Save to UserDefaults
        userDefaults.set(now, forKey: lastCacheUpdateKey)
        userDefaults.set(photoLibraryHash, forKey: photoLibraryHashKey)
        userDefaults.set(albumCount, forKey: cachedAlbumCountKey)
        
        isCacheValid = true
        
        print("📦 Cache marked as updated with \(albumCount) albums")
    }
    
    /// Invalidate cache manually (useful for debugging or forced refresh)
    func invalidateCache() {
        isCacheValid = false
        userDefaults.removeObject(forKey: lastCacheUpdateKey)
        userDefaults.removeObject(forKey: photoLibraryHashKey)
        userDefaults.removeObject(forKey: cachedAlbumCountKey)
        
        print("📦 Cache manually invalidated")
    }
    
    /// Get cache statistics for debugging
    func getCacheInfo() -> (isValid: Bool, lastUpdate: Date?, albumCount: Int, libraryHash: String) {
        return (
            isValid: isCacheValid,
            lastUpdate: lastCacheUpdate,
            albumCount: userDefaults.integer(forKey: cachedAlbumCountKey),
            libraryHash: photoLibraryHash
        )
    }
    
    // MARK: - Private Methods
    
    private func setupPhotoLibraryObserver() {
        // Monitor photo library changes
        PHPhotoLibrary.shared().register(self)
    }
    
    private func loadCacheMetadata() {
        if let lastUpdate = userDefaults.object(forKey: lastCacheUpdateKey) as? Date {
            lastCacheUpdate = lastUpdate
        }
        
        photoLibraryHash = userDefaults.string(forKey: photoLibraryHashKey) ?? ""
    }
    
    private func validateCacheOnInit() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let isValid = self.validateCacheInternal()
            
            DispatchQueue.main.async {
                self.isCacheValid = isValid
                print("📦 Cache validation on init: \(isValid ? "VALID" : "INVALID")")
            }
        }
    }
    
    private func validateCacheInternal() -> Bool {
        // Check if we have cached albums
        guard hasCachedAlbums() else {
            print("📦 No cached albums found")
            return false
        }
        
        // Check cache age
        guard let lastUpdate = lastCacheUpdate else {
            print("📦 No last update time found")
            return false
        }
        
        let hoursSinceUpdate = Date().timeIntervalSince(lastUpdate) / 3600
        guard hoursSinceUpdate < cacheValidityHours else {
            print("📦 Cache expired (age: \(String(format: "%.1f", hoursSinceUpdate)) hours)")
            return false
        }
        
        // Check if photo library has changed
        let currentHash = generateCurrentPhotoLibraryHash()
        guard currentHash == photoLibraryHash else {
            print("📦 Photo library changed - stored: '\(photoLibraryHash)', current: '\(currentHash)'")
            return false
        }
        
        print("📦 Cache is VALID (age: \(String(format: "%.1f", hoursSinceUpdate)) hours, \(userDefaults.integer(forKey: cachedAlbumCountKey)) albums)")
        return true
    }
    
    private func hasCachedAlbums() -> Bool {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<SmartAlbumGroup> = SmartAlbumGroup.fetchRequest()
        fetchRequest.fetchLimit = 1
        
        do {
            let count = try context.count(for: fetchRequest)
            return count > 0
        } catch {
            print("📦 Error checking cached albums: \(error)")
            return false
        }
    }
    
    private func generateCurrentPhotoLibraryHash() -> String {
        let authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return "no_access"
        }
        
        // Create a lightweight hash based on photo count and recent changes
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = false
        
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let allVideos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        let totalCount = allPhotos.count + allVideos.count
        
        // Get most recent photo date for additional validation
        let recentFetchOptions = PHFetchOptions()
        recentFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        recentFetchOptions.fetchLimit = 1
        
        let recentPhotos = PHAsset.fetchAssets(with: recentFetchOptions)
        let recentPhotoDate = recentPhotos.firstObject?.creationDate?.timeIntervalSince1970 ?? 0
        
        // Create a simple hash combining count and recent date
        let hashString = "\(totalCount)_\(Int(recentPhotoDate))"
        return hashString
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension DiscoverCacheService: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            // When photo library changes, invalidate cache
            let newHash = self.generateCurrentPhotoLibraryHash()
            
            DispatchQueue.main.async {
                if newHash != self.photoLibraryHash {
                    self.isCacheValid = false
                    self.photoLibraryHash = newHash
                    print("📦 Photo library changed - cache invalidated")
                } else {
                    print("📦 Photo library change detected but hash unchanged")
                }
            }
        }
    }
} 