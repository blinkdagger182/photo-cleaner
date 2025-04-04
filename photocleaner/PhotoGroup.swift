import Foundation
import Photos

struct PhotoGroup: Identifiable {
    let id: UUID
    let title: String
    let assets: [PHAsset]
    let monthDate: Date?  // ✅ Optional for system albums like "Deleted", "Saved"

    var thumbnailAsset: PHAsset? {
        assets.first
    }

    init(id: UUID = UUID(), assets: [PHAsset], title: String, monthDate: Date?) {
        self.id = id
        self.title = title
        self.assets = assets
        self.monthDate = monthDate
    }

    // For month albums (safe default for non-system groups)
    init(assets: [PHAsset], title: String, creationDate: Date) {
        self.id = UUID()
        self.title = title
        self.assets = assets
        self.monthDate = creationDate
    }

    func copy(withAssets assets: [PHAsset]) -> PhotoGroup {
        return PhotoGroup(id: self.id, assets: assets, title: self.title, monthDate: self.monthDate)
    }
}



struct YearGroup: Identifiable {
    let id: Int
    let year: Int
    let months: [PhotoGroup]
}
