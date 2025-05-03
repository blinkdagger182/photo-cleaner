import Foundation
import Photos
import CoreLocation
import Vision
import Combine

/// Manages the clustering of photos into meaningful groups based on time and location
class PhotoClusteringManager: ObservableObject {
    // MARK: - Properties
    
    static let shared = PhotoClusteringManager()
    
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0.0
    
    private var photoManager: PhotoManager
    
    private let clusteringQueue = DispatchQueue(label: "com.photocleaner.clustering", qos: .userInitiated)
    
    private var clusteringTask: Task<Void, Error>?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Clustering Configuration
    
    /// Maximum time difference (in seconds) between photos to be considered part of the same event
    private let maxTimeDifference: TimeInterval = 2 * 60 * 60 // 2 hours
    
    /// Maximum distance (in meters) between photos to be considered part of the same event
    private let maxDistanceDifference: CLLocationDistance = 300 // 300 meters
    
    /// Minimum number of photos required to form a cluster
    private let minPhotosPerCluster: Int = 5
    
    /// Minimum duration (in seconds) between first and last photo in a cluster
    private let minClusterDuration: TimeInterval = 30 * 60 // 30 minutes
    
    // MARK: - Initialization
    
    private init() {
        // Private initializer to enforce singleton pattern
        self.photoManager = PhotoManager()
    }
    
    /// Initialize with a specific PhotoManager instance
    func configure(with photoManager: PhotoManager) {
        self.photoManager = photoManager
    }
    
    // MARK: - Public Methods
    
    /// Process the entire photo library and generate clusters
    /// - Parameter completion: Called when processing is complete with the generated photo groups
    func processEntireLibrary(completion: @escaping ([PhotoGroup]) -> Void) {
        guard !isProcessing else {
            print("⚠️ Already processing photo library")
            return
        }
        
        isProcessing = true
        progress = 0.0
        
        // Cancel any existing task
        clusteringTask?.cancel()
        
        // Create a new task for processing
        clusteringTask = Task {
            do {
                // 1. Fetch all assets from the photo library
                let allAssets = try await fetchAllAssets()
                
                // 2. Extract metadata for all assets
                let assetMetadata = try await extractMetadata(from: allAssets)
                
                // 3. Cluster assets into events
                let eventClusters = try await clusterIntoEvents(metadata: assetMetadata)
                
                // 4. Create PhotoGroup objects from clusters
                let photoGroups = try await createPhotoGroups(from: eventClusters, allAssets: allAssets)
                
                // 5. Create utility albums (only screenshots)
                let utilityGroups = try await createUtilityAlbums(from: allAssets)
                
                // 6. System albums are now empty
                
                // 7. Combine all groups (events and screenshots only)
                let allGroups = photoGroups + utilityGroups
                
                // Complete processing
                await MainActor.run {
                    self.isProcessing = false
                    self.progress = 1.0
                    completion(allGroups)
                }
            } catch {
                print("❌ Error processing photo library: \(error)")
                await MainActor.run {
                    self.isProcessing = false
                    self.progress = 0.0
                    completion([])
                }
            }
        }
    }
    
    /// Cancel the current processing task
    func cancelProcessing() {
        clusteringTask?.cancel()
        isProcessing = false
        progress = 0.0
    }
    
    // MARK: - Private Methods - Asset Fetching
    
    /// Fetch all assets from the photo library in a memory-efficient way
    /// - Returns: Array of PHAssets
    private func fetchAllAssets() async throws -> [PHAsset] {
        return await withCheckedContinuation { continuation in
            clusteringQueue.async {
                // Create fetch options
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                
                // Fetch all assets
                let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
                
                // Convert fetch result to array
                var assets: [PHAsset] = []
                assets.reserveCapacity(fetchResult.count)
                
                // Process in batches to avoid memory issues
                let batchSize = 500
                let totalBatches = (fetchResult.count + batchSize - 1) / batchSize
                
                for batchIndex in 0..<totalBatches {
                    let startIndex = batchIndex * batchSize
                    let endIndex = min(startIndex + batchSize, fetchResult.count)
                    
                    // Process this batch
                    for i in startIndex..<endIndex {
                        autoreleasepool {
                            if let asset = fetchResult.object(at: i) as? PHAsset {
                                assets.append(asset)
                            }
                        }
                    }
                    
                    // Update progress
                    Task { @MainActor in
                        self.progress = Double(endIndex) / Double(fetchResult.count) * 0.3 // 30% of total progress
                    }
                }
                
                continuation.resume(returning: assets)
            }
        }
    }
    
