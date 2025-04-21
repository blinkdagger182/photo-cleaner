import SwiftUI
import Photos

struct DeletePreviewEntry: Identifiable, Equatable, Hashable {
    let id = UUID()
    let asset: PHAsset
    let image: UIImage
    let fileSize: Int

    static func == (lhs: DeletePreviewEntry, rhs: DeletePreviewEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 