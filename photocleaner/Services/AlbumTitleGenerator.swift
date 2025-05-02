import Foundation
import Photos
import CoreLocation

/// A generator for creating warm, human-like titles for smart albums based on location, time of day, and photo count.
struct AlbumTitleGenerator {
    
    // MARK: - Public Methods
    
    /// Generates a beautiful, human-like title for a smart album based on provided metadata.
    /// - Parameters:
    ///   - location: Optional location name (e.g., "Genting", "KL", "Ampang")
    ///   - timeOfDay: Optional time of day ("morning", "afternoon", "evening", "night")
    ///   - photoCount: Optional number of photos in the album
    ///   - date: Optional date string for the album
    ///   - tags: Optional array of dominant tags for the album
    /// - Returns: A warm, personal album title
    static func generate(location: String?, timeOfDay: String?, photoCount: Int?, date: String? = nil, tags: [String]? = nil) -> String {
        // Safety check - ensure we have at least some data to work with
        let hasLocation = location != nil && !(location?.isEmpty ?? true)
        let hasTimeOfDay = timeOfDay != nil && !(timeOfDay?.isEmpty ?? true)
        let hasDate = date != nil && !(date?.isEmpty ?? true)
        let hasTags = tags != nil && !(tags?.isEmpty ?? true)
        
        // Select appropriate template category based on available information
        var templates: [String]
        
        // Use a more conservative approach to template selection to prevent crashes
        if hasTags && hasLocation && tagLocationTemplates.count > 0 {
            // Tags + location
            templates = tagLocationTemplates
        } else if hasTags && tagTemplates.count > 0 {
            // Just tags
            templates = tagTemplates
        } else if hasLocation && hasTimeOfDay && locationTimeTemplates.count > 0 {
            // Location + time
            templates = locationTimeTemplates
        } else if hasLocation && locationTemplates.count > 0 {
            // Just location
            templates = locationTemplates
        } else if hasTimeOfDay && timeTemplates.count > 0 {
            // Just time
            templates = timeTemplates
        } else if hasDate && dateTemplates.count > 0 {
            // Just date
            templates = dateTemplates
        } else {
            // Fallback to general templates
            templates = generalTemplates
        }
        
        // Select a random template
        guard let template = templates.randomElement() else {
            return "Beautiful moments"
        }
        
        // Fill in the template with the available information
        var title = template
        
        // Only replace placeholders if they exist in the template
        // Replace location placeholder if available
        if let location = location, !location.isEmpty, title.contains("{location}") {
            title = title.replacingOccurrences(of: "{location}", with: location)
        }
        
        // Replace time placeholder if available
        if let timeOfDay = timeOfDay, !timeOfDay.isEmpty, title.contains("{time}") {
            // Capitalize the first letter of the time of day
            let capitalizedTimeOfDay = timeOfDay.prefix(1).uppercased() + timeOfDay.dropFirst()
            title = title.replacingOccurrences(of: "{time}", with: capitalizedTimeOfDay)
        }
        
        // Replace photo count if available
        if let photoCount = photoCount, title.contains("{count}") {
            title = title.replacingOccurrences(of: "{count}", with: "\(photoCount)")
        }
        
        // Replace date if available
        if let date = date, !date.isEmpty, title.contains("{date}") {
            title = title.replacingOccurrences(of: "{date}", with: date)
        }
        
        // Replace tag if available
        if let tags = tags, !tags.isEmpty, let primaryTag = tags.first, title.contains("{tag}") {
            // Capitalize the first letter of the tag
            let capitalizedTag = primaryTag.prefix(1).uppercased() + primaryTag.dropFirst()
            title = title.replacingOccurrences(of: "{tag}", with: capitalizedTag)
            
            // If we have a second tag, add it as well - but only if it makes sense
            if tags.count > 1, let secondaryTag = tags.dropFirst().first {
                // Only add the second tag if it's not already in the title and if we're not using a date template
                if !title.lowercased().contains(secondaryTag.lowercased()) && !title.contains("{date}") {
                    title = title + " & " + secondaryTag.capitalized
                }
            }
        }
        
        // Safety check - if we still have any placeholder patterns, remove them
        let placeholderPattern = #"\{[^\}]+\}"#
        if let regex = try? NSRegularExpression(pattern: placeholderPattern, options: []) {
            title = regex.stringByReplacingMatches(in: title, options: [], range: NSRange(location: 0, length: title.utf16.count), withTemplate: "")
        }
        
        // Adjust for singular/plural based on photo count if needed
        if let photoCount = photoCount {
            if photoCount == 1 {
                title = title.replacingOccurrences(of: "memories", with: "memory")
                title = title.replacingOccurrences(of: "days", with: "day")
                title = title.replacingOccurrences(of: "adventures", with: "adventure")
                title = title.replacingOccurrences(of: "stories", with: "story")
            }
        }
        
        return title
    }
    
