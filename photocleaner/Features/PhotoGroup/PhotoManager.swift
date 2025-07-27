import Foundation
import Photos
import SwiftUI
import UIKit

// Import models from Core/Models
@_implementationOnly import struct photocleaner.PhotoGroup
@_implementationOnly import struct photocleaner.YearGroup
@_implementationOnly import struct photocleaner.DeletePreviewEntry

class PhotoManager: NSObject, ObservableObject {
    @Published var allPhotos: [PHAsset] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allAssets: [PHAsset] = []
    @Published var photoGroups: [PhotoGroup] = []
    @Published var yearGroups: [YearGroup] = []
    @Published var markedForDeletion: Set<String> = []  // asset.localIdentifier
    @Published var markedForBookmark: Set<String> = []
    @Published var deletedImagesPreview: [DeletePreviewEntry] = [] // Track all deleted images for preview
    @Published var isLoadingInitialData: Bool = false
    @Published var isLoadingCompleteLibrary: Bool = false
    @Published var hasLoadedInitialData: Bool = false

    private let lastViewedIndexKey = "LastViewedIndex"
    private let markedForDeletionFileName = "MarkedForDeletion.json"
    private let deletedPreviewIdentifiersFileName = "DeletedPreviewIdentifiers.json"
    private var isPerformingInternalChange = false // Flag to track internal changes through our UI
    private var isPreloading = false // Flag to prevent reloads during preloading
    private var lastReloadTime: Date = .distantPast
    private let reloadThrottleInterval: TimeInterval = 2.0 // Minimum seconds between reloads
    private var isObservingPhotoLibrary = false // Flag to track if we're already observing
    
    // Task for debouncing reloads
    private var pendingReloadTask: Task<Void, Never>?
    
    // Store the current fetch result for change detection
    private var currentAssetsFetchResult: PHFetchResult<PHAsset>?

    override init() {
        super.init()
        // Removed PHPhotoLibrary registration to prevent premature permission requests
        
        // Load marked for deletion identifiers from persistent storage
        // Do this asynchronously so it doesn't block init
        Task {
            await loadMarkedForDeletion()
            await loadDeletedPreviewIdentifiers()
        }
    }

//    deinit {
//        if isObservingPhotoLibrary {
//            PHPhotoLibrary.shared().unregisterChangeObserver(self)
//        }
//        pendingReloadTask?.cancel()
//    }
    
    // Add a method to start observing photo library changes only after permissions are granted
//    private func startObservingPhotoChanges() {
//        if !isObservingPhotoLibrary {
//            print("📸 Starting to observe photo library changes.")
//            PHPhotoLibrary.shared().register(self)
//            isObservingPhotoLibrary = true
//        }
//    }

    // MARK: - Persistence for Marked for Deletion
    
