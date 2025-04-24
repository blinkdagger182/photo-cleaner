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