import Foundation
import Photos

struct PhotoGroup: Identifiable {
    let id: UUID
    let assets: [PHAsset]
    
    var thumbnailAsset: PHAsset? {
        assets.first
    }

    var creationDate: Date? {
        assets.first?.creationDate
    }

    init(id: UUID = UUID(), assets: [PHAsset]) {
        self.id = id
        self.assets = assets
    }
}