    /// Returns the URL for the marked for deletion file in the documents directory
    private func getMarkedForDeletionURL() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent(markedForDeletionFileName)
    }
    
    /// Returns the URL for the deleted preview identifiers file in the documents directory
    private func getDeletedPreviewIdentifiersURL() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent(deletedPreviewIdentifiersFileName)
    }
    
    /// Loads saved marked for deletion identifiers from persistent storage
    private func loadMarkedForDeletion() async {
        // Execute file operations on a background queue
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let fileURL = self.getMarkedForDeletionURL()
                
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("📝 No marked for deletion file exists yet")
                    continuation.resume()
                    return
                }
                
                do {
                    let data = try Data(contentsOf: fileURL)
                    let identifiers = try JSONDecoder().decode([String].self, from: data)
                    
                    await MainActor.run {
                        self.markedForDeletion = Set(identifiers)
                        print("📝 Loaded \(identifiers.count) identifiers marked for deletion")
                    }
                } catch {
                    print("❌ Error loading marked for deletion: \(error.localizedDescription)")
                }
                
                continuation.resume()
            }
        }
    }
    
    /// Loads saved preview identifiers from persistent storage and reconstructs the preview entries
    private func loadDeletedPreviewIdentifiers() async {
        // Execute file operations on a background queue
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let fileURL = self.getDeletedPreviewIdentifiersURL()
                
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("📝 No deleted preview identifiers file exists yet")
                    continuation.resume()
                    return
                }
                
                do {
                    let data = try Data(contentsOf: fileURL)
                    let identifiers = try JSONDecoder().decode([String].self, from: data)
                    
                    // Only proceed if we have identifiers to load
                    if !identifiers.isEmpty {
                        print("📝 Loading \(identifiers.count) deleted preview identifiers")
                        
                        // Fetch the PHAssets for these identifiers
                        let assets = PHAsset.fetchAssets(
                            withLocalIdentifiers: identifiers,
                            options: nil
                        )
                        
                        // We need to reconstruct the DeletePreviewEntry objects with images
                        assets.enumerateObjects { asset, _, _ in
                            // We only add assets that still exist in the photo library
                            // and are still marked for deletion
                            if self.markedForDeletion.contains(asset.localIdentifier) {
                                // Load a low-resolution thumbnail for the preview
                                Task {
                                    let image = await self.loadThumbnailImage(for: asset)
                                    if let image = image {
                                        await MainActor.run {
                                            let size = asset.estimatedAssetSize
                                            let entry = DeletePreviewEntry(asset: asset, image: image, fileSize: size)
                                            self.deletedImagesPreview.append(entry)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    print("❌ Error loading deleted preview identifiers: \(error.localizedDescription)")
                }
                
                continuation.resume()
            }
        }
    }
    
    /// Saves the current marked for deletion identifiers to persistent storage
    private func saveMarkedForDeletion() {
        let identifiers = Array(markedForDeletion)
        let fileURL = getMarkedForDeletionURL()
        
        do {
            let data = try JSONEncoder().encode(identifiers)
            try data.write(to: fileURL)
            print("📝 Saved \(identifiers.count) identifiers marked for deletion")
        } catch {
            print("❌ Error saving marked for deletion: \(error.localizedDescription)")
        }
    }
    
    /// Saves just the identifiers of assets in the deletedImagesPreview array
    private func saveDeletedPreviewIdentifiers() {
        let identifiers = deletedImagesPreview.map { $0.asset.localIdentifier }
        let fileURL = getDeletedPreviewIdentifiersURL()
        
        do {
            let data = try JSONEncoder().encode(identifiers)
            try data.write(to: fileURL)
            print("📝 Saved \(identifiers.count) deleted preview identifiers")
        } catch {
            print("❌ Error saving deleted preview identifiers: \(error.localizedDescription)")
        }
    }
    
    /// Helper method to load a thumbnail image for an asset
    private func loadThumbnailImage(for asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            // Track if we've already resumed to prevent multiple resumes
            var hasResumed = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Guard against multiple resume calls
                guard !hasResumed else { return }
                
                // Check for cancellation or errors
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = (info?[PHImageErrorKey] != nil)
                
                if cancelled || hasError {
                    // PHImageManager will call again with the final result
                    return
                }
                
                // Mark as resumed and return the image
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }
    
    // MARK: - Lifecycle and Change Observation
    
    // @objc func photoLibraryDidChange(_ changeInstance: PHChange) {
    //     // Skip reloads if it's from our own operations or if we're preloading images
    //     if isPerformingInternalChange || isPreloading {
    //         print("📝 Skipping reload - change was from our own operations")
    //         // Reset flag after handling
    //         isPerformingInternalChange = false
    //         return
    //     }
        
    //     // Check if we have a reference to the current fetch result to compare changes against
    //     guard let currentAssetsFetchResult = self.currentAssetsFetchResult else {
    //         // If we don't have a reference fetch result yet, perform a full reload once
    //         Task { @MainActor in
    //             print("📸 Initial photo library change detected, loading assets...")
    //             await self.loadAssets()
    //         }
    //         return
    //     }
        
    //     // Get detailed changes for our assets fetch result
    //     guard let details = changeInstance.changeDetails(for: currentAssetsFetchResult) else {
    //         // No changes relevant to our fetch result
    //         return
    //     }
        
    //     // Only reload if there are meaningful changes (additions or removals)
    //     let hasAdditions = details.insertedObjects.count > 0
    //     let hasRemovals = details.removedObjects.count > 0
        
    //     if hasAdditions || hasRemovals {
    //         // Throttle reloads to prevent multiple rapid reloads
    //         let now = Date()
    //         if now.timeIntervalSince(lastReloadTime) < reloadThrottleInterval {
    //             // Cancel any pending reload task
    //             pendingReloadTask?.cancel()
                
    //             // Schedule a new reload after the throttle interval
    //             pendingReloadTask = Task { @MainActor in
    //                 do {
    //                     // Wait until we're outside the throttle interval
    //                     let waitTime = reloadThrottleInterval - now.timeIntervalSince(lastReloadTime)
    //                     if waitTime > 0 {
    //                         try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
    //                     }
                        
    //                     // Check if task was cancelled during sleep
    //                     try Task.checkCancellation()
                        
    //                     if hasAdditions {
    //                         print("🔄 New photos added (\(details.insertedObjects.count)), reloading...")
    //                     } else if hasRemovals {
    //                         print("🔄 Photos deleted (\(details.removedObjects.count)), reloading...")
    //                     }
                        
    //                     await self.loadAssets()
    //                     lastReloadTime = Date()
    //                 } catch {
    //                     // Task was cancelled, do nothing
    //                 }
    //             }
    //             return
    //         }
            
    //         // If we're outside the throttle interval, reload immediately
    //         lastReloadTime = now
    //         Task { @MainActor in
    //             if hasAdditions {
    //                 print("🔄 New photos added (\(details.insertedObjects.count)), reloading...")
    //             } else if hasRemovals {
    //                 print("🔄 Photos deleted (\(details.removedObjects.count)), reloading...")
    //             }
    //             await self.loadAssets()
    //         }
    //     } else if details.changedObjects.count > 0 {
    //         // Just log changes that don't require reload (like metadata changes)
    //         print("ℹ️ Photo metadata changed for \(details.changedObjects.count) assets (no reload needed)")
    //     }
    // }

    // Set preloading state to prevent unnecessary reloads
    func setPreloadingState(_ isPreloading: Bool) {
        self.isPreloading = isPreloading
    }

    /// Checks the current photo authorization status without requesting permission
    func checkCurrentStatus() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        await MainActor.run {
            self.authorizationStatus = status
        }
        
        // If already authorized, load the assets
        if status == .authorized || status == .limited {
            await loadAssets()
//            startObservingPhotoChanges() // Start observing only after we have permission
        }
    }
    
    /// Progressive loading strategy: Load minimal data first, then continue in background
    private func loadAssets() async {
        await MainActor.run {
            self.isLoadingInitialData = true
            self.hasLoadedInitialData = false
        }
        
        // Phase 1: Get basic asset count and fetch result (minimal work)
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotoAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        // Store the fetch result for change detection
        self.currentAssetsFetchResult = allPhotoAssets
        
        let totalCount = allPhotoAssets.count
        
        // Update UI immediately with basic info
        await MainActor.run {
            print("📸 Found \(totalCount) total assets - starting progressive load")
        }
        
        // Phase 2: Load first batch of recent photos for immediate display (fast)
        await loadRecentPhotosForQuickDisplay()
        
        // Phase 3: Continue loading rest in background (slow work moved off critical path)
        Task.detached(priority: .utility) { [weak self] in
            await self?.loadAllAssetsInBackground()
        }
    }
    
    /// Phase 2: Load only recent photos for immediate UI display
    private func loadRecentPhotosForQuickDisplay() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 500 // Only load most recent 500 photos for quick start
        
        let recentAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        // Build basic groups from recent assets only
        let quickGroups = await buildPhotoGroupsFromAssets(recentAssets, isQuickLoad: true)
        
        await MainActor.run {
            // Update with initial data so UI can display immediately
            self.photoGroups = quickGroups
            self.yearGroups = self.organizeGroupsByYear(quickGroups)
            self.isLoadingInitialData = false
            self.hasLoadedInitialData = true
            print("📸 Quick loaded \(quickGroups.count) recent photo groups")
        }
    }
    
    /// Phase 3: Load all remaining assets in background
    private func loadAllAssetsInBackground() async {
        await MainActor.run {
            self.isLoadingCompleteLibrary = true
        }
        
        // This runs in background - load all assets without blocking UI
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotoAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        // Convert to array in chunks to avoid blocking
        var assetArray: [PHAsset] = []
        let chunkSize = 1000
        let totalAssets = allPhotoAssets.count
        
        for i in stride(from: 0, to: totalAssets, by: chunkSize) {
            let endIndex = min(i + chunkSize, totalAssets)
            
            // Process in chunks to avoid blocking
            for j in i..<endIndex {
                let asset = allPhotoAssets.object(at: j)
                assetArray.append(asset)
            }
            
            // Small yield between chunks
            await Task.yield()
        }
        
        // Build complete photo groups
        let allGroups = await buildPhotoGroupsFromAssets(allPhotoAssets, isQuickLoad: false)
        let systemAlbums = await fetchPhotoGroupsFromAlbums(albumNames: ["Deleted", "Maybe?"])
        
        // Update UI with complete data
        await MainActor.run {
            self.allAssets = assetArray
            self.photoGroups = allGroups + systemAlbums
            self.yearGroups = self.organizeGroupsByYear(self.photoGroups)
            self.isLoadingCompleteLibrary = false
            print("📸 Background loaded complete library: \(assetArray.count) assets, \(allGroups.count) groups")
        }
    }
    
    /// Helper method to build photo groups from assets with memory management
    private func buildPhotoGroupsFromAssets(_ fetchResult: PHFetchResult<PHAsset>, isQuickLoad: Bool) async -> [PhotoGroup] {
        var groupedByMonth: [Date: [PHAsset]] = [:]
        let calendar = Calendar.current
        
        let assetCount = fetchResult.count
        let chunkSize = isQuickLoad ? 100 : 1000
        
        // Process assets in chunks to avoid memory spikes
        for i in stride(from: 0, to: assetCount, by: chunkSize) {
            let endIndex = min(i + chunkSize, assetCount)
            
            for j in i..<endIndex {
                let asset = fetchResult.object(at: j)
                
                if !self.markedForDeletion.contains(asset.localIdentifier),
                   let date = asset.creationDate,
                   let monthDate = calendar.date(
                       from: calendar.dateComponents([.year, .month], from: date))
                {
                    groupedByMonth[monthDate, default: []].append(asset)
                }
            }
            
            // Yield periodically to keep UI responsive
            if i % (chunkSize * 5) == 0 {
                await Task.yield()
            }
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        
        let photoGroups = groupedByMonth.map { (monthDate, assets) in
            let title = dateFormatter.string(from: monthDate)
            return PhotoGroup(assets: assets, title: title, monthDate: monthDate)
        }
        
        return photoGroups.sorted {
            ($0.monthDate ?? .distantPast) > ($1.monthDate ?? .distantPast)
        }
    }
    
    /// Helper method to organize groups by year
    /// Only organizes time-based photo groups, excludes system albums like "Maybe?" and "Deleted"
    private func organizeGroupsByYear(_ photoGroups: [PhotoGroup]) -> [YearGroup] {
        let calendar = Calendar.current
        var yearMap: [Int: [PhotoGroup]] = [:]
        
        // System albums that should not be organized by year
        let systemAlbumNames = ["Maybe?", "Deleted"]
        
        for group in photoGroups {
            // Skip system albums - they should only appear in "My Albums" section
            if systemAlbumNames.contains(group.title) {
                continue
            }
            
            if let monthDate = group.monthDate {
                let components = calendar.dateComponents([.year], from: monthDate)
                let year = components.year ?? 0
                yearMap[year, default: []].append(group)
            }
        }
        
        let yearGroups = yearMap.map { (year, groups) in
            YearGroup(
                id: year,
                year: year,
                months: groups.sorted {
                    ($0.monthDate ?? .distantPast) > ($1.monthDate ?? .distantPast)
                }
            )
        }
        
        return yearGroups.sorted { $0.year > $1.year }
    }

    /// Explicitly requests user authorization to access photos
    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

        await MainActor.run {
            self.authorizationStatus = status
        }

        if status == .authorized || status == .limited {
            await loadAssets()
//            startObservingPhotoChanges() // Start observing only after we have permission
        }
    }

    // This method has been replaced by progressive loading in buildPhotoGroupsFromAssets() and organizeGroupsByYear()
    // Keeping this comment for reference during refactoring

    func fetchPhotoGroupsFromAlbums(albumNames: [String]) async -> [PhotoGroup] {
        var result: [PhotoGroup] = []

        for name in albumNames {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .any, options: nil)
            collections.enumerateObjects { collection, _, _ in
                if collection.localizedTitle == name {
                    let assets = PHAsset.fetchAssets(in: collection, options: nil)
                    var assetArray: [PHAsset] = []
                    assets.enumerateObjects { asset, _, _ in
                        assetArray.append(asset)
                    }
                    if !assetArray.isEmpty {
                        result.append(
                            PhotoGroup(
                                assets: assetArray, title: name,
                                monthDate: assetArray.first?.creationDate))
                    }
                }
            }
        }

        return result
    }

    func addAsset(_ asset: PHAsset, toAlbumNamed name: String) {
        isPerformingInternalChange = true // Set flag before operation
        fetchOrCreateAlbum(named: name) { collection in
            guard let collection = collection else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: collection)?.addAssets([asset] as NSArray)
            }
        }
    }

    func removeAsset(_ asset: PHAsset, fromAlbumNamed name: String) {
        isPerformingInternalChange = true // Set flag before operation
        fetchOrCreateAlbum(named: name) { collection in
            guard let collection = collection else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: collection)?.removeAssets([asset] as NSArray)
            }
        }
    }

    func fetchOrCreateAlbum(named title: String, completion: @escaping (PHAssetCollection?) -> Void)
    {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", title)
        let collection = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: fetchOptions)

        if let album = collection.firstObject {
            completion(album)
        } else {
            var placeholder: PHObjectPlaceholder?
            
            isPerformingInternalChange = true // Set flag before creating the album
            
            PHPhotoLibrary.shared().performChanges(
                {
                    placeholder =
                        PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                            withTitle: title
                        ).placeholderForCreatedAssetCollection
                },
                completionHandler: { success, error in
                    guard success, let placeholder = placeholder else {
                        completion(nil)
                        return
                    }
                    let newCollection = PHAssetCollection.fetchAssetCollections(
                        withLocalIdentifiers: [placeholder.localIdentifier], options: nil
                    ).firstObject
                    completion(newCollection)
                })
        }
    }

