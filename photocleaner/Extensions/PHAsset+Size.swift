import Photos

extension PHAsset {
    func fetchEstimatedAssetSize() async -> Int {
        return await withCheckedContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            
            self.requestContentEditingInput(with: options) { input, _ in
                if let input = input, let fileSize = input.fullSizeImageURL?.fileSize {
                    continuation.resume(returning: fileSize)
                } else {
                    // Fallback to the older method if needed
                    let resources = PHAssetResource.assetResources(for: self)
                    let size = resources.first?.value(forKey: "fileSize") as? Int ?? 0
                    continuation.resume(returning: size)
                }
            }
        }
    }
    
    var estimatedAssetSize: Int {
        // This is the property that causes warnings - for backward compatibility
        let resources = PHAssetResource.assetResources(for: self)
        return resources.first?.value(forKey: "fileSize") as? Int ?? 0
    }
}

extension URL {
    var fileSize: Int {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.size] as? Int ?? 0
        } catch {
            return 0
        }
    }
}
