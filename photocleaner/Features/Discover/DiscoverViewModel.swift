import Foundation
import SwiftUI
import Photos

class DiscoverViewModel: ObservableObject {
    // Services
    private let smartAlbumManager = SmartAlbumManager.shared
    private var photoManager: PhotoManager
    var toast: ToastService?
    
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
            // Add null safety to prevent crashes with invalid dates
            guard album.createdAt > Date(timeIntervalSince1970: 0) else { return false }
            
            let now = Date()
            let daysSinceCreation = Calendar.current.dateComponents([.day], from: album.createdAt, to: now).day ?? 0
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
        },
        "Utilities": { (album: SmartAlbumGroup) -> Bool in
            let utilityTags = ["receipt", "document", "text", "handwriting", "illustration", "drawing", 
                              "qr", "code", "scan", "duplicate", "screenshot", "import"]
            return album.tags.contains { tag in utilityTags.contains { tag.lowercased().contains($0) } }
        }
    ]
    
    init(photoManager: PhotoManager, toast: ToastService? = nil) {
        self.photoManager = photoManager
        self.toast = toast
        self.loadAlbums()
    }
    
    // MARK: - Public Methods
    
    /// Load smart albums from the repository
    func loadAlbums(forceRefresh: Bool = false) {
        isLoading = true
        
        // Show loading toast on main thread
        DispatchQueue.main.async { [weak self] in
            self?.toast?.show("Refreshing albums...", duration: 1.5)
        }
        
        if forceRefresh {
            // Perform a full refresh by regenerating albums
            smartAlbumManager.refreshSmartAlbums(from: photoManager.allAssets) { [weak self] in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    // Update UI after refresh
                    self.featuredAlbums = self.smartAlbumManager.featuredAlbums
                    self.categorizeAlbums(self.smartAlbumManager.allSmartAlbums)
                    self.showEmptyState = self.smartAlbumManager.allSmartAlbums.isEmpty
                    self.isLoading = false
                    
                    // Show completion toast
                    self.toast?.show("Albums refreshed!", duration: 1.5)
                }
            }
        } else {
            // Just load existing albums from CoreData
            smartAlbumManager.loadSmartAlbums()
            self.featuredAlbums = smartAlbumManager.featuredAlbums
            
            // Categorize albums
            categorizeAlbums(smartAlbumManager.allSmartAlbums)
            
            // Show empty state if needed
            showEmptyState = smartAlbumManager.allSmartAlbums.isEmpty
            
            isLoading = false
            
            // Show completion toast with delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.toast?.show("Albums refreshed!", duration: 1.5)
            }
        }
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
        // Safely fetch assets
        let assets = album.fetchAssets()
        
        // Guard against empty assets to prevent potential crashes
        guard !assets.isEmpty else {
            return "Photo Collection"
        }
        
        // Define utility tags
        let utilityTags = ["receipt", "document", "text", "handwriting", "illustration", "drawing", 
                          "qr", "code", "scan", "duplicate", "screenshot", "import"]
        
        // Safely check if this is a utilities album based on tags
        // Make sure we have tags before checking
        if !album.tags.isEmpty {
            let isUtilityAlbum = album.tags.contains { tag in 
                utilityTags.contains { utilityTag in 
                    tag.lowercased().contains(utilityTag) 
                }
            }
            
            if isUtilityAlbum {
                // For utility albums, generate a title based on the utility tags
                let matchingTags = album.tags.filter { tag in 
                    utilityTags.contains { utilityTag in 
                        tag.lowercased().contains(utilityTag) 
                    }
                }
                
                if let primaryTag = matchingTags.first {
                    // Safely capitalize the first letter of the tag
                    let capitalizedTag: String
                    if primaryTag.isEmpty {
                        capitalizedTag = "Document"
                    } else {
                        capitalizedTag = primaryTag.prefix(1).capitalized + primaryTag.dropFirst()
                    }
                    
                    // Generate a title based on the utility tag
                    let utilityTitles = [
                        "\(capitalizedTag) Collection",
                        "\(capitalizedTag) Library",
                        "My \(capitalizedTag)s",
                        "Saved \(capitalizedTag)s",
                        "\(capitalizedTag) Archive"
                    ]
                    
                    return utilityTitles.randomElement() ?? "\(capitalizedTag) Collection"
                }
            }
        }
        
        // For non-utility albums or if utility title generation failed, use the standard approach
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