//    func removeAsset(_ asset: PHAsset, fromGroupWithDate monthDate: Date?) {
//        guard let monthDate else { return }
//        if let index = self.photoGroups.firstIndex(where: { $0.monthDate == monthDate }) {
//            let filteredAssets = self.photoGroups[index].assets.filter {
//                $0.localIdentifier != asset.localIdentifier
//            }
//            if filteredAssets.isEmpty {
//                self.photoGroups.remove(at: index)
//            } else {
//                self.photoGroups[index] = self.photoGroups[index].copy(withAssets: filteredAssets)
//            }
//        }
//    }

    func restoreToPhotoGroups(_ asset: PHAsset, inMonth: Date?) {
        guard let inMonth else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let title = formatter.string(from: inMonth)

        if let index = self.photoGroups.firstIndex(where: { $0.monthDate == inMonth }) {
            // Check if the asset already exists in the group
            if !self.photoGroups[index].assets.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
                // Only update if the asset is not already present
                let updated = [asset] + self.photoGroups[index].assets
                self.photoGroups[index] = self.photoGroups[index].copy(withAssets: updated)
            } 
            // If the asset is already there, we don't need to modify the group's assets.
            // We still need to proceed to unmark it and remove from the 'Deleted' album later.
        } else {
            // Asset's original month group doesn't exist (shouldn't normally happen if restoring)
            // Create a new group for it.
            self.photoGroups.insert(
                PhotoGroup(assets: [asset], title: title, monthDate: inMonth), at: 0)
        }

        removeAsset(asset, fromAlbumNamed: "Deleted")
    }

    func updateGroup(_ id: UUID, withAssets newAssets: [PHAsset]) {
        if let index = photoGroups.firstIndex(where: { $0.id == id }) {
            photoGroups[index] = photoGroups[index].copy(withAssets: newAssets)
        }
    }

    func bookmarkAsset(_ asset: PHAsset) {
        isPerformingInternalChange = true // Set flag before operation
        addAsset(asset, toAlbumNamed: "Maybe?")
        
        // Manually refresh photo groups to update the UI
        Task {
            await refreshAllPhotoGroups()
        }
    }

    /// Refreshes all photo groups
    @MainActor
    func refreshAllPhotoGroups() async {
        // Throttle reloads to prevent excessive refreshes
        let now = Date()
        if now.timeIntervalSince(lastReloadTime) < reloadThrottleInterval {
            return
        }
        lastReloadTime = now
        
        // Use the new progressive loading approach
        if let currentAssetsFetchResult = currentAssetsFetchResult {
            // Build photo groups from current assets
            let allPhotoGroups = await buildPhotoGroupsFromAssets(currentAssetsFetchResult, isQuickLoad: false)
            let systemAlbums = await fetchPhotoGroupsFromAlbums(albumNames: ["Deleted", "Maybe?"])
            
            // Update published properties on main thread
            await MainActor.run {
                self.photoGroups = allPhotoGroups + systemAlbums
                self.yearGroups = self.organizeGroupsByYear(self.photoGroups)
            }
        } else {
            // Fallback: reload assets if we don't have them
            await loadAssets()
        }
    }
    
    /// Pre-caches high-quality first images for all photo groups
    @MainActor
    func preCacheFirstImages() async {
        // Only cache if we have loaded some data
        guard hasLoadedInitialData else { return }
        
        // Get current photo groups (might be partial during progressive loading)
        let currentGroups = photoGroups
        
        // Prioritize groups with more recent view dates
        let sortedGroups = currentGroups.sorted { group1, group2 in
            // Get last viewed index as a proxy for recency
            let index1 = loadLastViewedIndex(for: group1.id)
            let index2 = loadLastViewedIndex(for: group2.id)
            
            // Groups with higher indices (more recently viewed) come first
            return index1 > index2
        }
        
        // Be more conservative - only cache first 5 groups to avoid memory pressure
        let groupsToCache = Array(sortedGroups.prefix(5))
        
        // Pre-cache first images with lower priority
        AlbumHighQualityCache.shared.cacheFirstImages(for: groupsToCache)
    }
    
    /// Fetches a high-quality album cover image for the given group
    /// Uses the AlbumHighQualityCache for faster loading
    func fetchAlbumCoverImage(for group: PhotoGroup, completion: @escaping (UIImage?) -> Void) {
        guard group.count > 0 else {
            completion(nil)
            return
        }
        
        // First, check if we have a high-quality cached version
        if let cachedImage = AlbumHighQualityCache.shared.getCachedFirstImage(for: group) {
            completion(cachedImage)
            return
        }

        let key = "LastViewedIndex_\(group.id.uuidString)"
        let savedIndex = UserDefaults.standard.integer(forKey: key)
        let safeIndex = min(savedIndex, group.count - 1)
        
        guard let asset = group.asset(at: safeIndex) else {
            completion(nil)
            return
        }

        // If we're requesting the first image, use the high-quality cache
        if safeIndex == 0 {
            AlbumHighQualityCache.shared.cacheFirstImage(for: group, completion: completion)
            return
        }
        
        // For non-first images, use the original implementation
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 600, height: 600),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    func updateLastViewedIndex(for groupID: UUID, index: Int) {
        if let idx = photoGroups.firstIndex(where: { $0.id == groupID }) {
            var group = photoGroups[idx]
            group.lastViewedIndex = index
            photoGroups[idx] = group

            saveLastViewedIndex(index, for: groupID)
        }
    }

    func saveLastViewedIndex(_ index: Int, for groupID: UUID) {
        UserDefaults.standard.set(index, forKey: "\(lastViewedIndexKey)_\(groupID.uuidString)")
    }

    func loadLastViewedIndex(for groupID: UUID) -> Int {
        UserDefaults.standard.integer(forKey: "\(lastViewedIndexKey)_\(groupID.uuidString)")
    }
    func markForDeletion(_ asset: PHAsset) {
        markedForDeletion.insert(asset.localIdentifier)
        
        // Save to persistent storage
        Task.detached(priority: .background) {
            self.saveMarkedForDeletion()
        }
    }

    /// Batch version of markForDeletion for efficiency when marking multiple assets
    func markMultipleForDeletion(_ assets: [PHAsset]) {
        Task { @MainActor in
            for asset in assets {
                markedForDeletion.insert(asset.localIdentifier)
            }
            
            // Save all changes at once
            Task.detached(priority: .background) {
                self.saveMarkedForDeletion()
            }
        }
    }

    func unmarkForDeletion(_ asset: PHAsset) {
        Task { @MainActor in
            self.markedForDeletion.remove(asset.localIdentifier)
            // Also remove from preview entries if exists
            self.deletedImagesPreview.removeAll { $0.asset.localIdentifier == asset.localIdentifier }
            
            // Save to persistent storage
            Task.detached(priority: .background) {
                self.saveMarkedForDeletion()
            }
        }
    }

    /// Batch version of unmarkForDeletion for efficiency when unmarking multiple assets
    func unmarkMultipleForDeletion(_ assets: [PHAsset]) {
        let identifiers = assets.map { $0.localIdentifier }
        
        Task { @MainActor in
            for identifier in identifiers {
                markedForDeletion.remove(identifier)
            }
            
            // Remove from preview entries
            deletedImagesPreview.removeAll { entry in
                identifiers.contains(entry.asset.localIdentifier)
            }
            
            // Save all changes at once
            Task.detached(priority: .background) {
                self.saveMarkedForDeletion()
            }
        }
    }

    func isMarkedForDeletion(_ asset: PHAsset) -> Bool {
        markedForDeletion.contains(asset.localIdentifier)
    }
    func markForFavourite(_ asset: PHAsset) {
        markedForBookmark.insert(asset.localIdentifier)
    }

    func unmarkForFavourite(_ asset: PHAsset) {
        markedForBookmark.remove(asset.localIdentifier)
    }

    func isMarkedForFavourite(_ asset: PHAsset) -> Bool {
        markedForBookmark.contains(asset.localIdentifier)
    }
    
    /// Marks an asset as "keep" - this simply indicates the user wants to keep the asset
    /// without any further actions required
    func keepAsset(_ asset: PHAsset) {
        // No specific action needed for keeping an asset
        // This method exists to provide a consistent API alongside markForDeletion and bookmarkAsset
    }

    func handleLeftSwipe(asset: PHAsset, monthDate: Date?) async {
        isPerformingInternalChange = true // Set flag before operation
        self.markForDeletion(asset)
        await self.refreshAllPhotoGroups()
    }
    
    /// Attempts to delete the specified assets from the Photos library.
    /// Returns true if deletion was successful, false if it failed or was canceled by the user.
    func hardDeleteAssets(_ assets: [PHAsset]) async -> Bool {
        guard !assets.isEmpty else { return false }

        // Set flag before deletion operation
        isPerformingInternalChange = true
        
        // Use withCheckedContinuation to wrap the completion handler in async/await
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                // Request to delete the assets
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }, completionHandler: { success, error in
                if success {
                    // Deletion was successful - proceed with updating app state
                    Task {
                        do {
                            await MainActor.run {
                                // Remove assets from markedForDeletion
                                for asset in assets {
                                    self.markedForDeletion.remove(asset.localIdentifier)
                                    
                                    // Also remove from preview entries if exists
                                    self.deletedImagesPreview.removeAll { 
                                        $0.asset.localIdentifier == asset.localIdentifier 
                                    }
                                }
                            }
                            
                            // Refresh photo groups to reflect changes
                            await self.refreshAllPhotoGroups()
                            
                            // Save changes to persistence
                            Task.detached(priority: .background) {
                                self.saveMarkedForDeletion()
                                self.saveDeletedPreviewIdentifiers()
                            }
                            
                            // Return success
                            continuation.resume(returning: true)
                        } catch {
                            print("❌ Error updating app state after deletion: \(error.localizedDescription)")
                            continuation.resume(returning: false)
                        }
                    }
                } else {
                    // Deletion failed or was canceled by user
                    if let error = error {
                        print("❌ Photo deletion failed: \(error.localizedDescription)")
                    } else {
                        print("❌ Photo deletion was canceled by user")
                    }
                    
                    // Don't modify app state - just return failure
                    continuation.resume(returning: false)
                }
            })
        }
    }

    // New method to add image to deleted preview
    func addToDeletedImagesPreview(asset: PHAsset, image: UIImage) {
        // Check if we already have this asset to prevent duplicates
        if !deletedImagesPreview.contains(where: { $0.asset.localIdentifier == asset.localIdentifier }) {
            let size = asset.estimatedAssetSize
            let newEntry = DeletePreviewEntry(asset: asset, image: image, fileSize: size)
            
            Task { @MainActor in
                self.deletedImagesPreview.append(newEntry)
                
                // Save the updated identifiers list
                Task.detached(priority: .background) {
                    self.saveDeletedPreviewIdentifiers()
                }
            }
        }
    }
    
    // Remove specific assets from preview
    func removeFromDeletedImagesPreview(assets: [PHAsset]) {
        let identifiers = assets.map { $0.localIdentifier }
        
        Task { @MainActor in
            self.deletedImagesPreview.removeAll { entry in
                identifiers.contains(entry.asset.localIdentifier)
            }
            
            // Save the updated identifiers list
            Task.detached(priority: .background) {
                self.saveDeletedPreviewIdentifiers()
            }
        }
    }
    
    // Clear all preview entries
    func clearDeletedImagesPreview() {
        Task { @MainActor in
            self.deletedImagesPreview.removeAll()
            
            // Save the updated (empty) identifiers list
            Task.detached(priority: .background) {
                self.saveDeletedPreviewIdentifiers()
            }
        }
    }

    // MARK: - Handling Invalid Assets
    
    /// Removes identifiers from the markedForDeletion set if they no longer exist in the photo library
    func removeInvalidDeletionIdentifiers(_ invalidIdentifiers: [String]) {
        Task { @MainActor in
            // Remove from markedForDeletion
            for identifier in invalidIdentifiers {
                markedForDeletion.remove(identifier)
            }
            
            // Remove from preview entries
            deletedImagesPreview.removeAll { entry in
                invalidIdentifiers.contains(entry.asset.localIdentifier)
            }
            
            // Save all changes to persistent storage
            Task.detached(priority: .background) {
                self.saveMarkedForDeletion()
                self.saveDeletedPreviewIdentifiers()
            }
            
            print("🧹 Removed \(invalidIdentifiers.count) invalid identifiers from deletion list")
        }
    }

}