    // MARK: - Private Template Collections
    
    // Templates that include both location and time
    private static let locationTimeTemplates: [String] = [
        "{time} adventures in {location}",
        "{time} moments in {location}",
        "{time} strolls through {location}",
        "{time} vibes in {location}",
        "{time} memories in {location}",
        "{time} stories from {location}",
        "{time} escapes to {location}",
        "{time} wanderings in {location}",
        "{time} explorations around {location}",
        "Beautiful {time} in {location}",
        "Peaceful {time} in {location}",
        "Dreamy {time} in {location}",
        "Cozy {time} in {location}",
        "Vibrant {time} in {location}",
        "Quiet {time} in {location}",
        "Lively {time} in {location}",
        "Serene {time} in {location}",
        "Enchanting {time} in {location}",
        "Nostalgic {time} in {location}"
    ]
    
    // Templates that include only location
    private static let locationTemplates: [String] = [
        "Moments in {location} 🌟",
        "Adventures in {location} 🗺️",
        "Memories from {location} 📷",
        "Exploring {location} 🔍",
        "{location} collection 📱",
        "Scenes from {location} 🏙️",
        "Captured in {location} 📸",
        "Discovering {location} 🌈",
        "{location} memories 💫",
        "A day in {location} 🌅"
    ]
    
    // Templates that include only time of day
    private static let timeTemplates: [String] = [
        "Beautiful {time} moments ✨",
        "{time} memories 📷",
        "{time} vibes 🌈",
        "Captured {time} moments 📸",
        "{time} collection 📱",
        "{time} adventures 🌅",
        "Magical {time} ✨",
        "{time} scenes 🏙️",
        "Wonderful {time} 💫",
        "{time} memories to cherish 💖"
    ]
    
    // General templates (no location or time)
    private static let generalTemplates: [String] = [
        "Beautiful moments ✨",
        "Captured memories 📷",
        "Photo collection 📱",
        "Special moments 💫",
        "Memorable times 🌟",
        "Life snapshots 📸",
        "Cherished memories 💖",
        "Moments to remember 🌈",
        "Photo highlights 🔍",
        "Wonderful memories 🌅"
    ]
    
    /// Templates for when we have specific tags
    private static let tagTemplates = [
        "{tag} moments ✨",
        "{tag} memories 📷",
        "{tag} collection 📱",
        "My {tag} album 🌟",
        "{tag} highlights 🔍",
        "Captured {tag} moments 📸",
        "{tag} adventures 🌅",
        "Special {tag} memories 💫",
        "{tag} times 🌈"
    ]
    
    /// Templates for when we have both tags and location
    private static let tagLocationTemplates = [
        "{tag} in {location} 🌟",
        "{tag} moments in {location} ✨",
        "{location} {tag} collection 📱",
        "{tag} adventures in {location} 🌅",
        "Captured {tag} in {location} 📸",
        "{location} {tag} memories 💫"
    ]
    
