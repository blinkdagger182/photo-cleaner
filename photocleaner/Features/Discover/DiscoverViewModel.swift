import Foundation
import SwiftUI
import Photos
import Combine

class DiscoverViewModel: ObservableObject {
    // Services
    private let smartAlbumManager = SmartAlbumManager.shared
    private let batchProcessor = BatchProcessingManager.shared
    private let clusteringManager = PhotoClusteringManager.shared
    private var photoManager: PhotoManager
    var toast: ToastService?
    
    // Memory optimization
    private let photoCache = OptimizedPhotoCache.shared
    
    // Published properties
    @Published var featuredAlbums: [SmartAlbumGroup] = []
    @Published var categorizedAlbums: [String: [SmartAlbumGroup]] = [:]
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var selectedAlbum: SmartAlbumGroup?
    @Published var selectedGroup: PhotoGroup? // For SwipeCardView navigation
    @Published var showEmptyState = false
    @Published var useFallbackMode = true // Use fallback mode to prevent black screens
    @Published var forceRefresh: Bool = false // For SwipeCardView
    
    // Advanced clustering properties
    @Published var isClusteringInProgress: Bool = false
    @Published var clusteringProgress: Double = 0.0
    @Published var photoGroups: [PhotoGroup] = []
    @Published var processedAlbumCount: Int = 0 // Track the number of processed albums
    
    // Pagination properties
    @Published var hasMoreAlbums: Bool = false
    @Published var isLoadingMore: Bool = false
    private var currentPage: Int = 1
    private let albumsPerPage: Int = 10
    
    // Photo count statistics
    @Published var totalPhotoCount: Int = 0
    @Published var albumsInCategoriesCount: Int = 0
    @Published var discoveredPhotoCount: Int = 0
    @Published var batchProcessingProgress: Double = 0.0
    @Published var isBatchProcessing: Bool = false
    
    // Sort order for events
    @Published var eventsShowMostRecentFirst: Bool = true
    @Published var eventsSortOption: EventSortOption = .newestFirst
    @Published var isSortingEvents: Bool = false
    
    // Sort order for featured albums
    @Published var featuredSortByMostPhotos: Bool = true
    @Published var isSortingFeatured: Bool = false
    
    // Collapsible categories tracking
    @Published var collapsedCategories: Set<String> = []
    
    // Flag to indicate if we have clustering results available - Always true now
    @Published var hasClusteringResults: Bool = true
    
    // Sort options for Events
    enum EventSortOption: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case mostPhotos = "Most Photos"
        case mostRelevant = "Most Relevant"
        
