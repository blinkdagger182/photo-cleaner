import Photos

extension PHAsset {
    // Cache for asset sizes to reduce repeated requests
    private static var sizeCache: [String: Int] = [:]
    
    func fetchEstimatedAssetSize() async -> Int {
        // Check cache first
        if let cachedSize = PHAsset.sizeCache[self.localIdentifier], cachedSize > 0 {
            return cachedSize
        }
        
        return await withCheckedContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            
            self.requestContentEditingInput(with: options) { input, _ in
                var size = 0
                if let input = input, let fileSize = input.fullSizeImageURL?.fileSize {
                    size = fileSize
                } else {
                    // Fallback to the older method if needed
                    let resources = PHAssetResource.assetResources(for: self)
                    size = resources.first?.value(forKey: "fileSize") as? Int ?? 0
                }
                
                // Cache the result
                if size > 0 {
                    PHAsset.sizeCache[self.localIdentifier] = size
                }
                
                continuation.resume(returning: size)
            }
        }
    }
    
    var estimatedAssetSize: Int {
        // Check cache first
        if let cachedSize = PHAsset.sizeCache[self.localIdentifier], cachedSize > 0 {
            return cachedSize
        }
        
        // This is the property that causes warnings - for backward compatibility
        let resources = PHAssetResource.assetResources(for: self)
        let size = resources.first?.value(forKey: "fileSize") as? Int ?? 0
        
        // Cache the result
        if size > 0 {
            PHAsset.sizeCache[self.localIdentifier] = size
        }
        
        return size
    }
    
    // Clear cache if needed (e.g. on memory warning)
    static func clearSizeCache() {
        sizeCache.removeAll()
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