    /// Templates for when we have a specific date
    private static let dateTemplates = [
        "{date} memories 📆",
        "Photos from {date} 📸",
        "{date} collection 📱",
        "Moments from {date} 📅",
        "{date} highlights 🌟",
        "Captured on {date} 📷"
    ]
    
    // Malaysian-specific templates
    private static let malaysianTemplates: [String] = [
        "Mamak adventures in {location}",
        "Hawker delights in {location}",
        "Teh tarik moments in {location}",
        "Pasar malam treasures in {location}",
        "Kampung memories in {location}",
        "Tropical paradise in {location}",
        "Rainforest wonders in {location}",
        "Island escapes to {location}",
        "Heritage walks in {location}",
        "Street food hunts in {location}",
        "Durian season in {location}",
        "Monsoon memories in {location}",
        "Kopitiam mornings in {location}",
        "Batik beauty in {location}",
        "Festive celebrations in {location}",
        "Cultural treasures of {location}",
        "Laksa cravings in {location}",
        "Nasi lemak breakfasts in {location}",
        "Roti canai mornings in {location}",
        "Satay nights in {location}",
        "Merdeka celebrations in {location}",
        "Hari Raya gatherings in {location}",
        "Chinese New Year in {location}",
        "Deepavali lights in {location}",
        "Gong Xi Fa Cai in {location}"
    ]
    
    // Family and relationship templates
    private static let relationshipTemplates: [String] = [
        "Family laughter in {location}",
        "Cousins gathering at {location}",
        "Sibling adventures in {location}",
        "Grandma's stories in {location}",
        "Family reunion in {location}",
        "Weekend with loved ones in {location}",
        "Birthday celebrations in {location}",
        "Anniversary memories in {location}",
        "Friendship tales in {location}",
        "Coffee dates in {location}",
        "Romantic getaway to {location}",
        "Quiet moments with you in {location}",
        "Love stories in {location}",
        "Together in {location}",
        "Holding hands in {location}",
        "First date memories in {location}",
        "Wedding joy in {location}",
        "Baby steps in {location}",
        "Growing up in {location}",
        "Home sweet home in {location}"
    ]
    
    // Activity-based templates
    private static let activityTemplates: [String] = [
        "Hiking adventures in {location}",
        "Beach days in {location}",
        "Roadtrip to {location}",
        "Shopping spree in {location}",
        "Foodie adventures in {location}",
        "Cafe hopping in {location}",
        "Museum visits in {location}",
        "Concert night in {location}",
        "Movie date in {location}",
        "Picnic day in {location}",
        "Cycling through {location}",
        "Swimming at {location}",
        "Camping under stars in {location}",
        "Fishing trip to {location}",
        "Photography walk in {location}",
        "Art exploration in {location}",
        "Cooking adventures in {location}",
        "Garden strolls in {location}",
        "Market wanderings in {location}",
        "Festival fun in {location}"
    ]
    
    // Seasonal and weather templates
    private static let seasonalTemplates: [String] = [
        "Rainy day in {location}",
        "Sunny afternoon in {location}",
        "Misty morning in {location}",
        "Stormy skies over {location}",
        "Foggy views of {location}",
        "Sunset magic in {location}",
        "Sunrise beauty in {location}",
        "Rainbow sightings in {location}",
        "Cloudy day in {location}",
        "Starry night in {location}",
        "Moonlit walks in {location}",
        "Autumn colors in {location}",
        "Spring blooms in {location}",
        "Summer heat in {location}",
        "Winter chill in {location}",
        "Monsoon season in {location}",
        "Golden hour in {location}",
        "Blue hour in {location}",
        "First light at {location}",
        "Last light at {location}"
    ]
}

// MARK: - Extension for Smart Album Integration
extension AlbumTitleGenerator {
    
