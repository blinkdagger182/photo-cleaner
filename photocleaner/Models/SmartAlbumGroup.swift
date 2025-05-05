import Foundation
import CoreData
import Photos

// MARK: - Core Data model for SmartAlbumGroup
class SmartAlbumGroup: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var createdAt: Date
    @NSManaged public var relevanceScore: Int32
    @NSManaged public var tagsData: Data?
    @NSManaged public var assetIdsData: Data?
    @NSManaged public var thumbnailId: String?
    
    // Computed properties for transformable attributes
    var tags: [String] {
        get {
            guard let data = tagsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            tagsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    var assetIds: [String] {
        get {
            guard let data = assetIdsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            assetIdsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    // Fetch request
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SmartAlbumGroup> {
        return NSFetchRequest<SmartAlbumGroup>(entityName: "SmartAlbumGroup")
    }
    
    // Helper method to get PHAssets for this album
    func fetchAssets() -> [PHAsset] {
        // Create fetch options with chronological sort
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: self.assetIds, options: fetchOptions)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { (asset, _, _) in
            assets.append(asset)
        }
        
        // If fetchResult doesn't respect our sort order (which can happen with fetchAssets(withLocalIdentifiers:)),
        // sort the assets array manually by creation date
        return assets.sorted { first, second in
            guard let date1 = first.creationDate, let date2 = second.creationDate else {
                // If either has no date, put the one with a date first
                return first.creationDate != nil
            }
            return date1 < date2  // Ascending order (oldest first)
        }
    }
    
    // Helper to get thumbnail asset
    func thumbnailAsset() -> PHAsset? {
        // First try to get the designated thumbnail asset
        if let thumbnailId = thumbnailId, !thumbnailId.isEmpty {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [thumbnailId], options: nil)
            if let asset = result.firstObject {
                return asset
            }
        }
        
        // Fallback to the first asset in the album if thumbnailId is invalid or nil
        if !assetIds.isEmpty {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetIds[0]], options: nil)
            return result.firstObject
        }
        
        return nil
    }
    
    // Core Data validation
    public override func validateForInsert() throws {
        try super.validateForInsert()
        
        // Debug log for validation
        print("Validating album: id=\(String(describing: id)), title=\(String(describing: title)), createdAt=\(String(describing: createdAt))")
        
        // Check for nil attributes first
        if self.title == nil {
            throw NSError(domain: "SmartAlbumGroup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Title is nil"])
        }
        
        if self.id == nil {
            throw NSError(domain: "SmartAlbumGroup", code: 2, userInfo: [NSLocalizedDescriptionKey: "ID is nil"])
        }
        
        if self.createdAt == nil {
            throw NSError(domain: "SmartAlbumGroup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Creation date is nil"])
        }
        
        // Validate title
        if title.isEmpty {
            // Fix empty title rather than throwing an error
            self.title = "Photos from \(Date().formatted(.dateTime.month().day().year()))"
            print("✅ Fixed empty title for album")
        }
        
        // Validate ID
        if id == UUID.init(uuidString: "00000000-0000-0000-0000-000000000000") {
            // Fix invalid UUID
            self.id = UUID()
            print("✅ Fixed invalid UUID for album")
        }
        
        // Ensure tagsData exists
        if tagsData == nil {
            // Create default tags data
            do {
                self.tagsData = try JSONEncoder().encode(["Photos"])
                print("✅ Fixed missing tags data for album")
            } catch {
                throw NSError(domain: "SmartAlbumGroup", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to encode default tags: \(error.localizedDescription)"])
            }
        }
        
        // Ensure assetIdsData exists
        if assetIdsData == nil {
            throw NSError(domain: "SmartAlbumGroup", code: 5, userInfo: [NSLocalizedDescriptionKey: "Asset IDs data is missing"])
        }
        
        // Validate thumbnailId
        if thumbnailId == nil || thumbnailId!.isEmpty {
            // Try to fix missing thumbnail ID
            if let firstAssetId = assetIds.first {
                self.thumbnailId = firstAssetId
                print("✅ Fixed missing thumbnail ID for album")
            } else {
                throw NSError(domain: "SmartAlbumGroup", code: 6, userInfo: [NSLocalizedDescriptionKey: "Thumbnail ID and asset IDs are both missing"])
            }
        }
        
        // Validate that decoded values are valid
        do {
            let tagCount = tags.count
            let assetCount = assetIds.count
            
            if assetCount == 0 {
                throw NSError(domain: "SmartAlbumGroup", code: 7, userInfo: [NSLocalizedDescriptionKey: "No asset IDs found after decoding"])
            }
            
            print("✅ Validation successful: \(tagCount) tags, \(assetCount) assets")
        } catch {
            throw NSError(domain: "SmartAlbumGroup", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to validate decoded data: \(error.localizedDescription)"])
        }
    }
}

// MARK: - Preview helper
extension SmartAlbumGroup {
    static var preview: SmartAlbumGroup {
        let viewContext = PersistenceController.preview.container.viewContext
        let album = SmartAlbumGroup(context: viewContext)
        album.id = UUID()
        album.title = "Beach day 🏖️"
        album.createdAt = Date()
        album.relevanceScore = 85
        album.tags = ["beach", "ocean", "sunset"]
        album.assetIds = ["example-asset-id-1", "example-asset-id-2"]
        album.thumbnailId = "example-asset-id-1"
        return album
    }
} 