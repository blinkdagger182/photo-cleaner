import Photos
import SwiftUI

// MARK: - PHAsset Extensions
extension PHAsset {
    /// Checks if the asset is a Live Photo
    var isLivePhoto: Bool {
        return mediaSubtypes.contains(.photoLive)
    }
    
    /// Returns the icon name for the asset type (useful for UI indicators)
    var typeIconName: String {
        if isLivePhoto {
            return "livephoto"
        } else if mediaType == .video {
            return "video.fill"
        } else {
            return "photo"
        }
    }
    
    /// Returns the duration of a video or Live Photo in a readable format
    var durationText: String? {
        guard duration > 0 else { return nil }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        
        return formatter.string(from: duration)
    }
    
    /// Attempts to get the file size of the asset
    func getFileSize(completion: @escaping (Int64?) -> Void) {
        // Most backward compatible approach using PHImageManager
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .fastFormat
        options.resizeMode = .none
        
        // Use the standard requestImageData method available on older iOS versions
        manager.requestImageData(for: self, options: options) { (data, _, _, _) in
            if let data = data {
                completion(Int64(data.count))
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - Cache Extension for PHCachingImageManager
extension PHCachingImageManager {
    /// Optimized method to request a Live Photo with proper caching
    func requestCachedLivePhoto(for asset: PHAsset, 
                               targetSize: CGSize,
                               contentMode: PHImageContentMode,
                               options: PHLivePhotoRequestOptions,
                               resultHandler: @escaping (PHLivePhoto?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
        
        // Start caching the asset
        startCachingImages(for: [asset], targetSize: targetSize, contentMode: contentMode, options: nil)
        
        // Request the live photo
        return requestLivePhoto(for: asset, targetSize: targetSize, contentMode: contentMode, options: options, resultHandler: { livePhoto, info in
            // Deliver the result
            resultHandler(livePhoto, info)
            
            // If we got a valid result, stop caching this specific asset to save memory
            if livePhoto != nil {
                self.stopCachingImages(for: [asset], targetSize: targetSize, contentMode: contentMode, options: nil)
            }
        })
    }
} 