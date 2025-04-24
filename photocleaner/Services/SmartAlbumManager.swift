import Foundation
import Photos
import UIKit
import CoreData
import CoreLocation

// MARK: - SmartAlbumManager
class SmartAlbumManager: ObservableObject {
    // Singleton instance
    static let shared = SmartAlbumManager()
    
    // Services
    private let imageClassifier = ImageClassificationService.shared
    private let persistence = PersistenceController.shared
    
    // Published properties
    @Published var allSmartAlbums: [SmartAlbumGroup] = []
    @Published var featuredAlbums: [SmartAlbumGroup] = []
    @Published var isGenerating = false
    
    // Time clustering parameters
    private let clusterTimeWindowHours: Double = 3.0
    private let minimumPhotosForAlbum: Int = 3
    private let maximumSamplesPerAlbum: Int = 3
    
    // Tags mapping for better titles and emojis
    private let tagEmojis: [String: String] = [
        "beach": "🏖️",
        "mountain": "🏔️",
        "sunset": "🌅",
        "food": "🍽️",
        "pizza": "🍕",
        "dog": "🐕",
        "cat": "🐱",
        "car": "🚗",
        "flower": "🌸",
        "birthday": "🎂",
        "party": "🎉",
        "concert": "🎵",
        "coffee": "☕",
        "snow": "❄️",
        "city": "🏙️"
    ]
    
    private init() {
        // Load albums on initialization
        loadSmartAlbums()
    }
    
    // MARK: - Public Methods
    
    /// Generate smart albums from photos with limit option
    func generateSmartAlbums(from assets: [PHAsset], limit: Int = 0, completion: @escaping () -> Void) {
        guard !isGenerating else {
            print("⚠️ Album generation already in progress")
            completion()
            return
        }
        
        // Check if we actually have photos to process
        if assets.isEmpty {
            print("⚠️ No assets provided for smart album generation")
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        // Set isGenerating on main thread
        DispatchQueue.main.async {
            self.isGenerating = true
        }
        
        print("📸 Starting smart album generation with \(assets.count) photos")
        
        // Check ML model availability once
        let mlModelAvailable = imageClassifier.isModelAvailable()
        if !mlModelAvailable {
            print("⚠️ ML model not available - smart albums will use basic classification")
        } else {
            print("✅ ML model is available - smart albums will use advanced classification")
        }
        
        // Create a persistent viewContext for saving albums
        let viewContext = persistence.container.viewContext
        var savedAlbumCount = 0
        
        // Use a background thread for processing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return completion() }
            
            // 1. Cluster photos by time proximity
            let clusters = self.clusterPhotosByTime(assets)
            print("📸 Created \(clusters.count) time-based clusters")
            
            // Apply limit if requested
            let clustersToProcess: [Int]
            if limit > 0 && limit < clusters.count {
                // Process only the first 'limit' clusters that meet the minimum size requirement
                var validClusters: [Int] = []
                for (index, cluster) in clusters.enumerated() {
                    if cluster.count >= self.minimumPhotosForAlbum {
                        validClusters.append(index)
                        if validClusters.count >= limit {
                            break
                        }
                    }
                }
                clustersToProcess = validClusters
                print("📸 Processing limited set of \(clustersToProcess.count) clusters (out of \(clusters.count) total)")
            } else {
                // Process all clusters
                clustersToProcess = Array(0..<clusters.count)
            }
            
            // Track skipped clusters
            var skippedClusters = 0
            
            // Batch processing to avoid memory issues
            let batchSize = 10
            
            // Try once more to load ML model if it wasn't available initially
            let finalMlModelAvailable: Bool
            if !mlModelAvailable {
                print("📱 Retrying ML model loading before classification...")
                finalMlModelAvailable = self.imageClassifier.isModelAvailable()
                if finalMlModelAvailable {
                    print("✅ Successfully loaded ML model on retry")
                } else {
                    print("⚠️ ML model still not available after retry")
                }
            } else {
                finalMlModelAvailable = true
            }
            
            // Split clusters into batches
            let batches = stride(from: 0, to: clustersToProcess.count, by: batchSize).map {
                let end = min($0 + batchSize, clustersToProcess.count)
                return Array(clustersToProcess[$0..<end])
            }
            
            // Process each batch 
            for (batchIndex, batchClusterIndices) in batches.enumerated() {
                print("📸 Processing batch \(batchIndex+1)/\(batches.count)")
                
                // Create batch data to save
                var batchAlbumData: [(
                    title: String,
                    date: Date,
                    score: Int32,
                    thumbnail: String,
                    tags: [String],
                    assetIds: [String]
                )] = []
                
                // Process each cluster in this batch
                for clusterIndex in batchClusterIndices {
                    let cluster = clusters[clusterIndex]
                    
                    // Skip small clusters (already filtered in limit case)
                    if cluster.count < self.minimumPhotosForAlbum {
                        skippedClusters += 1
                        continue
                    }
                    
                    // Process this cluster
                    let group = DispatchGroup()
                    var albumData: (
                        title: String,
                        date: Date,
                        score: Int32,
                        thumbnail: String,
                        tags: [String],
                        assetIds: [String]
                    )?
                    
                    group.enter()
                    self.processClusterForData(cluster, index: clusterIndex, useFallbackMode: !finalMlModelAvailable) { data in
                        albumData = data
                        group.leave()
                    }
                    
                    // Wait for cluster processing to complete
                    group.wait()
                    
                    // Add to batch if valid
                    if let data = albumData {
                        batchAlbumData.append(data)
                    }
                }
                
                // Save this batch on the main thread
                if !batchAlbumData.isEmpty {
                    DispatchQueue.main.sync {
                        for data in batchAlbumData {
                            // Create the album in the main context
                            let album = SmartAlbumGroup(context: viewContext)
                            album.id = UUID()
                            album.title = data.title
                            album.createdAt = data.date
                            album.relevanceScore = data.score
                            album.thumbnailId = data.thumbnail
                            
                            // Set the arrays
                            album.tags = data.tags
                            album.assetIds = data.assetIds
                        }
                        
                        // Save the batch
                        do {
                            try viewContext.save()
                            savedAlbumCount += batchAlbumData.count
                            print("✅ Saved batch \(batchIndex+1) with \(batchAlbumData.count) albums (total: \(savedAlbumCount))")
                        } catch {
                            print("❌ Failed to save batch: \(error.localizedDescription)")
                            viewContext.rollback()
                        }
                    }
                }
            }
            
            // Final update on the main thread
            DispatchQueue.main.async {
                print("✅ Generated \(savedAlbumCount) smart albums (skipped \(skippedClusters) small clusters)")
                self.loadSmartAlbums()
                self.isGenerating = false
                completion()
            }
        }
    }
    