    // MARK: - Private Methods - Metadata Extraction
    
    /// Asset metadata used for clustering
    struct AssetMetadata {
        let asset: PHAsset
        let creationDate: Date?
        let location: CLLocation?
        let mediaType: PHAssetMediaType
        let isUtility: Bool
        let utilityType: UtilityType?
        
        enum UtilityType: String {
            case receipt
            case document
            case screenshot
            case whiteboard
            case qrCode
            case unknown
        }
    }
    
    /// Extract metadata from assets
    /// - Parameter assets: Array of PHAssets
    /// - Returns: Array of AssetMetadata
    private func extractMetadata(from assets: [PHAsset]) async throws -> [AssetMetadata] {
        return await withCheckedContinuation { continuation in
            clusteringQueue.async {
                var metadata: [AssetMetadata] = []
                metadata.reserveCapacity(assets.count)
                
                // Process in batches
                let batchSize = 500
                let totalBatches = (assets.count + batchSize - 1) / batchSize
                
                for batchIndex in 0..<totalBatches {
                    let startIndex = batchIndex * batchSize
                    let endIndex = min(startIndex + batchSize, assets.count)
                    
                    // Process this batch
                    for i in startIndex..<endIndex {
                        autoreleasepool {
                            let asset = assets[i]
                            
                            // Determine if this is a utility image
                            let isUtility = self.isUtilityAsset(asset)
                            let utilityType = self.determineUtilityType(asset)
                            
                            let assetMetadata = AssetMetadata(
                                asset: asset,
                                creationDate: asset.creationDate,
                                location: asset.location,
                                mediaType: asset.mediaType,
                                isUtility: isUtility,
                                utilityType: utilityType
                            )
                            
                            metadata.append(assetMetadata)
                        }
                    }
                    
                    // Update progress
                    Task { @MainActor in
                        let baseProgress = 0.3 // Starting after asset fetching
                        let batchProgress = Double(endIndex - startIndex) / Double(assets.count) * 0.3 // 30% of total progress
                        self.progress = baseProgress + batchProgress
                    }
                }
                
                continuation.resume(returning: metadata)
            }
        }
    }
    
    /// Check if an asset is a utility image (screenshot, document, etc.)
    /// - Parameter asset: The PHAsset to check
    /// - Returns: True if the asset is a utility image
    private func isUtilityAsset(_ asset: PHAsset) -> Bool {
        // Check for screenshots using PHAssetMediaSubtype
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return true
        }
        
        // Check for other utility types
        if determineUtilityType(asset) != nil {
            return true
        }
        
