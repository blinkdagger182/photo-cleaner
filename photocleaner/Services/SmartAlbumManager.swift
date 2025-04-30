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
        // Nature and places
        "beach": "🏖️",
        "mountain": "🏔️",
        "sunset": "🌅",
        "city": "🏙️",
        "snow": "❄️",
        "flower": "🌸",
        
        // Food and dining
        "food": "🍽️",
        "pizza": "🍕",
        "coffee": "☕",
        
        // Animals
        "dog": "🐕",
        "cat": "🐱",
        
        // Events
        "birthday": "🎂",
        "party": "🎉",
        "concert": "🎵",
        
        // Transportation
        "car": "🚗",
        
        // Utility items
        "receipt": "🧾",
        "document": "📄",
        "text": "📝",
        "handwriting": "✍️",
        "illustration": "🎨",
        "drawing": "✏️",
        "qr": "📱",
        "code": "💻",
        "scan": "🔍",
        "duplicate": "🔄",
        "screenshot": "📱",
        "import": "📥"
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
                    print("✅ ML model loaded successfully on retry")
                } else {
                    print("⚠️ ML model still not available, using fallback classification")
                }
            } else {
                finalMlModelAvailable = true
            }
            
            // Create batches of clusters to process
            let batches = stride(from: 0, to: clustersToProcess.count, by: batchSize).map { startIndex -> [Int] in
                let end = min(startIndex + batchSize, clustersToProcess.count)
                return Array(clustersToProcess[startIndex..<end])
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
                    var albumData: (title: String, date: Date, score: Int32, thumbnail: String, tags: [String], assetIds: [String])? = nil
                    
                    // Use a dispatch group to wait for completion
                    let group = DispatchGroup()
                    group.enter()
                    
                    // Process cluster for album data
                    self.processClusterForData(cluster, index: clusterIndex, useFallbackMode: !finalMlModelAvailable) { data in
                        albumData = data
                        group.leave()
                    }
                    
                    // Wait for processing to complete
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
                            // Create a new album
                            let newAlbum = SmartAlbumGroup(context: viewContext)
                            newAlbum.id = UUID()
                            newAlbum.title = data.title
                            newAlbum.createdAt = data.date
                            newAlbum.relevanceScore = data.score
                            newAlbum.thumbnailId = data.thumbnail
                            newAlbum.tags = data.tags
                            newAlbum.assetIds = data.assetIds
                            
                            savedAlbumCount += 1
                        }
                        
                        // Save the context
                        do {
                            try viewContext.save()
                            print("✅ Saved batch \(batchIndex+1) with \(batchAlbumData.count) albums")
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
        
        // Sort by creation date (descending) to get the most recent albums
        let sortDescriptor = NSSortDescriptor(key: "createdAt", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        do {
            let albums = try context.fetch(fetchRequest)
            
            // Update on main thread
            DispatchQueue.main.async {
                self.allSmartAlbums = albums
                
                // Get recent albums (last 30 days)
                let calendar = Calendar.current
                let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                
                // Filter albums created in the last 30 days with null safety
                let recentAlbums = albums.filter { album in
                    // Skip albums with invalid dates
                    guard album.createdAt > Date(timeIntervalSince1970: 0) else { return false }
                    return album.createdAt.compare(thirtyDaysAgo) == .orderedDescending
                }
                
                // For featured albums, prioritize recent albums first, then fall back to high-scoring albums if needed
                if recentAlbums.count >= 5 {
                    // If we have enough recent albums, sort them by relevance score and take the top 5
                    let sortedRecentAlbums = recentAlbums.sorted { $0.relevanceScore > $1.relevanceScore }
                    self.featuredAlbums = Array(sortedRecentAlbums.prefix(5))
                } else {
                    // If we don't have enough recent albums, include some high-scoring older albums
                    var featured = recentAlbums
                    
                    // Add high-scoring albums that aren't already in the featured list
                    let highScoringAlbums = albums.sorted { $0.relevanceScore > $1.relevanceScore }
                    for album in highScoringAlbums where featured.count < 5 {
                        if !featured.contains(where: { $0.id == album.id }) {
                            featured.append(album)
                        }
                    }
                    
                    self.featuredAlbums = featured
                }
            }
        } catch {
            print("❌ Failed to fetch smart albums: \(error)")
        }
    }
    
    /// Refresh smart albums by regenerating them from the photo library
    func refreshSmartAlbums(from assets: [PHAsset], completion: @escaping () -> Void) {
        // First, clear existing albums
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<SmartAlbumGroup> = SmartAlbumGroup.fetchRequest()
        
        do {
            let existingAlbums = try context.fetch(fetchRequest)
            print("🔄 Refreshing \(existingAlbums.count) smart albums")
            
            // Delete all existing albums
            for album in existingAlbums {
                context.delete(album)
            }
            
            // Save the context to commit deletions
            try context.save()
            print("✅ Cleared existing albums")
            
            // Regenerate albums
            generateSmartAlbums(from: assets, limit: 0) {
                completion()
            }
        } catch {
            print("❌ Failed to refresh albums: \(error)")
            completion()
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
            guard let date1 = $0.creationDate, let date2 = $1.creationDate else {
                return false
            }
            return date1 < date2
        }
        
        // Filter out assets without creation dates
        let validAssets = sortedAssets.filter { $0.creationDate != nil }
        
        if validAssets.isEmpty {
            return []
        }
        
        var clusters: [[PHAsset]] = []
        var currentCluster: [PHAsset] = [validAssets[0]]
        
        // Group photos that were taken within the time window
        for i in 1..<validAssets.count {
            let asset = validAssets[i]
            let previousAsset = validAssets[i-1]
            
            guard let date = asset.creationDate, let previousDate = previousAsset.creationDate else {
                continue
            }
            
            let hoursDifference = date.timeIntervalSince(previousDate) / 3600
            
            if hoursDifference <= clusterTimeWindowHours {
                // Add to current cluster
                currentCluster.append(asset)
            } else {
                // Start a new cluster
                clusters.append(currentCluster)
                currentCluster = [asset]
            }
        }
        
        // Add the last cluster
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }
        
        return clusters
    }
    
    /// Process a cluster of photos and return data needed to create an album
    private func processClusterForData(_ assets: [PHAsset], index: Int, useFallbackMode: Bool, completion: @escaping ((title: String, date: Date, score: Int32, thumbnail: String, tags: [String], assetIds: [String])?) -> Void) {
        guard assets.count >= minimumPhotosForAlbum else {
            print("⚠️ Cluster #\(index) too small (\(assets.count) < \(minimumPhotosForAlbum)), skipping")
            completion(nil)
            return
        }
        
        // Get representative date
        guard let representativeAsset = assets.first else {
            print("⚠️ No representative asset found for cluster #\(index)")
            completion(nil)
            return
        }
        
        // Select a subset of assets to classify (to avoid processing too many)
        let sampleAssets = assets.count > maximumSamplesPerAlbum ? 
            Array(assets.prefix(maximumSamplesPerAlbum)) : assets
        
        // Track classification results and errors
        var allClassifications: [ClassificationResult] = []
        var classificationErrorCount = 0
        
        // Create a dispatch group for parallel classification
        let group = DispatchGroup()
        
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
        
        group.notify(queue: DispatchQueue.global()) { [weak self] in
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
        
        // Get asset IDs
        let assetIds = assets.map { $0.localIdentifier }
        if assetIds.isEmpty {
            print("⚠️ No asset IDs for cluster #\(index), skipping album")
            completion(nil)
            return
        }
        
        // Select the best thumbnail asset
        let thumbnailAsset = selectBestThumbnailAsset(from: assets) ?? representativeAsset
        let thumbnailId = thumbnailAsset.localIdentifier
        
        // Calculate average date for the cluster
        let dates = assets.compactMap { $0.creationDate }
        let averageDate = dates.reduce(Date()) { $0.addingTimeInterval($1.timeIntervalSince1970) }.addingTimeInterval(-Double(dates.count) * Date().timeIntervalSince1970 / Double(dates.count))
        
        // Get tag labels from classification results
        let tagLabels = tags.isEmpty ? ["Photos"] : tags.map { $0.label }
        
        // Extract location information from the assets
        let location = self.extractLocationFromAssets(assets)
        
        // Determine time of day from average date
        let hour = Calendar.current.component(.hour, from: averageDate)
        var timeOfDay: String
        
        switch hour {
        case 5..<12:
            timeOfDay = "morning"
        case 12..<17:
            timeOfDay = "afternoon"
        case 17..<21:
            timeOfDay = "evening"
        default:
            timeOfDay = "night"
        }
        
        // Generate title using our new AlbumTitleGenerator
        let title = AlbumTitleGenerator.generate(
            location: location,
            timeOfDay: timeOfDay,
            photoCount: assets.count
        )
        
        // Calculate a relevance score
        let score = Int32(self.calculateRelevanceScore(tags: tags, assetCount: assets.count))
        
        // Create and return the album data
        let albumData = (
            title: title,
            date: averageDate,
            score: score,
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
            ClassificationResult(label: "Photos", confidence: 1.0)
        ]
        
        // Add time-based classification
        if let date = assets.first?.creationDate {
            let hour = Calendar.current.component(.hour, from: date)
            
            // Time of day
            let timeTag: String
            switch hour {
            case 5..<12:
                timeTag = "Morning"
            case 12..<17:
                timeTag = "Afternoon"
            case 17..<21:
                timeTag = "Evening"
            default:
                timeTag = "Night"
            }
            
            classifications.append(ClassificationResult(label: timeTag, confidence: 0.9))
            
            // Month/year
            let monthYear = dateFormatter.string(from: date)
            classifications.append(ClassificationResult(label: monthYear, confidence: 0.8))
        }
        
        // Location-based classification if available
        if let location = extractLocationFromAssets(assets) {
            classifications.append(ClassificationResult(label: location, confidence: 0.85))
        }
        
        // Check for utility-type items
        detectUtilityItems(in: assets, classifications: &classifications)
        
        return classifications
    }
    
    /// Select representative sample assets from a cluster
    private func selectSampleAssets(from assets: [PHAsset], maxSamples: Int = 3) -> [PHAsset] {
        guard !assets.isEmpty else { return [] }
        
        if assets.count <= maxSamples {
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
    
    /// Combine and filter classification results
    private func combineClassificationResults(_ classifications: [ClassificationResult]) -> [ClassificationResult] {
        // Group by label and combine confidence scores
        var combinedDict: [String: Double] = [:]
        
        for classification in classifications {
            combinedDict[classification.label, default: 0] += Double(classification.confidence)
        }
        
        // Convert back to array of ClassificationResult and sort by confidence
        let combined = combinedDict.map { ClassificationResult(label: $0.key, confidence: Float($0.value)) }
            .sorted { $0.confidence > $1.confidence }
        
        // Filter out generic labels
        let filteredResults = combined.filter { !isGenericLabel($0.label) }
        
        // Take top results or fall back to original if all were filtered
        return filteredResults.isEmpty ? combined.prefix(3).map { $0 } : filteredResults.prefix(5).map { $0 }
    }
    
    /// Combine and filter classification results (alias for combineClassificationResults for backward compatibility)
    private func combineAndFilterClassifications(_ classifications: [ClassificationResult]) -> [ClassificationResult] {
        return combineClassificationResults(classifications)
    }
    
    /// Check if a label is generic and should be given lower priority
    private func isGenericLabel(_ label: String) -> Bool {
        let genericLabels = ["photo", "image", "picture", "photography", "snapshot", "photograph"]
        return genericLabels.contains(label.lowercased())
    }
    
    /// Generate a title for an album based on classification results
    private func generateTitle(from tags: [ClassificationResult], date: Date, asset: PHAsset) -> String {
        // Get top tags for title generation
        let topTags = tags.prefix(3).map { $0.label }
        
        // Extract location from the asset if available
        var locationName: String? = nil
        if let location = asset.location {
            // Use our Malaysian location approximation
            // This matches the approach in extractLocationFromAssets
            let malaysianLocations = [
                "Kuala Lumpur": CLLocationCoordinate2D(latitude: 3.1390, longitude: 101.6869),
                "Petaling Jaya": CLLocationCoordinate2D(latitude: 3.1073, longitude: 101.6068),
                "Bangsar": CLLocationCoordinate2D(latitude: 3.1340, longitude: 101.6780),
                "Mont Kiara": CLLocationCoordinate2D(latitude: 3.1762, longitude: 101.6503),
                "Subang Jaya": CLLocationCoordinate2D(latitude: 3.0567, longitude: 101.5850),
                "Shah Alam": CLLocationCoordinate2D(latitude: 3.0733, longitude: 101.5185),
                "Ampang": CLLocationCoordinate2D(latitude: 3.1631, longitude: 101.7612),
                "Damansara": CLLocationCoordinate2D(latitude: 3.1571, longitude: 101.6304),
                "Cheras": CLLocationCoordinate2D(latitude: 3.0904, longitude: 101.7286),
                "Putrajaya": CLLocationCoordinate2D(latitude: 2.9264, longitude: 101.6964)
            ]
            
            // Find the closest Malaysian location
            var closestLocation = "KL"
            var shortestDistance = Double.greatestFiniteMagnitude
            
            for (locationName, coordinates) in malaysianLocations {
                let distance = hypot(
                    location.coordinate.latitude - coordinates.latitude,
                    location.coordinate.longitude - coordinates.longitude
                )
                
                if distance < shortestDistance {
                    shortestDistance = distance
                    closestLocation = locationName
                }
            }
            
            // Only use if it's reasonably close (within ~50km)
            if shortestDistance < 0.5 { // Rough approximation
                locationName = closestLocation
            } else {
                // Fallback to a random Malaysian location
                let randomLocations = ["KL", "Bangsar", "Mont Kiara", "Damansara", "Ampang"]
                locationName = randomLocations.randomElement()
            }
        }
        
        // Determine time context
        let hour = Calendar.current.component(.hour, from: date)
        var timeContext: String
        
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
        
        // Use our new AlbumTitleGenerator
        let title = AlbumTitleGenerator.generate(
            location: locationName,
            timeOfDay: timeContext,
            photoCount: nil
        )
        
        // Add emoji if available from our tags
        var finalTitle = title
        for tag in topTags {
            if let emoji = tagEmojis[tag.lowercased()] {
                if !finalTitle.contains(emoji) {
                    finalTitle += " \(emoji)"
                }
                break
            }
        }
        
        return finalTitle
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
    
    /// Extract a location name from a collection of assets
    private func extractLocationFromAssets(_ assets: [PHAsset]) -> String? {
        // For now, we'll use a simplified approach with hardcoded Malaysian locations
        // In a real app, you would use CLGeocoder to reverse geocode the coordinates
        
        // Check if any assets have location data
        let assetsWithLocation = assets.filter { $0.location != nil }
        if assetsWithLocation.isEmpty {
            return nil
        }
        
        // Use hardcoded Malaysian locations based on coordinates for demo purposes
        // This is a simplified approach without actual reverse geocoding
        let malaysianLocations = [
            "Kuala Lumpur": CLLocationCoordinate2D(latitude: 3.1390, longitude: 101.6869),
            "Petaling Jaya": CLLocationCoordinate2D(latitude: 3.1073, longitude: 101.6068),
            "Bangsar": CLLocationCoordinate2D(latitude: 3.1340, longitude: 101.6780),
            "Mont Kiara": CLLocationCoordinate2D(latitude: 3.1762, longitude: 101.6503),
            "Subang Jaya": CLLocationCoordinate2D(latitude: 3.0567, longitude: 101.5850),
            "Shah Alam": CLLocationCoordinate2D(latitude: 3.0733, longitude: 101.5185),
            "Ampang": CLLocationCoordinate2D(latitude: 3.1631, longitude: 101.7612),
            "Damansara": CLLocationCoordinate2D(latitude: 3.1571, longitude: 101.6304),
            "Cheras": CLLocationCoordinate2D(latitude: 3.0904, longitude: 101.7286),
            "Putrajaya": CLLocationCoordinate2D(latitude: 2.9264, longitude: 101.6964)
        ]
        
        // Count occurrences of each location based on proximity
        var locationCounts: [String: Int] = [:]
        
        for asset in assetsWithLocation {
            if let assetLocation = asset.location?.coordinate {
                // Find the closest Malaysian location
                var closestLocation = "KL"
                var shortestDistance = Double.greatestFiniteMagnitude
                
                for (locationName, coordinates) in malaysianLocations {
                    let distance = hypot(
                        assetLocation.latitude - coordinates.latitude,
                        assetLocation.longitude - coordinates.longitude
                    )
                    
                    if distance < shortestDistance {
                        shortestDistance = distance
                        closestLocation = locationName
                    }
                }
                
                // Only count if it's reasonably close (within ~50km)
                if shortestDistance < 0.5 { // Rough approximation
                    locationCounts[closestLocation, default: 0] += 1
                }
            }
        }
        
        // If no matches, return a default location or nil
        if locationCounts.isEmpty {
            // Random selection of Malaysian locations for variety
            let randomLocations = ["KL", "Bangsar", "Mont Kiara", "Damansara", "Ampang"]
            return randomLocations.randomElement()
        }
        
        // Find the most common location
        return locationCounts.max(by: { $0.value < $1.value })?.key
    }
    
    /// Detect utility items like receipts, documents, QR codes, etc. in photo assets
    private func detectUtilityItems(in assets: [PHAsset], classifications: inout [ClassificationResult]) {
        // Check for screenshots
        let screenshotCount = assets.filter { $0.isScreenshot() }.count
        if screenshotCount > 0 {
            let confidence = min(Float(screenshotCount) / Float(assets.count) + 0.3, 0.95)
            classifications.append(ClassificationResult(label: "screenshot", confidence: confidence))
        }
        
        // Check for document-like aspect ratios (typically close to A4 or letter size)
        var documentLikeCount = 0
        for asset in assets {
            let aspectRatio = Double(asset.pixelWidth) / Double(asset.pixelHeight)
            // A4 and letter paper have aspect ratios around 0.7-0.77
            if (aspectRatio > 0.65 && aspectRatio < 0.85) || (aspectRatio > 1.2 && aspectRatio < 1.5) {
                documentLikeCount += 1
            }
        }
        
        if documentLikeCount > assets.count / 3 {
            classifications.append(ClassificationResult(label: "document", confidence: 0.8))
        }
        
        // For QR codes, receipts, handwriting, etc., we would ideally use ML vision analysis
        // Since we don't have that capability here, we'll use some basic heuristics
        
        // Check for square images (potential QR codes)
        let squareImageCount = assets.filter { abs(Double($0.pixelWidth) / Double($0.pixelHeight) - 1.0) < 0.1 }.count
        if squareImageCount > assets.count / 3 {
            classifications.append(ClassificationResult(label: "qr code", confidence: 0.7))
        }
        
        // Add receipt tag for portrait orientation images with specific aspect ratio
        let receiptLikeCount = assets.filter { 
            let aspectRatio = Double($0.pixelWidth) / Double($0.pixelHeight)
            return aspectRatio < 0.6 // Very tall and narrow
        }.count
        
        if receiptLikeCount > assets.count / 4 {
            classifications.append(ClassificationResult(label: "receipt", confidence: 0.75))
        }
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