        var id: String { self.rawValue }
    }
    
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
            // Check if the album title already indicates it's a utility album
            let utilityTitleIndicators = ["Screenshot", "Receipt", "Document", "QR Code", "Scan", "Duplicate"]
            if utilityTitleIndicators.contains(where: { album.title.contains($0) }) {
                return true
            }
            
            // Check tags for utility indicators
            let utilityTags = ["receipt", "document", "text", "handwriting", "illustration", "drawing", 
                              "qr", "code", "scan", "duplicate", "screenshot", "import"]
            return album.tags.contains { tag in utilityTags.contains { tag.lowercased().contains($0) } }
        }
    ]
    
    // MARK: - Initialization
    
    init(photoManager: PhotoManager, toast: ToastService? = nil) {
        self.photoManager = photoManager
        self.toast = toast
        
        // Configure the clustering manager with the photo manager
        clusteringManager.configure(with: photoManager)
        
        // Set up batch processing subscribers
        setupBatchProcessingSubscribers()
        
        // Remove automatic processing at initialization to improve startup time
        // The processing will be triggered when loadAlbums is called
    }
    
    private func setupBatchProcessingSubscribers() {
        // Subscribe to batch processing progress updates
        batchProcessor.progressPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.batchProcessingProgress = Double(progress)
            }
            .store(in: &cancellables)
        
        // Subscribe to batch processing completion
        batchProcessor.completionPublisher
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] completion in
                Task { @MainActor in
                    if case .failure(let error) = completion {
                        self?.toast?.showError("Error: \(error.localizedDescription)", duration: 3.0)
                    }
                    self?.isBatchProcessing = false
                }
            }, receiveValue: { [weak self] in
                Task { @MainActor in
                    self?.isBatchProcessing = false
                    self?.loadAlbums()
                    self?.toast?.showSuccess("Album generation complete!", duration: 2.0)
                }
            })
            .store(in: &cancellables)
    }
    
    // Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // Main actor isolation
    @MainActor private func showToast(_ message: String, duration: TimeInterval = 1.5) {
        toast?.showInfo(message, duration: duration)
    }
    
    // Check if we have clustering results - Now only uses clustering results
    private func checkForClusteringResults() {
        // Load albums with clustering data if available, otherwise generate them
        if !photoGroups.isEmpty {
            hasClusteringResults = true
            updateUIWithPhotoGroups(photoGroups)
        } else {
            // No clustering results yet, start processing
            Task { @MainActor in
                await processEntireLibrary()
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Toggles the collapse state of a category
    func toggleCategoryCollapse(_ category: String) {
        if collapsedCategories.contains(category) {
            collapsedCategories.remove(category)
        } else {
            collapsedCategories.insert(category)
        }
    }
    
    /// Checks if a category is collapsed
    func isCategoryCollapsed(_ category: String) -> Bool {
        return collapsedCategories.contains(category)
    }
    
    /// Load albums from clustering results or start processing if needed
    func loadAlbums(forceRefresh: Bool = false) {
        isLoading = true
        
        // Show loading toast on main thread
        Task { @MainActor [weak self] in
            self?.toast?.showInfo("Loading albums...", duration: 1.5)
        }
        
        // Check if we need to process the library
        if photoGroups.isEmpty || forceRefresh {
            Task { @MainActor in
                await processEntireLibrary()
            }
        } else {
            // If we already have data, just display it
            updateUIWithPhotoGroups(photoGroups)
            isLoading = false
        }
    }
    
    /// Process the entire photo library using advanced clustering
    @MainActor
    func processEntireLibrary() async {
        guard !isClusteringInProgress else {
            toast?.showWarning("Already processing photo library", duration: 1.5)
            return
        }
        
        isClusteringInProgress = true
        clusteringProgress = 0.0
        processedAlbumCount = 0 // Reset processed album count
        
        // Show toast notification
        toast?.showInfo("Processing photo library by time and location...", duration: 2.0)
        
        // Set up a timer to update the UI with progress
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.clusteringProgress = self.clusteringManager.progress
            
            // Estimate processed album count based on progress
            let estimatedAlbumCount = Int(self.clusteringProgress * 20)
            if estimatedAlbumCount > self.processedAlbumCount {
                self.processedAlbumCount = estimatedAlbumCount
            }
        }
        
        do {
            // Start the clustering process
            let photoGroups = await withCheckedContinuation { continuation in
                clusteringManager.processEntireLibrary { groups in
                    continuation.resume(returning: groups)
                }
            }
            
            // Stop the progress timer on the main thread
            progressTimer.invalidate()
            self.photoGroups = photoGroups
            self.isClusteringInProgress = false
            self.clusteringProgress = 1.0
            self.processedAlbumCount = photoGroups.count // Set actual count
            
            // Set flag to indicate we have clustering results
            self.hasClusteringResults = true
            
            // Show completion toast
            self.toast?.showSuccess("Processed \(photoGroups.count) albums from \(self.photoManager.allAssets.count) photos", duration: 2.0)
            
            // Update the UI with the new photo groups
            self.updateUIWithPhotoGroups(photoGroups)
        } catch {
            // Handle any errors that might occur
            progressTimer.invalidate()
            self.isClusteringInProgress = false
            self.clusteringProgress = 0
            self.processedAlbumCount = 0
            
            // Show error message
            self.toast?.showError("Error processing photo library: \(error.localizedDescription)", duration: 3.0)
            print("Error processing photo library: \(error)")
        }
    }
    
    /// Update the UI with the new photo groups
    func updateUIWithPhotoGroups(_ photoGroups: [PhotoGroup]) {
        // Reset the current state
        currentPage = 1
        categorizedAlbums = [:]
        featuredAlbums = []
        
        // Convert PhotoGroup objects to SmartAlbumGroup objects
        var eventAlbums: [SmartAlbumGroup] = []
        var utilityAlbums: [SmartAlbumGroup] = []
        
        for group in photoGroups {
            // Create a SmartAlbumGroup from the PhotoGroup
            let smartAlbum = createSmartAlbumFromPhotoGroup(group)
            
            // Categorize the album based on its title
            if group.title == "Screenshots" {
                // Only include Screenshots in the utilities category
                utilityAlbums.append(smartAlbum)
            } else if !group.title.starts(with: "System") && 
                      group.title != "Maybe?" && 
                      group.title != "Deleted" &&
                      group.title != "Utilities" &&
                      group.title != "Receipts" && 
                      group.title != "Documents" && 
                      group.title != "Whiteboards" && 
                      group.title != "QR Codes" {
                // Add all non-system, non-utility albums to events
                eventAlbums.append(smartAlbum)
            }
        }
        
        // Sort event albums by date (most recent first by default)
        sortEventAlbums(&eventAlbums)
        
        // Update the categorized albums
        if !eventAlbums.isEmpty {
            categorizedAlbums["Events"] = eventAlbums
        }
        
        if !utilityAlbums.isEmpty {
            categorizedAlbums["Utilities"] = utilityAlbums
        }
        
        // Add an "All" category with only events and screenshots
        let allAlbums = eventAlbums + utilityAlbums
        if !allAlbums.isEmpty {
            categorizedAlbums["All"] = allAlbums
        }
        
        // Set featured albums (only event albums, sorted by photo count or relevance)
        // We exclude utility albums and screenshots from featured section
        let sortedForFeatured = sortAlbumsForFeatured(eventAlbums)
        featuredAlbums = Array(sortedForFeatured.prefix(5))
        
        // Update empty state
        showEmptyState = allAlbums.isEmpty
        
        // Update photo count statistics
        updatePhotoCountStatistics()
    }
    
    /// Create a SmartAlbumGroup from a PhotoGroup
    private func createSmartAlbumFromPhotoGroup(_ photoGroup: PhotoGroup) -> SmartAlbumGroup {
        // Create a new SmartAlbumGroup
        let context = PersistenceController.shared.container.viewContext
        let smartAlbum = SmartAlbumGroup(context: context)
        
        // Set properties
        smartAlbum.id = photoGroup.id
        smartAlbum.title = photoGroup.title
        smartAlbum.createdAt = photoGroup.monthDate ?? Date()
        
        // For screenshots, ensure high relevance score
        if photoGroup.title.contains("Screenshot") {
            smartAlbum.relevanceScore = 90 // High relevance for screenshots
            smartAlbum.tags = ["screenshot", "utility"]
        } else {
            smartAlbum.relevanceScore = Int32.random(in: 50...100) // Placeholder score between 50-100
            
            // Set tags based on the title
            if photoGroup.title.contains("Morning") {
                smartAlbum.tags = ["morning"]
            } else if photoGroup.title.contains("Afternoon") {
                smartAlbum.tags = ["afternoon"]
            } else if photoGroup.title.contains("Evening") {
                smartAlbum.tags = ["evening"]
            } else if photoGroup.title.contains("Night") {
                smartAlbum.tags = ["night"]
            }
        }
        
        // Set asset identifiers
        let assetIdentifiers = photoGroup.assets.map { $0.localIdentifier }
        smartAlbum.assetIds = assetIdentifiers
        
        return smartAlbum
    }
    
    /// Load a specific page of albums
    private func loadAlbumsPage(page: Int) {
        // Reload albums from CoreData to ensure we have the latest data
        smartAlbumManager.loadSmartAlbums()
        
        // Get all albums
        let allAlbums = smartAlbumManager.allSmartAlbums
        
        // Calculate start and end indices for this page
        let startIndex = (page - 1) * albumsPerPage
        let endIndex = min(startIndex + albumsPerPage, allAlbums.count)
        
        
        // Check if there are more albums to load
        hasMoreAlbums = endIndex < allAlbums.count || photoManager.allAssets.count > allAlbums.count * 10
        
        // If it's the first page, set featured albums
        if page == 1 {
            // Separate albums by type
            var eventAlbums: [SmartAlbumGroup] = []
            var otherAlbums: [SmartAlbumGroup] = []
            
            for album in allAlbums {
                // Check if this is a utility or screenshot album
                let isUtilityOrScreenshot = album.title == "Utilities" || 
                                           album.title == "Screenshots" || 
                                           album.title == "Receipts" || 
                                           album.title == "Documents" || 
                                           album.title == "Whiteboards" || 
                                           album.title == "QR Codes"
                
                if isUtilityOrScreenshot {
                    otherAlbums.append(album)
                } else {
                    eventAlbums.append(album)
                }
            }
            
            // Sort event albums by date
            sortEventAlbums(&eventAlbums)
            
            // For featured albums, only use event albums (filtered and sorted)
            let sortedForFeatured = sortAlbumsForFeatured(eventAlbums)
            featuredAlbums = Array(sortedForFeatured.prefix(5))
            
            showEmptyState = allAlbums.isEmpty
            
            // Reset categorized albums on first page
            categorizedAlbums = [:]
        }
        
        // Get albums for this page
        let pageAlbums = allAlbums.count > startIndex ? Array(allAlbums[startIndex..<endIndex]) : []
        
        // Categorize the albums for this page
        categorizeAlbumsForPage(pageAlbums)
        
        // Update photo count statistics after loading albums
        updatePhotoCountStatistics()
        
        // Show toast with album count information
        let totalAssets = photoManager.allAssets.count
        let albumsInCategories = categorizedAlbums.values.flatMap { $0 }.count
        
        Task { @MainActor [weak self] in
            self?.toast?.showSuccess("Loaded \(albumsInCategories) albums from \(totalAssets) photos", duration: 2.0)
        }
    }
    
    /// Start batch processing for large photo libraries
    private func startBatchProcessing() {
        guard !isBatchProcessing else { return }
        
        isBatchProcessing = true
        batchProcessingProgress = 0
        
        // Clear caches before starting
        photoCache.clearCache()
        
        // Show toast notification
        Task { @MainActor in
            toast?.showInfo("Processing large photo library in batches...", duration: 3.0)
        }
        
        // Start batch processing
        batchProcessor.processPhotosInBatches(assets: photoManager.allAssets) { [weak self] in
            guard let self = self else { return }
            
            // When batch processing completes, load the albums
            DispatchQueue.main.async {
                self.isLoading = false
                self.smartAlbumManager.loadSmartAlbums()
                self.featuredAlbums = self.smartAlbumManager.featuredAlbums
                self.categorizeAlbumsForPage(self.smartAlbumManager.allSmartAlbums)
                self.showEmptyState = self.smartAlbumManager.allSmartAlbums.isEmpty
                self.updatePhotoCountStatistics()
            }
        }
    }
    
    /// Cancel batch processing
    func cancelBatchProcessing() {
        if isBatchProcessing {
            batchProcessor.cancelProcessing()
            isBatchProcessing = false
            isLoading = false
            Task { @MainActor in
                toast?.showInfo("Processing cancelled", duration: 1.5)
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
    
    /// Select an album and prepare it for SwipeCardView
    func selectAlbum(_ album: SmartAlbumGroup) {
        // Set the selected album
        self.selectedAlbum = album
        
        // Get assets for this album
        let assets = album.fetchAssets()
        
        // Create a PhotoGroup from the SmartAlbumGroup
        let photoGroup = PhotoGroup(
            assets: assets,
            title: album.title,
            monthDate: nil,
            lastViewedIndex: 0
        )
        
        // Set the selected group for SwipeCardView
        self.selectedGroup = photoGroup
    }
    
    /// Generate a beautiful title for an album using the AlbumTitleGenerator
    func generateBeautifulTitle(for album: SmartAlbumGroup) -> String {
        // Safely fetch assets
        let assets = album.fetchAssets()
        
        // Guard against empty assets to prevent potential crashes
        guard !assets.isEmpty else {
            return "Photo Collection"
        }
        
        // Define utility tags with clear categories
        let utilityTags = [
            "screenshot": "Screenshots",
            "receipt": "Receipts",
            "document": "Documents",
            "text": "Text Documents",
            "handwriting": "Handwritten Notes",
            "illustration": "Illustrations",
            "drawing": "Drawings",
            "qr": "QR Codes",
            "code": "Code Snippets",
            "scan": "Scanned Items",
            "duplicate": "Duplicates",
            "import": "Imported Items"
        ]
        
        // Check if this is a utilities album based on tags
        if !album.tags.isEmpty {
            // Find matching utility tags
            var matchedUtilityTitle: String? = nil
            
            // Check for utility tags in album tags
            for tag in album.tags {
                for (utilityKey, utilityTitle) in utilityTags {
                    if tag.lowercased().contains(utilityKey.lowercased()) {
                        matchedUtilityTitle = utilityTitle
                        break
                    }
                }
                if matchedUtilityTitle != nil {
                    break
                }
            }
            
            // If we found a utility match, use the specific utility title
            if let utilityTitle = matchedUtilityTitle {
                return utilityTitle
            }
        }
        
        // For non-utility albums or if utility title generation failed, use the standard approach
        // Extract location if available (using the first few assets)
        let location = extractLocationFromAssets(assets.prefix(5))
        
        // Determine predominant time of day
        let timeOfDay = extractTimeOfDay(from: assets)
        
        // Extract date for more specific title
        let date = extractDateFromAssets(assets)
        
        // Extract dominant tags for more meaningful titles
        let dominantTags = extractDominantTags(from: album.tags)
        
        // Generate a beautiful title with more specific information
        return AlbumTitleGenerator.generate(
            location: location,
            timeOfDay: timeOfDay,
            photoCount: assets.count,
            date: date,
            tags: dominantTags
        )
    }
    
    /// Extract a meaningful date string from assets
    private func extractDateFromAssets(_ assets: [PHAsset]) -> String? {
        // Safety check - only use for albums with recent photos (last 3 months)
        guard let firstAsset = assets.first, 
              let creationDate = firstAsset.creationDate,
              creationDate > Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date() else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        
        return dateFormatter.string(from: creationDate)
    }
    
    /// Extract the most meaningful tags from an album
    private func extractDominantTags(from tags: [String]) -> [String] {
        // Safety check - if there are no tags or too few, return empty array
        guard !tags.isEmpty, tags.count >= 2 else {
            return []
        }
        
        // Define categories of meaningful tags
        let meaningfulTagCategories = [
            "event": ["wedding", "birthday", "party", "graduation", "concert", "festival"],
            "activity": ["hiking", "swimming", "skiing", "biking", "running", "camping"],
            "food": ["dinner", "lunch", "breakfast", "brunch", "coffee", "restaurant"],
            "travel": ["vacation", "trip", "journey", "tour", "adventure"],
            "people": ["family", "friends", "children", "baby", "group"]
        ]
        
        var dominantTags: [String] = []
        
        // Find the most meaningful tags
        for tag in tags {
            for (_, categoryTags) in meaningfulTagCategories {
                if categoryTags.contains(where: { tag.lowercased().contains($0) }) {
                    dominantTags.append(tag)
                    if dominantTags.count >= 2 {
                        return dominantTags
                    }
                    break
                }
            }
        }
        
        // If we couldn't find meaningful tags in our categories, just return the first two tags
        if dominantTags.isEmpty && tags.count >= 2 {
            return Array(tags.prefix(2))
        }
        
        return dominantTags
    }
    
    /// Update the photo count statistics
    func updatePhotoCountStatistics() {
        // Update total photo count from all assets
        totalPhotoCount = photoManager.allAssets.count
        
        // Safety check - if there are no assets, set counts to 0
        guard totalPhotoCount > 0 else {
            discoveredPhotoCount = 0
            return
        }
        
        // Use a set to track unique asset IDs and prevent duplicates
        var uniqueAssetIds = Set<String>()
        
        // Only count each photo once, even if it appears in multiple albums
        for (categoryName, albumGroup) in categorizedAlbums {
            // Skip the "All" category to prevent double-counting
            if categoryName == "All" { continue }
            
            for album in albumGroup {
                let assets = album.fetchAssets()
                for asset in assets {
                    uniqueAssetIds.insert(asset.localIdentifier)
                }
            }
        }
        
        // Update discovered photo count with unique photos only
        discoveredPhotoCount = uniqueAssetIds.count
        
        // Log the updated statistics
        print("📊 Photo Statistics: \(discoveredPhotoCount) of \(totalPhotoCount) photos in albums")
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
            case 17..<24:
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
    
    /// Categorize albums for a specific page, preserving existing categories
    private func categorizeAlbumsForPage(_ pageAlbums: [SmartAlbumGroup]) {
        var categorized: [String: [SmartAlbumGroup]] = [:]
        
        // Group albums by category
        for (categoryName, predicate) in categories {
            let matchingAlbums = pageAlbums.filter(predicate)
            if !matchingAlbums.isEmpty {
                categorized[categoryName] = matchingAlbums
            }
        }
        
        // Add an "All" category if we have albums
        if !pageAlbums.isEmpty {
            categorized["All"] = pageAlbums
        }
        
        self.categorizedAlbums = categorized
        
        // Update photo count statistics after categorization
        updatePhotoCountStatistics()
    }
    
    // Sort albums for featured section based on user preference
    private func sortAlbumsForFeatured(_ albums: [SmartAlbumGroup]) -> [SmartAlbumGroup] {
        // Filter out screenshots and utility albums
        let filteredAlbums = albums.filter { album in
            // Exclude screenshot albums
            !album.title.contains("Screenshot")
        }
        
        return filteredAlbums.sorted { album1, album2 in
            if featuredSortByMostPhotos {
                // Sort by photo count (most photos first)
                return album1.assetIds.count > album2.assetIds.count
            } else {
                // Sort by relevance score
                return album1.relevanceScore > album2.relevanceScore
            }
        }
    }
    
    // Sort event albums based on the selected sort option
    private func sortEventAlbums(_ albums: inout [SmartAlbumGroup]) {
        albums.sort { album1, album2 in
            switch eventsSortOption {
            case .newestFirst:
                return album1.createdAt > album2.createdAt
            case .oldestFirst:
                return album1.createdAt < album2.createdAt
            case .mostPhotos:
                return album1.assetIds.count > album2.assetIds.count
            case .mostRelevant:
                return album1.relevanceScore > album2.relevanceScore
            }
        }
    }
    
    // Set the event sort option and resort
    func setEventSortOption(_ option: EventSortOption) {
        guard eventsSortOption != option else { return }
        
        isSortingEvents = true
        
        // Use a small delay to allow the UI to update with spinner
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            self.eventsSortOption = option
            
            // If we have events in categories, resort them
            if var eventAlbums = self.categorizedAlbums["Events"] {
                self.sortEventAlbums(&eventAlbums)
                self.categorizedAlbums["Events"] = eventAlbums
            }
            
            self.isSortingEvents = false
        }
    }
    
    // Toggle featured albums sort order
    func toggleFeaturedSortOrder() {
        isSortingFeatured = true
        
        // Use a small delay to allow the UI to update with spinner
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            self.featuredSortByMostPhotos.toggle()
            
            // Re-sort featured albums
            let allAlbums = self.categorizedAlbums.values.flatMap { $0 }
            if !allAlbums.isEmpty {
                let sortedForFeatured = self.sortAlbumsForFeatured(allAlbums)
                self.featuredAlbums = Array(sortedForFeatured.prefix(5))
            }
            
            self.isSortingFeatured = false
        }
    }
    
    // New simplified implementation that just reprocesses the library
    func loadMoreAlbums() {
        // For our clustering-based approach, "load more" just reprocesses the entire library 
        // using time and location metadata to create optimized photo groups
        Task { @MainActor in
            await processEntireLibrary()
        }
    }
} 