        return false
    }
    
    /// Determine the utility type of an asset
    /// - Parameter asset: The PHAsset to check
    /// - Returns: The utility type, or nil if not a utility
    private func determineUtilityType(_ asset: PHAsset) -> AssetMetadata.UtilityType? {
        // Check for screenshots using PHAssetMediaSubtype
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return .screenshot
        }
        
        // Check for other utility types based on available metadata
        // This is a placeholder - in a real implementation, we would use Vision framework
        // or other iOS built-in classifications
        
        // For now, we'll use a simple heuristic based on the asset's filename
        let filename = asset.value(forKey: "filename") as? String ?? ""
        
        if filename.lowercased().contains("receipt") || filename.lowercased().contains("invoice") {
            return .receipt
        } else if filename.lowercased().contains("document") || filename.lowercased().contains("doc") {
            return .document
        } else if filename.lowercased().contains("whiteboard") || filename.lowercased().contains("board") {
            return .whiteboard
        } else if filename.lowercased().contains("qr") || filename.lowercased().contains("code") {
            return .qrCode
        }
        
        return nil
    }
    
    // MARK: - Private Methods - Clustering
    
    /// Cluster metadata into events based on time and location
    /// - Parameter metadata: Array of AssetMetadata
    /// - Returns: Array of clusters, where each cluster is an array of AssetMetadata
    private func clusterIntoEvents(metadata: [AssetMetadata]) async throws -> [[AssetMetadata]] {
        return await withCheckedContinuation { continuation in
            clusteringQueue.async {
                // Filter out metadata without creation dates
                let validMetadata = metadata.filter { $0.creationDate != nil && !$0.isUtility }
                
                // Sort by creation date
                let sortedMetadata = validMetadata.sorted { 
                    ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast) 
                }
                
                var clusters: [[AssetMetadata]] = []
                var currentCluster: [AssetMetadata] = []
                
                // Process each metadata item
                for (index, item) in sortedMetadata.enumerated() {
                    // Update progress
                    if index % 500 == 0 {
                        let baseProgress = 0.6 // Starting after metadata extraction
                        let clusteringProgress = Double(index) / Double(sortedMetadata.count) * 0.2 // 20% of total progress
                        Task { @MainActor in
                            self.progress = baseProgress + clusteringProgress
                        }
                    }
                    
                    // If this is the first item, add it to the current cluster
                    if currentCluster.isEmpty {
                        currentCluster.append(item)
                        continue
                    }
                    
                    // Get the last item in the current cluster
                    guard let lastItem = currentCluster.last,
                          let lastDate = lastItem.creationDate,
                          let currentDate = item.creationDate else {
                        continue
                    }
                    
                    // Calculate time difference
                    let timeDifference = currentDate.timeIntervalSince(lastDate)
                    
                    // Calculate location difference if both items have locations
                    var locationDifference: CLLocationDistance = .infinity
                    if let lastLocation = lastItem.location?.coordinate,
                       let currentLocation = item.location?.coordinate {
                        let lastCLLocation = CLLocation(latitude: lastLocation.latitude, longitude: lastLocation.longitude)
                        let currentCLLocation = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
                        locationDifference = lastCLLocation.distance(from: currentCLLocation)
                    }
                    
                    // Check if the current item belongs to the current cluster
                    let isTimeDifferenceAcceptable = timeDifference <= self.maxTimeDifference
                    let isLocationDifferenceAcceptable = locationDifference <= self.maxDistanceDifference
                    
                    // If either time or location difference is too large, start a new cluster
                    if !isTimeDifferenceAcceptable || (!isLocationDifferenceAcceptable && locationDifference != .infinity) {
                        // Check if the current cluster meets the minimum requirements
                        if self.isValidCluster(currentCluster) {
                            clusters.append(currentCluster)
                        }
                        
                        // Start a new cluster
                        currentCluster = [item]
                    } else {
                        // Add to the current cluster
                        currentCluster.append(item)
                    }
                }
                
                // Add the last cluster if it meets the minimum requirements
                if self.isValidCluster(currentCluster) {
                    clusters.append(currentCluster)
                }
                
                continuation.resume(returning: clusters)
            }
        }
    }
    
    /// Check if a cluster meets the minimum requirements
    /// - Parameter cluster: Array of AssetMetadata
    /// - Returns: True if the cluster is valid
    private func isValidCluster(_ cluster: [AssetMetadata]) -> Bool {
        // Check minimum number of photos
        guard cluster.count >= minPhotosPerCluster else {
            return false
        }
        
        // Check minimum duration
        guard let firstDate = cluster.first?.creationDate,
              let lastDate = cluster.last?.creationDate else {
            return false
        }
        
        let duration = lastDate.timeIntervalSince(firstDate)
        return duration >= minClusterDuration
    }
    
    // MARK: - Private Methods - PhotoGroup Creation
    
    /// Create PhotoGroup objects from clusters
    /// - Parameters:
    ///   - clusters: Array of clusters, where each cluster is an array of AssetMetadata
    ///   - allAssets: Array of all PHAssets
    /// - Returns: Array of PhotoGroup objects
    private func createPhotoGroups(from clusters: [[AssetMetadata]], allAssets: [PHAsset]) async throws -> [PhotoGroup] {
        return await withCheckedContinuation { continuation in
            clusteringQueue.async {
                var photoGroups: [PhotoGroup] = []
                
                // Process each cluster
                for (index, cluster) in clusters.enumerated() {
                    // Update progress
                    let baseProgress = 0.8 // Starting after clustering
                    let groupProgress = Double(index) / Double(clusters.count) * 0.1 // 10% of total progress
                    Task { @MainActor in
                        self.progress = baseProgress + groupProgress
                    }
                    
                    // Extract assets from the cluster
                    let assets = cluster.map { $0.asset }
                    
                    // Generate a title for the cluster
                    let title = self.generateTitle(for: cluster)
                    
                    // Create a PhotoGroup
                    let photoGroup = PhotoGroup(
                        assets: assets,
                        title: title,
                        monthDate: cluster.first?.creationDate,
                        lastViewedIndex: 0
                    )
                    
                    photoGroups.append(photoGroup)
                }
                
                continuation.resume(returning: photoGroups)
            }
        }
    }
    
    /// Generate a title for a cluster
    /// - Parameter cluster: Array of AssetMetadata
    /// - Returns: A descriptive title for the cluster
    private func generateTitle(for cluster: [AssetMetadata]) -> String {
        guard let firstDate = cluster.first?.creationDate else {
            return "Photo Collection"
        }
        
        // Format the date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: firstDate)
        
        // Get the time of day
        let hour = Calendar.current.component(.hour, from: firstDate)
        let timeOfDay: String
        switch hour {
        case 5..<12:
            timeOfDay = "Morning"
        case 12..<17:
            timeOfDay = "Afternoon"
        case 17..<22:
            timeOfDay = "Evening"
        default:
            timeOfDay = "Night"
        }
        
        // Get the location if available
        if let location = cluster.first?.location {
            // In a real app, we would use reverse geocoding to get the location name
            // For now, we'll use the coordinates
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            
            // This is a placeholder - in a real implementation, we would use CLGeocoder
            // to get the actual location name
            return "\(timeOfDay) at \(dateString)"
        }
        
        return "\(timeOfDay) on \(dateString)"
    }
    
    // MARK: - Private Methods - Utility Albums
    
    /// Create utility albums from assets
    /// - Parameter assets: Array of PHAssets
    /// - Returns: Array of PhotoGroup objects for utility albums
    private func createUtilityAlbums(from assets: [PHAsset]) async throws -> [PhotoGroup] {
        return await withCheckedContinuation { continuation in
            clusteringQueue.async {
                var utilityGroups: [PhotoGroup] = []
                
                // Only collect screenshot assets
                var screenshotAssets: [PHAsset] = []
                
                // Process each asset
                for asset in assets {
                    // Check for screenshots using PHAssetMediaSubtype
                    if asset.mediaSubtypes.contains(.photoScreenshot) {
                        screenshotAssets.append(asset)
                    }
                }
                
                // Create Screenshots album only if we have screenshots
                if !screenshotAssets.isEmpty {
                    let screenshotGroup = PhotoGroup(
                        assets: screenshotAssets,
                        title: "Screenshots",
                        monthDate: nil,
                        lastViewedIndex: 0
                    )
                    utilityGroups.append(screenshotGroup)
                }
                
                continuation.resume(returning: utilityGroups)
            }
        }
    }
    
    // MARK: - Private Methods - System Albums
    
    /// Create system albums (Deleted, Saved)
    /// - Returns: Array of PhotoGroup objects for system albums
    private func createSystemAlbums() async throws -> [PhotoGroup] {
        // Return an empty array since we don't want to show system albums
        return []
    }
}
