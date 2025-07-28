import Foundation
import CoreData
import Photos

/// A service responsible for caching and retrieving Discover albums using CoreData
class DiscoverCacheManager {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Fetches cached albums from CoreData and converts them to PhotoGroup models
    /// - Returns: Array of PhotoGroup objects or nil if no cache exists
    func fetchCachedAlbums() -> [PhotoGroup]? {
        let request: NSFetchRequest<CachedDiscoverAlbum> = CachedDiscoverAlbum.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CachedDiscoverAlbum.creationDate, ascending: false)]
        
        do {
            let cachedAlbums = try context.fetch(request)
            
            guard !cachedAlbums.isEmpty else {
                return nil
            }
            
            // Convert cached albums to PhotoGroup objects
            var photoGroups: [PhotoGroup] = []
            
            for cachedAlbum in cachedAlbums {
                guard let assetIdentifiers = cachedAlbum.assetIdentifiers,
                      let albumTitle = cachedAlbum.title,
                      let albumId = cachedAlbum.id,
                      let creationDate = cachedAlbum.creationDate else {
                    continue
                }
                
                // Fetch PHAssets using the cached identifiers
                let assets = fetchAssets(from: assetIdentifiers)
                
                // Only include albums that still have valid assets
                if !assets.isEmpty {
                    let photoGroup = PhotoGroup(
                        id: albumId,
                        assets: assets,
                        title: albumTitle,
                        monthDate: creationDate,
                        lastViewedIndex: 0
                    )
                    photoGroups.append(photoGroup)
                }
            }
            
            return photoGroups.isEmpty ? nil : photoGroups
            
        } catch {
            print("Error fetching cached albums: \(error)")
            return nil
        }
    }
    
    /// Saves PhotoGroup objects to CoreData cache
    /// - Parameter photoGroups: Array of PhotoGroup objects to cache
    func saveAlbums(_ photoGroups: [PhotoGroup]) {
        // Clear existing cache first
        clearCache()
        
        for photoGroup in photoGroups {
            let cachedAlbum = CachedDiscoverAlbum(context: context)
            cachedAlbum.id = photoGroup.id
            cachedAlbum.title = photoGroup.title
            cachedAlbum.creationDate = photoGroup.monthDate ?? Date()
            cachedAlbum.assetIdentifiers = photoGroup.assets.map { $0.localIdentifier }
            cachedAlbum.coverAssetIdentifier = photoGroup.thumbnailAsset?.localIdentifier ?? ""
        }
        
        saveContext()
    }
    
    /// Clears all cached albums from CoreData
    func clearCache() {
        let request: NSFetchRequest<NSFetchRequestResult> = CachedDiscoverAlbum.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        
        do {
            try context.execute(deleteRequest)
            saveContext()
        } catch {
            print("Error clearing cache: \(error)")
        }
    }
    
    /// Checks if valid cached data exists
    /// - Returns: True if cached albums exist and are recent
    func hasCachedData() -> Bool {
        let request: NSFetchRequest<CachedDiscoverAlbum> = CachedDiscoverAlbum.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("Error checking cached data: \(error)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    /// Fetches PHAssets from their local identifiers
    /// - Parameter identifiers: Array of asset local identifiers
    /// - Returns: Array of valid PHAsset objects
    private func fetchAssets(from identifiers: [String]) -> [PHAsset] {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        return assets
    }
    
    /// Saves the CoreData context
    private func saveContext() {
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
} 