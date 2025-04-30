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
    /// - Returns: A warm, personal album title
    static func generate(location: String?, timeOfDay: String?, photoCount: Int?) -> String {
        // Select appropriate template category based on available information
        let templates: [String]
        
        if let location = location, !location.isEmpty {
            if let timeOfDay = timeOfDay, !timeOfDay.isEmpty {
                // Both location and time available
                templates = locationTimeTemplates
            } else {
                // Only location available
                templates = locationTemplates
            }
        } else if let timeOfDay = timeOfDay, !timeOfDay.isEmpty {
            // Only time available
            templates = timeTemplates
        } else {
            // Neither location nor time available
            templates = generalTemplates
        }
        
        // Select a random template
        guard let template = templates.randomElement() else {
            return "Beautiful moments"
        }
        
        // Fill in the template with the available information
        var title = template
        
        // Replace location placeholder if available
        if let location = location, !location.isEmpty {
            title = title.replacingOccurrences(of: "{location}", with: location)
        }
        
        // Replace time placeholder if available
        if let timeOfDay = timeOfDay, !timeOfDay.isEmpty {
            title = title.replacingOccurrences(of: "{time}", with: timeOfDay)
        }
        
        // Adjust for singular/plural based on photo count if needed
        if let photoCount = photoCount {
            if photoCount == 1 {
                title = title.replacingOccurrences(of: "moments", with: "moment")
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
        "Adventures in {location}",
        "Wandering through {location}",
        "Exploring {location}",
        "Memories from {location}",
        "Moments in {location}",
        "Days in {location}",
        "Life in {location}",
        "Discovering {location}",
        "Hidden gems in {location}",
        "Streets of {location}",
        "The heart of {location}",
        "Escape to {location}",
        "Journey through {location}",
        "Treasures of {location}",
        "Beauty of {location}",
        "Scenes from {location}",
        "Impressions of {location}",
        "Glimpses of {location}",
        "Reflections of {location}",
        "Stories from {location}",
        "Postcards from {location}",
        "Souvenirs from {location}",
        "Wanderlust in {location}",
        "Lost in {location}",
        "Found in {location}"
    ]
    
    // Templates that include only time of day
    private static let timeTemplates: [String] = [
        "Golden {time} light",
        "{time} reflections",
        "{time} stories",
        "{time} adventures",
        "{time} moments to remember",
        "{time} dreams",
        "Peaceful {time} hours",
        "Magical {time} light",
        "Quiet {time} thoughts",
        "Gentle {time} breeze",
        "Soft {time} shadows",
        "Warm {time} glow",
        "{time} wanderings",
        "{time} whispers",
        "{time} serenity",
        "{time} escapes",
        "Cherished {time} moments",
        "Precious {time} memories",
        "Stolen {time} moments",
        "Perfect {time} bliss",
        "{time} treasures",
        "Embracing the {time}",
        "Dancing in the {time}",
        "Chasing {time} light",
        "Lost in {time} thoughts"
    ]
    
    // General templates (no location or time)
    private static let generalTemplates: [String] = [
        "Captured moments",
        "Life's little treasures",
        "Memories to cherish",
        "Snapshots of joy",
        "Beautiful memories",
        "Moments that matter",
        "Pieces of happiness",
        "Stories worth telling",
        "Fragments of time",
        "Collected memories",
        "Precious moments",
        "Timeless memories",
        "Cherished moments",
        "Stolen moments",
        "Little joys",
        "Simple pleasures",
        "Quiet moments",
        "Treasured memories",
        "Moments of wonder",
        "Glimpses of happiness",
        "Whispers of joy",
        "Echoes of laughter",
        "Traces of happiness",
        "Slices of life",
        "Chapters of joy"
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
        
        // For simplicity, we're just returning the coordinate's description
        // In a real app, you would use CLGeocoder to get the actual place name
        return ("Unknown Location", location.coordinate)
    }
}
