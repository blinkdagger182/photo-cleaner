import Foundation
import Photos

struct DeletePreviewEntry: Identifiable {
    let id: UUID
    let asset: PHAsset
    
    init(id: UUID = UUID(), asset: PHAsset) {
        self.id = id
        self.asset = asset
    }
} 