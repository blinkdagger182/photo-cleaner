import Foundation
import Photos
import CoreData
import Combine
import CoreLocation
import UIKit

// Error types for batch processing
enum BatchProcessingError: Error {
    case cancelled
    case memoryPressure
    case processingFailed
}

/// Manager for batch processing large photo libraries
class BatchProcessingManager {
    // Singleton instance
    static let shared = BatchProcessingManager()
    
    // Reference to SmartAlbumManager
    private let smartAlbumManager = SmartAlbumManager.shared
    
    // Reference to persistence controller
    private let persistence = PersistenceController.shared
    
    // Batch size for processing - adaptive based on device memory
    private var batchSize: Int {
        // Use smaller batch sizes on devices with less memory
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        if totalMemory < 2_000_000_000 { // Less than 2GB
            return 200
        } else if totalMemory < 4_000_000_000 { // Less than 4GB
            return 500
        } else {
            return 1000
        }
    }
    
    // Processing state
    private(set) var isProcessing = false
    private var processingProgress: Float = 0
    private var isCancelled = false
    private var currentBatch = 0
    private var totalBatches = 0
    private var currentProgress: Double = 0.0
    
    // Publishers
    let progressPublisher = PassthroughSubject<Float, Never>()
    let completionPublisher = PassthroughSubject<Void, Error>()
    
    // New publishers with Double precision
    let progressSubject = PassthroughSubject<Double, Never>()
    let completionSubject = PassthroughSubject<Void, Error>()
    
    // Background processing queue
    private let processingQueue = DispatchQueue(label: "com.photocleaner.batchProcessing", qos: .utility)
    
    // Memory usage monitoring
    private var memoryUsageTimer: Timer?
    private let memoryThreshold: Double = 0.7 // 70% of available memory
    
    private init() {
        // Start memory monitoring when processing
        setupMemoryMonitoring()
    }
    