    /// Reload smart albums from CoreData
    func loadSmartAlbums() {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<SmartAlbumGroup> = SmartAlbumGroup.fetchRequest()
        
        // Sort by relevance score (descending)
        let sortDescriptor = NSSortDescriptor(keyPath: \SmartAlbumGroup.relevanceScore, ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        do {
            let albums = try context.fetch(fetchRequest)
            
            // IMPORTANT: Update published properties on the main thread
            DispatchQueue.main.async {
                self.allSmartAlbums = albums
                
                // Set featured albums (top 5 by score)
                self.featuredAlbums = Array(albums.prefix(5))
                
                print("📸 Loaded \(albums.count) smart albums")
            }
        } catch {
            print("❌ Failed to fetch smart albums: \(error)")
        }
    }
    
    /// Delete a smart album
    func deleteAlbum(_ album: SmartAlbumGroup) {
        let context = persistence.container.viewContext
        context.delete(album)
        
        do {
            try context.save()
            loadSmartAlbums()
        } catch {
            print("❌ Failed to delete album: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    /// Cluster photos by time proximity
    private func clusterPhotosByTime(_ assets: [PHAsset]) -> [[PHAsset]] {
        // Sort assets by creation date
        let sortedAssets = assets.sorted { 
            ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast) 
        }
        
        var clusters: [[PHAsset]] = []
        var currentCluster: [PHAsset] = []
        var lastDate: Date?
        
        // Group assets based on time proximity
        for asset in sortedAssets {
            guard let creationDate = asset.creationDate else { continue }
            
            if let lastDate = lastDate, 
               creationDate.timeIntervalSince(lastDate) <= (clusterTimeWindowHours * 3600) {
                // Add to current cluster if within time window
                currentCluster.append(asset)
            } else {
                // Start a new cluster
                if !currentCluster.isEmpty {
                    clusters.append(currentCluster)
                }
                currentCluster = [asset]
            }
            
            lastDate = creationDate
        }
        
        // Add the last cluster if not empty
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }
        
        return clusters
    }
    
    /// Process a cluster of photos and return data needed to create an album
    private func processClusterForData(_ assets: [PHAsset], index: Int, useFallbackMode: Bool, completion: @escaping ((title: String, date: Date, score: Int32, thumbnail: String, tags: [String], assetIds: [String])?) -> Void) {
        // Select representative assets to analyze
        let sampleAssets = selectSampleAssets(from: assets)
        
        // If we're in fallback mode, skip ML classification
        if useFallbackMode {
            print("🔄 Using fallback classification for cluster #\(index) with \(assets.count) assets")
            // Generate fallback tags based on date
            let fallbackClassifications = generateFallbackClassifications(from: assets)
            createAlbumDataFromClassifications(fallbackClassifications, assets: assets, index: index, completion: completion)
            return
        }
        
        print("🔍 Using ML classification for cluster #\(index) with \(assets.count) assets")
        
        // Track classification results across samples
        var allClassifications: [ClassificationResult] = []
        let group = DispatchGroup()
        var classificationErrorCount = 0
        
        // Process each sample asset
        for (idx, asset) in sampleAssets.enumerated() {
            group.enter()
            
            imageClassifier.classifyAsset(asset) { results in
                // Check if we got valid ML results or fallbacks
                let isFallbackResult = results.count == 2 && 
                    results.contains(where: { $0.label == "Photo" }) && 
                    results.contains(where: { $0.label == "Image" })
                
                if results.isEmpty {
                    classificationErrorCount += 1
                    print("⚠️ Asset #\(idx) in cluster #\(index) returned no classification results")
                } else if isFallbackResult {
                    classificationErrorCount += 1
                    print("⚠️ Asset #\(idx) in cluster #\(index) used fallback classification")
                } else {
                    print("✅ Successfully classified asset #\(idx) in cluster #\(index): \(results.map { $0.label }.joined(separator: ", "))")
                    allClassifications.append(contentsOf: results)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .global()) { [weak self] in
            guard let self = self else { return completion(nil) }
            
            // Log if we had any classification errors
            if classificationErrorCount > 0 {
                print("⚠️ Classification failed for \(classificationErrorCount)/\(sampleAssets.count) assets in cluster #\(index)")
            }
            
            // If all classifications failed or returned fallbacks, use fallback mechanism
            if classificationErrorCount == sampleAssets.count || allClassifications.isEmpty {
                print("⚠️ All ML classifications failed for cluster #\(index), falling back to basic classification")
                let fallbackClassifications = self.generateFallbackClassifications(from: assets)
                self.createAlbumDataFromClassifications(fallbackClassifications, assets: assets, index: index, completion: completion)
                return
            }
            
            // Combine classifications from all sample assets
            let combinedClassifications = self.combineClassificationResults(allClassifications)
            
            // Create the album data
            self.createAlbumDataFromClassifications(combinedClassifications, assets: assets, index: index, completion: completion)
        }
    }
    
    /// Create album data from classification results
    private func createAlbumDataFromClassifications(_ tags: [ClassificationResult], assets: [PHAsset], index: Int, completion: @escaping ((title: String, date: Date, score: Int32, thumbnail: String, tags: [String], assetIds: [String])?) -> Void) {
        // Get representative date
        guard let representativeAsset = assets.first else {
            print("⚠️ No representative asset found for cluster #\(index)")
            completion(nil)
            return
        }
        
        let date = representativeAsset.creationDate ?? Date()
        
        // Generate title from tags and date
        var title = generateTitle(from: tags, date: date, asset: representativeAsset)
        if title.isEmpty {
            print("⚠️ Failed to generate title for cluster #\(index)")
            // Provide a fallback title if generation fails
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            title = "Photos from \(dateFormatter.string(from: date))"
        }
        
        // Calculate relevance score
        let score = calculateRelevanceScore(tags: tags, assetCount: assets.count)
        
        // Get asset IDs
        let assetIds = assets.map { $0.localIdentifier }
        if assetIds.isEmpty {
            print("⚠️ No asset IDs for cluster #\(index), skipping album")
            completion(nil)
            return
        }
        
        // Ensure tags are never empty
        let tagLabels = tags.isEmpty ? ["Photos"] : tags.map { $0.label }
        
        // Select the most visually appealing thumbnail
        let thumbnailId: String
        if let bestThumbnail = selectBestThumbnailAsset(from: assets) {
            thumbnailId = bestThumbnail.localIdentifier
        } else if let firstAsset = assets.first {
            // Fallback to first asset if selection fails
            thumbnailId = firstAsset.localIdentifier
        } else {
            // This shouldn't happen as we checked assets aren't empty above
            print("⚠️ No thumbnail ID for cluster #\(index), skipping album")
            completion(nil)
            return
        }
        
        // Create and return the album data
        let albumData = (
            title: title,
            date: Date(),
            score: Int32(score),
            thumbnail: thumbnailId,
            tags: tagLabels,
            assetIds: assetIds
        )
        
        print("📝 Prepared album data: title=\(title), tags=\(tagLabels.count), assetIds=\(assetIds.count)")
        completion(albumData)
    }
    
    /// Generate fallback classifications based on date, time, and metadata
    private func generateFallbackClassifications(from assets: [PHAsset]) -> [ClassificationResult] {
        // Create fallback tags based on date/time and metadata
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        
        var classifications: [ClassificationResult] = [
            ClassificationResult(label: "Photos", confidence: 1.0),
            ClassificationResult(label: "Collection", confidence: 0.9)
        ]
        
        guard let firstAsset = assets.first, let date = firstAsset.creationDate else {
            return classifications
        }
        
        // Date-based classifications
        let dateLabel = dateFormatter.string(from: date)
        classifications.append(ClassificationResult(label: dateLabel, confidence: 0.8))
        
        // Season-based classification
        let month = Calendar.current.component(.month, from: date)
        var season = ""
        
        switch month {
        case 12, 1, 2:
            season = "Winter"
        case 3, 4, 5:
            season = "Spring"
        case 6, 7, 8:
            season = "Summer"
        case 9, 10, 11:
            season = "Fall"
        default:
            break
        }
        
        if !season.isEmpty {
            classifications.append(ClassificationResult(label: season, confidence: 0.75))
        }
        
        // Time-of-day context
        let hour = Calendar.current.component(.hour, from: date)
        var timeContext = ""
        
        switch hour {
        case 5..<8:
            timeContext = "Early morning"
        case 8..<12:
            timeContext = "Morning"
        case 12..<14:
            timeContext = "Midday"
        case 14..<17:
            timeContext = "Afternoon"
        case 17..<19:
            timeContext = "Evening"
        case 19..<22:
            timeContext = "Night"
        default:
            timeContext = "Late night"
        }
        
        classifications.append(ClassificationResult(label: timeContext, confidence: 0.7))
        
        // Add location-based classifications if available
        for asset in assets.prefix(3) { // Check up to 3 assets for location
            if let location = asset.location {
                // Try to get a reverse geolocation name
                let geocoder = CLGeocoder()
                let group = DispatchGroup()
                
                group.enter()
                geocoder.reverseGeocodeLocation(location) { placemarks, error in
                    defer { group.leave() }
                    
                    guard let placemark = placemarks?.first, error == nil else { return }
                    
                    // Add location-based tags with different confidence levels
                    if let country = placemark.country {
                        classifications.append(ClassificationResult(label: country, confidence: 0.65))
                    }
                    
                    if let city = placemark.locality {
                        classifications.append(ClassificationResult(label: city, confidence: 0.7))
                    }
                    
                    if let area = placemark.areasOfInterest?.first {
                        classifications.append(ClassificationResult(label: area, confidence: 0.75))
                    }
                }
                
                // Wait for geocoding to complete (with timeout)
                _ = group.wait(timeout: .now() + 1.0)
                
                // No need to check more assets if we found a location
                break
            }
        }
        
        // Check for burst photos
        let burstCount = assets.filter { $0.burstIdentifier != nil }.count
        if burstCount > 3 {
            classifications.append(ClassificationResult(label: "Burst photos", confidence: 0.75))
        }
        
        // Check for videos
        let videoCount = assets.filter { $0.mediaType == .video }.count
        if videoCount > 0 {
            let videoPercentage = Float(videoCount) / Float(assets.count)
            if videoPercentage > 0.5 {
                classifications.append(ClassificationResult(label: "Videos", confidence: 0.8))
            } else {
                classifications.append(ClassificationResult(label: "Photos and videos", confidence: 0.7))
            }
        }
        
        return classifications
    }
    
    /// Select representative assets from a cluster for analysis
    private func selectSampleAssets(from assets: [PHAsset]) -> [PHAsset] {
        guard !assets.isEmpty else { return [] }
        
        if assets.count <= maximumSamplesPerAlbum {
            return assets
        }
        
        // Strategy: Take first, middle, and last for temporal diversity
        let first = assets.first!
        let last = assets.last!
        
        var samples = [first, last]
        
        // Add middle item if we have more than 2 assets
        if assets.count > 2 {
            let middleIndex = assets.count / 2
            samples.append(assets[middleIndex])
        }
        
        return samples
    }
    
    /// Combine and weight classification results
    private func combineClassificationResults(_ results: [ClassificationResult]) -> [ClassificationResult] {
        // Group by label and sum confidences
        var combinedDict: [String: Float] = [:]
        
        for result in results {
            combinedDict[result.label, default: 0] += result.confidence
        }
        
        // Convert back to array and sort by confidence
        let combined = combinedDict.map { ClassificationResult(label: $0.key, confidence: $0.value) }
            .sorted { $0.confidence > $1.confidence }
        
        // Return top results
        return Array(combined.prefix(5))
    }
    
    /// Generate a natural language title from tags and metadata
    private func generateTitle(from tags: [ClassificationResult], date: Date, asset: PHAsset) -> String {
        // Get top tags
        let topTags = tags.prefix(3).map { $0.label }
        
        // Time of day context
        let hour = Calendar.current.component(.hour, from: date)
        var timeContext = ""
        
        switch hour {
        case 5..<12:
            timeContext = "morning"
        case 12..<17:
            timeContext = "afternoon"
        case 17..<21:
            timeContext = "evening"
        default:
            timeContext = "night"
        }
        
        // Build the title
        var title = ""
        
        // Format based on available information
        if let mainTag = topTags.first {
            // Avoid location lookups to prevent throttling
            title = "\(mainTag.capitalized) \(timeContext)"
        } else {
            // Fallback title if no good tags
            title = "Photos from \(date.formatted(.dateTime.month().day().year()))"
        }
        
        // Add emoji if available
        for tag in topTags {
            if let emoji = tagEmojis[tag.lowercased()] {
                title += " \(emoji)"
                break
            }
        }
        
        return title
    }
    
    /// Calculate a relevance score for the album
    private func calculateRelevanceScore(tags: [ClassificationResult], assetCount: Int) -> Int {
        var score = 0
        
        // Base score from classification confidence
        let confidenceScore = Int(tags.first?.confidence ?? 0 * 100)
        score += min(confidenceScore, 30) // Max 30 points for confidence
        
        // Score for number of assets (more photos = more significant event)
        let countScore = min(assetCount / 2, 30) // Max 30 points for count
        score += countScore
        
        // Score for variety of content (unique tags)
        let varietyScore = min(tags.count * 8, 25) // Max 25 points for variety
        score += varietyScore
        
        // Special tags that might indicate important moments
        let specialTags = ["birthday", "wedding", "graduation", "party", "holiday", "travel"]
        for tag in tags {
            if specialTags.contains(where: { tag.label.lowercased().contains($0) }) {
                score += 15 // Bonus for special events
                break
            }
        }
        
        return min(score, 100) // Cap at 100
    }
    
    /// Select the best thumbnail from a group of assets
    private func selectBestThumbnailAsset(from assets: [PHAsset]) -> PHAsset? {
        // Filter for landscape photos that aren't screenshots
        let candidates = assets.filter { asset in
            asset.mediaType == .image && 
            asset.pixelWidth > asset.pixelHeight && 
            !asset.isScreenshot()
        }
        
        // If no good candidates, return first asset
        if candidates.isEmpty {
            return assets.first
        }
        
        // Prefer assets with better metadata
        let scoredCandidates = candidates.map { asset -> (PHAsset, Int) in
            var score = 0
            
            // Favor photos with location data
            if asset.location != nil {
                score += 10
            }
            
            // Favor higher resolution assets
            let resolution = asset.pixelWidth * asset.pixelHeight
            score += min(resolution / 100000, 10)
            
            return (asset, score)
        }
        
        // Return highest scoring candidate
        return scoredCandidates.max(by: { $0.1 < $1.1 })?.0 ?? candidates.first
    }
}

// MARK: - PHAsset Extensions
extension PHAsset {
    func isScreenshot() -> Bool {
        // Check for screenshot-like dimensions and naming patterns
        if let filename = self.value(forKey: "filename") as? String {
            return filename.lowercased().contains("screenshot")
        }
        return false
    }
} 