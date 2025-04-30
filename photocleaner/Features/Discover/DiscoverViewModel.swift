import Foundation
import SwiftUI
import Photos

class DiscoverViewModel: ObservableObject {
    // Services
    private let smartAlbumManager = SmartAlbumManager.shared
    private var photoManager: PhotoManager
    
    // Published properties
    @Published var featuredAlbums: [SmartAlbumGroup] = []
    @Published var categorizedAlbums: [String: [SmartAlbumGroup]] = [:]
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var selectedAlbum: SmartAlbumGroup?
    @Published var showEmptyState = false
    
    // Computed property to access all smart albums
    var allSmartAlbums: [SmartAlbumGroup] {
        return smartAlbumManager.allSmartAlbums
    }
    
    // Categories for organizing albums
    private let categories = [
        "High Score": { (album: SmartAlbumGroup) -> Bool in album.relevanceScore > 70 },
        "Recent": { (album: SmartAlbumGroup) -> Bool in 
            let daysSinceCreation = Calendar.current.dateComponents([.day], from: album.createdAt, to: Date()).day ?? 0
            return daysSinceCreation < 7
        },
        "Food & Dining": { (album: SmartAlbumGroup) -> Bool in 
            let foodTags = ["food", "restaurant", "pizza", "dinner", "lunch", "breakfast", "coffee"]
            return album.tags.contains { tag in foodTags.contains { tag.lowercased().contains($0) } }
        },
        "Nature": { (album: SmartAlbumGroup) -> Bool in
            let natureTags = ["beach", "mountain", "forest", "park", "lake", "sunset", "nature"]
            return album.tags.contains { tag in natureTags.contains { tag.lowercased().contains($0) } }
        },
        "People": { (album: SmartAlbumGroup) -> Bool in
            let peopleTags = ["person", "people", "face", "portrait", "group", "family"]
            return album.tags.contains { tag in peopleTags.contains { tag.lowercased().contains($0) } }
        }
    ]
    
    init(photoManager: PhotoManager) {
        self.photoManager = photoManager
        self.loadAlbums()
    }
    
    // MARK: - Public Methods
    
    /// Load smart albums from the repository
    func loadAlbums() {
        isLoading = true
        
        // Load from the manager
        smartAlbumManager.loadSmartAlbums()
        self.featuredAlbums = smartAlbumManager.featuredAlbums
        
        // Categorize albums
        categorizeAlbums(smartAlbumManager.allSmartAlbums)
        
        // Show empty state if needed
        showEmptyState = smartAlbumManager.allSmartAlbums.isEmpty
        
        isLoading = false
    }
    
    /// Generate new smart albums
    func generateAlbums(limit: Int = 100) {
        guard !isGenerating else { return }
        
        isGenerating = true
        
        // Use assets from the photo manager with a limit of 100 albums
        smartAlbumManager.generateSmartAlbums(from: photoManager.allAssets, limit: limit) { [weak self] in
            DispatchQueue.main.async {
                self?.isGenerating = false
                self?.loadAlbums()
            }
        }
    }
    
    /// Generate more albums, continuing from existing ones
    func generateMoreAlbums(additionalCount: Int = 100) {
        guard !isGenerating else { return }
        
        isGenerating = true
        
        // First determine how many albums we already have
        let existingCount = allSmartAlbums.count
        print("📸 Already have \(existingCount) albums, generating \(additionalCount) more")
        
        // Use assets from the photo manager with a start offset
        smartAlbumManager.generateSmartAlbums(from: photoManager.allAssets, limit: existingCount + additionalCount) { [weak self] in
            DispatchQueue.main.async {
                self?.isGenerating = false
                self?.loadAlbums()
            }
        }
    }
    
    /// Delete a smart album
    func deleteAlbum(_ album: SmartAlbumGroup) {
        smartAlbumManager.deleteAlbum(album)
        loadAlbums()
    }
    
    /// Get assets for a specific album
    func getAssets(for album: SmartAlbumGroup) -> [PHAsset] {
        return album.fetchAssets()
    }
    
    /// Generate a beautiful title for an album using the AlbumTitleGenerator
    func generateBeautifulTitle(for album: SmartAlbumGroup) -> String {
        let assets = album.fetchAssets()
        
        // Extract location if available (using the first few assets)
        let location = extractLocationFromAssets(assets.prefix(5))
        
        // Determine predominant time of day
        let timeOfDay = extractTimeOfDay(from: assets)
        
        // Generate the title
        return AlbumTitleGenerator.generate(
            location: location,
            timeOfDay: timeOfDay,
            photoCount: assets.count
        )
    }
    
    /// Extract location name from assets
    private func extractLocationFromAssets(_ assets: ArraySlice<PHAsset>) -> String? {
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
    
    /// Extract time of day from assets
    private func extractTimeOfDay(from assets: [PHAsset]) -> String? {
        var timeOfDayCounts: [String: Int] = [
            "morning": 0,
            "afternoon": 0,
            "evening": 0,
            "night": 0
        ]
        
        for asset in assets {
            let hour = Calendar.current.component(.hour, from: asset.creationDate ?? Date())
            
            switch hour {
            case 5..<12:
                timeOfDayCounts["morning", default: 0] += 1
            case 12..<17:
                timeOfDayCounts["afternoon", default: 0] += 1
            case 17..<21:
                timeOfDayCounts["evening", default: 0] += 1
            default:
                timeOfDayCounts["night", default: 0] += 1
            }
        }
        
        // Find the most common time of day
        return timeOfDayCounts.max(by: { $0.value < $1.value })?.key
    }
    
    // MARK: - Private Methods
    
    /// Categorize albums into sections
    private func categorizeAlbums(_ albums: [SmartAlbumGroup]) {
        var categorized: [String: [SmartAlbumGroup]] = [:]
        
        // Group albums by category
        for (categoryName, predicate) in categories {
            let matchingAlbums = albums.filter(predicate)
            if !matchingAlbums.isEmpty {
                categorized[categoryName] = matchingAlbums
            }
        }
        
        // Add an "All" category if we have albums
        if !albums.isEmpty {
            categorized["All"] = albums
        }
        
        self.categorizedAlbums = categorized
    }
} 