    /// Setup memory monitoring to pause processing if memory usage gets too high
    private func setupMemoryMonitoring() {
        // Subscribe to memory warning notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        memoryUsageTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isProcessing else { return }
            
            if self.isUnderMemoryPressure() {
                // Temporarily pause processing and clear caches
                self.pauseProcessingForMemoryRelief()
            }
        }
    }
    
    @objc private func didReceiveMemoryWarning() {
        // Immediately pause processing and clear caches
        pauseProcessingForMemoryRelief()
    }
    
    /// Get current memory usage
    /// Check if the app is under memory pressure
    func isUnderMemoryPressure() -> Bool {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size) / Double(ProcessInfo.processInfo.physicalMemory)
            return usedMemory > memoryThreshold
        } else {
            return false
        }
    }
    
    /// Pause processing temporarily to relieve memory pressure
    private func pauseProcessingForMemoryRelief() {
        // Pause for 2 seconds to let memory be released
        processingQueue.suspend()
        
        // Clear caches
        OptimizedPhotoCache.shared.clearCache()
        
        // Resume after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.processingQueue.resume()
        }
    }
    
    /// Process photos in batches to avoid memory issues
    /// - Parameters:
    ///   - assets: All assets to process
    ///   - completion: Called when processing is complete
    func processPhotosInBatches(assets: [PHAsset], completion: @escaping () -> Void) {
        // Reset state
        isCancelled = false
        currentBatch = 0
        totalBatches = max(1, Int(ceil(Double(assets.count) / Double(batchSize))))
        
        // Update progress
        currentProgress = 0.0
        progressSubject.send(0.0)
        
        // Create a background queue for processing
        let processingQueue = DispatchQueue(label: "com.photocleaner.batchProcessing", qos: .userInitiated)
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Process in smaller chunks to avoid memory pressure
            var processedCount = 0
            let totalCount = assets.count
            
            while processedCount < totalCount && !self.isCancelled {
                // Determine batch size based on current memory conditions
                let adaptiveBatchSize = self.isUnderMemoryPressure() ? self.batchSize / 2 : self.batchSize
                let endIndex = min(processedCount + adaptiveBatchSize, totalCount)
                
                // Create current batch
                let currentBatchAssets = Array(assets[processedCount..<endIndex])
                
                // Update batch index
                self.currentBatch += 1
                
                // Process this batch
                autoreleasepool {
                    // Create a temporary context for this batch
                    let context = self.persistence.container.newBackgroundContext()
                    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                    
                    // Process batch with this context
                    self.processBatch(currentBatchAssets, in: context)
                    
                    // Save context changes
                    do {
                        try context.save()
                    } catch {
                        print("Error saving batch context: \(error)")
                    }
                }
                
                // Update progress
                processedCount = endIndex
                self.currentProgress = Double(processedCount) / Double(totalCount)
                self.progressSubject.send(self.currentProgress)
                
                // Check memory pressure
                if self.isUnderMemoryPressure() {
                    // Pause briefly to allow memory to be released
                    Thread.sleep(forTimeInterval: 2.0)
                    
                    // Force a memory cleanup
                    autoreleasepool { () -> Void in
                        // This empty autorelease pool helps release memory
                    }
                }
                
                // Check if processing was cancelled
                if self.isCancelled {
                    self.completionSubject.send(completion: .failure(BatchProcessingError.cancelled))
                    return
                }
            }
            
            // Notify completion
            self.completionSubject.send(())
            self.completionSubject.send(completion: .finished)
            
            // Call completion handler on main thread
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    /// Process a single batch of assets
    /// - Parameters:
    ///   - assets: Assets in this batch
    ///   - context: CoreData context to use
    private func processBatch(_ assets: [PHAsset], in context: NSManagedObjectContext) {
        // Implement our own clustering logic similar to SmartAlbumManager's
        let clusters = clusterAssetsByTimeAndLocation(assets)
        
        // Process each cluster and save to CoreData
        context.performAndWait {
            for cluster in clusters {
                // Skip clusters that are too small
                guard cluster.count >= 3 else { continue }
                
                // Create a smart album for this cluster
                let album = SmartAlbumGroup(context: context)
                album.id = UUID()
                album.createdAt = Date()
                album.title = "Batch Processed Album" // Temporary title
                album.relevanceScore = 50 // Default score
                
                // Store asset identifiers
                let assetIds = cluster.map { $0.localIdentifier }
                do {
                    let assetIdsData = try JSONEncoder().encode(assetIds)
                    album.assetIdsData = assetIdsData
                } catch {
                    print("❌ Failed to encode asset IDs: \(error)")
                    continue
                }
                
                // Extract tags (simplified for batch processing)
                let tags = extractTagsFromAssets(cluster)
                do {
                    let tagsData = try JSONEncoder().encode(tags)
                    album.tagsData = tagsData
                } catch {
                    print("❌ Failed to encode tags: \(error)")
                }
                
                // Calculate score based on recency and relevance
                let score = calculateRecencyScore(for: album)
                album.relevanceScore = Int32(score)
            }
            
            // Save batch changes
            do {
                try context.save()
            } catch {
                print("❌ Failed to save batch: \(error)")
            }
        }
    }
    
    /// Cluster assets by time and location (similar to SmartAlbumManager's implementation)
    /// - Parameter assets: Assets to cluster
    /// - Returns: Array of asset clusters
    private func clusterAssetsByTimeAndLocation(_ assets: [PHAsset]) -> [[PHAsset]] {
        // Sort assets by creation date
        let sortedAssets = assets.sorted { 
            ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast) 
        }
        
        // Early return for empty or single asset
        if sortedAssets.count <= 1 {
            return sortedAssets.isEmpty ? [] : [sortedAssets]
        }
        
        var clusters: [[PHAsset]] = []
        var currentCluster: [PHAsset] = [sortedAssets[0]]
        var currentClusterLocation: CLLocation? = sortedAssets[0].location
        
        // Time window in seconds (12 hours)
        let timeWindow = 12 * 3600
        
        // Location proximity threshold in meters (1 km)
        let proximityThreshold = 1000.0
        
        // Process remaining assets
        for i in 1..<sortedAssets.count {
            let asset = sortedAssets[i]
            let previousAsset = sortedAssets[i-1]
            
            // Check time proximity
            let timeDifference = asset.creationDate?.timeIntervalSince(previousAsset.creationDate ?? Date.distantPast) ?? Double(timeWindow) + 1.0
            
            // Check location proximity if both assets have location
            var locationProximity = true
            if let assetLocation = asset.location, let clusterLocation = currentClusterLocation {
                let distance = assetLocation.distance(from: clusterLocation)
                locationProximity = distance <= proximityThreshold
            }
            
            // If within time window and location proximity, add to current cluster
            if timeDifference <= Double(timeWindow) && locationProximity {
                currentCluster.append(asset)
                
                // Update cluster location to the average if this asset has location
                if let assetLocation = asset.location {
                    // If current cluster doesn't have a location yet, use this one
                    if currentClusterLocation == nil {
                        currentClusterLocation = assetLocation
                    }
                }
            } else {
                // Start a new cluster
                if currentCluster.count >= 3 {
                    clusters.append(currentCluster)
                }
                
                currentCluster = [asset]
                currentClusterLocation = asset.location
            }
        }
        
        // Add the last cluster if it meets the minimum size
        if currentCluster.count >= 3 {
            clusters.append(currentCluster)
        }
        
        return clusters
    }
    
    /// Extract tags from assets (simplified version of SmartAlbumManager's method)
    /// - Parameter assets: Assets to extract tags from
    /// - Returns: Array of tags
    private func extractTagsFromAssets(_ assets: [PHAsset]) -> [String] {
        // For batch processing, we'll use a simplified approach
        // In a real implementation, you'd want to use ML to analyze the images
        
        var tags: Set<String> = []
        
        // Add some basic tags based on time
        if let firstAsset = assets.first, let creationDate = firstAsset.creationDate {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: creationDate)
            
            // Add time of day tag
            if hour >= 5 && hour < 12 {
                tags.insert("morning")
            } else if hour >= 12 && hour < 17 {
                tags.insert("afternoon")
            } else if hour >= 17 && hour < 21 {
                tags.insert("evening")
            } else {
                tags.insert("night")
            }
            
            // Add day of week tag
            let weekday = calendar.component(.weekday, from: creationDate)
            let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            if weekday >= 1 && weekday <= 7 {
                tags.insert(weekdayNames[weekday - 1])
            }
            
            // Add weekend/weekday tag
            if weekday == 1 || weekday == 7 {
                tags.insert("weekend")
            } else {
                tags.insert("weekday")
            }
        }
        
        // Add location-based tag if available
        if let firstAsset = assets.first, let location = firstAsset.location {
            // Check if location is near water (very simplified)
            if location.altitude < 10 {
                tags.insert("waterfront")
            }
            
            // Check if location is in a city (very simplified)
            if location.horizontalAccuracy < 100 {
                tags.insert("urban")
            } else {
                tags.insert("rural")
            }
        }
        
        return Array(tags)
    }
    
    /// Calculate a recency-weighted score for an album
    /// - Parameter album: The album to score
    /// - Returns: A score between 0 and 100
    private func calculateRecencyScore(for album: SmartAlbumGroup) -> Double {
        // Base score
        var score: Double = 50
        
        // Recency component (40% of score)
        let now = Date()
        let creationDate = album.createdAt
        let daysSinceCreation = Calendar.current.dateComponents([.day], from: creationDate, to: now).day ?? 0
        
        // Decay function: score decreases as album gets older (1 year = 365 days)
        let recencyScore = max(0, 40.0 * (1.0 - Double(daysSinceCreation) / 365.0))
        
        // Add recency component to base score
        score += recencyScore
        
        // Size component (10% of score)
        if let assetIdsData = album.assetIdsData, 
           let assetIds = try? JSONDecoder().decode([String].self, from: assetIdsData) {
            // More photos = higher score, up to 10 points
            let sizeScore = min(10.0, Double(assetIds.count) / 2.0)
            score += sizeScore
        }
        
        return min(100, max(0, score))
    }
    
    /// Cancel ongoing batch processing
    func cancelProcessing() {
        isProcessing = false
        isCancelled = true
    }
    
    /// Memory management - release any resources when finished
    func cleanUp() {
        // Clear any caches or temporary data
        memoryUsageTimer?.invalidate()
        memoryUsageTimer = nil
    }
}
