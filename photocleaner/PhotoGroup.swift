import Foundation
import Photos

struct PhotoGroup: Identifiable {
    let id: UUID
    let assets: [PHAsset]
    let title: String
    let monthDate: Date?
    var lastViewedIndex: Int = 0

    var thumbnailAsset: PHAsset? {
        assets.first
    }

    func copy(withAssets newAssets: [PHAsset]) -> PhotoGroup {
        PhotoGroup(id: id, assets: newAssets, title: title, monthDate: monthDate, lastViewedIndex: lastViewedIndex)
    }

    init(id: UUID = UUID(), assets: [PHAsset], title: String, monthDate: Date?, lastViewedIndex: Int = 0) {
        self.id = id
        self.assets = assets
        self.title = title
        self.monthDate = monthDate
        self.lastViewedIndex = lastViewedIndex
    }
}

struct YearGroup: Identifiable {
    let id: Int
    let year: Int
    let months: [PhotoGroup]
}
