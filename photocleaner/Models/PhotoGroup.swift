import Foundation
import Photos

struct PhotoGroup: Identifiable {
    let id: UUID
    let assets: [PHAsset]
    let assetsDict: [String: PHAsset]  // Dictionary with asset.localIdentifier as key
    let assetOrder: [String]  // Preserve the original order of assets
    let title: String
    let monthDate: Date?
    var lastViewedIndex: Int = 0

    var thumbnailAsset: PHAsset? {
        assets.first
    }

    func copy(withAssets newAssets: [PHAsset]) -> PhotoGroup {
        // Create a new PhotoGroup instance with the same properties but updated assets
        return PhotoGroup(
            id: id,
            assets: newAssets,
            title: title,
            monthDate: monthDate,
            lastViewedIndex: lastViewedIndex
        )
    }

    init(id: UUID = UUID(), assets: [PHAsset], title: String, monthDate: Date?, lastViewedIndex: Int = 0) {
        self.id = id
        self.assets = assets
        self.assetsDict = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        self.assetOrder = assets.map { $0.localIdentifier }
        self.title = title
        self.monthDate = monthDate
        self.lastViewedIndex = lastViewedIndex
    }
    
    // Access an asset by index using the ordered array
    func asset(at index: Int) -> PHAsset? {
        guard index >= 0 && index < assetOrder.count else { return nil }
        let identifier = assetOrder[index]
        return assetsDict[identifier]
    }
    
    // Total count of assets
    var count: Int {
        return assetOrder.count
    }
}

struct YearGroup: Identifiable {
    let id: Int
    let year: Int
    let months: [PhotoGroup]
} 