    /// Generates a title for a smart album based on metadata extracted from PHAssets
    /// - Parameters:
    ///   - assets: Array of PHAssets in the album
    ///   - tags: Optional array of classification tags
    /// - Returns: A warm, personal album title
    static func generateFromAssets(_ assets: [PHAsset], tags: [String]? = nil) -> String {
        // Extract location if available
        let location = extractLocationName(from: assets)
        
        // Extract time of day from creation dates
        let timeOfDay = extractTimeOfDay(from: assets)
        
        // Use the basic generator with extracted metadata
        return generate(location: location, timeOfDay: timeOfDay, photoCount: assets.count)
    }
    
    /// Extracts a location name from a collection of assets
    /// - Parameter assets: Array of PHAssets to analyze
    /// - Returns: Most common location name if available
    private static func extractLocationName(from assets: [PHAsset]) -> String? {
        // Count occurrences of each location
        var locationCounts: [String: Int] = [:]
        
        for asset in assets {
            if let location = asset.location?.name {
                locationCounts[location, default: 0] += 1
            }
        }
        
        // Find the most common location
        return locationCounts.max(by: { $0.value < $1.value })?.key
    }
    
    /// Extracts the predominant time of day from asset creation dates
    /// - Parameter assets: Array of PHAssets to analyze
    /// - Returns: String representing the time of day
    private static func extractTimeOfDay(from assets: [PHAsset]) -> String? {
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
}

// MARK: - PHAsset Extension for Location Name
private extension PHAsset {
    /// A computed property that attempts to extract a human-readable location name
    var location: (name: String, coordinate: CLLocationCoordinate2D)? {
        guard let location = self.location else { return nil }
        
        // Return the coordinate for now - actual geocoding will be done by GeocodeService
        return ("Unknown Location", location.coordinate)
    }
}

// MARK: - Geocode Service for Reverse Geocoding
class GeocodeService {
    // Singleton instance
    static let shared = GeocodeService()
    
    // Geocoder instance
    private let geocoder = CLGeocoder()
    
    // Cache for geocoding results to avoid redundant API calls
    private var locationCache: [String: String] = [:]
    
    /// Get a human-readable location name from coordinates
    /// - Parameters:
    ///   - coordinate: The coordinates to reverse geocode
    ///   - completion: Closure called with the location name
    func getLocationName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
        // Create a cache key from the coordinates (rounded to reduce cache misses for nearby locations)
        let cacheKey = String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
        
        // Check if we have a cached result
        if let cachedName = locationCache[cacheKey] {
            completion(cachedName)
            return
        }
        
        // Create a CLLocation from the coordinates
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        // Perform reverse geocoding
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self, error == nil, let placemark = placemarks?.first else {
                completion(nil)
                return
            }
            
            // Extract the most specific and meaningful location name
            var locationName: String? = nil
            
            // Try to get the most specific name possible
            if let name = placemark.name, !name.isEmpty {
                locationName = name
            } else if let locality = placemark.locality {
                locationName = locality
            } else if let area = placemark.administrativeArea {
                locationName = area
            } else if let country = placemark.country {
                locationName = country
            }
            
            // Cache the result
            if let name = locationName {
                self.locationCache[cacheKey] = name
            }
            
            completion(locationName)
        }
    }
    
    /// Get location names for a batch of assets
    /// - Parameters:
    ///   - assets: Array of assets to process
    ///   - completion: Closure called when all geocoding is complete
    func batchGetLocationNames(for assets: [PHAsset], completion: @escaping (String?) -> Void) {
        // Filter assets with location data
        let assetsWithLocation = assets.compactMap { asset -> CLLocationCoordinate2D? in
            return asset.location?.coordinate
        }
        
        if assetsWithLocation.isEmpty {
            completion(nil)
            return
        }
        
        // Find the center point of all locations
        let totalLat = assetsWithLocation.reduce(0.0) { $0 + $1.latitude }
        let totalLng = assetsWithLocation.reduce(0.0) { $0 + $1.longitude }
        let avgLat = totalLat / Double(assetsWithLocation.count)
        let avgLng = totalLng / Double(assetsWithLocation.count)
        
        // Get location name for the center point
        getLocationName(for: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng), completion: completion)
    }
}
