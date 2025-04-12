import Photos
import UIKit

extension PHAsset {
    func getImageSize() -> CGSize {
        return CGSize(width: self.pixelWidth, height: self.pixelHeight)
    }
}

//import Photos
//
//extension PHAsset {
//    var estimatedAssetSize: Int {
//        let resources = PHAssetResource.assetResources(for: self)
//        return resources.first?.value(forKey: "fileSize") as? Int ?? 0
//    }
//}
