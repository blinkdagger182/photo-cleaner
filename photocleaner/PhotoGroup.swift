import Foundation
import Photos

struct PhotoGroup: Identifiable {
    let id: String // stored, not computed
    let title: String
    let assets: [PHAsset]
    let monthDate: Date


    var thumbnailAsset: PHAsset? {
        assets.first
    }

    init(assets: [PHAsset], title: String, monthDate: Date) {
        self.title = title
        self.assets = assets
        self.id = title // assign title as ID
        self.monthDate = monthDate

    }
}
struct YearGroup: Identifiable {
    let id: Int
    let year: Int
    let months: [PhotoGroup]
}
