import SwiftUI
import Photos
import UIKit

/// A high quality image view that loads PHAsset thumbnails with better resolution
/// Uses async/await pattern with continuation for proper handling of PHImageManager callbacks
struct HighQualityAssetImage: View {
    let asset: PHAsset
    let size: CGSize
    let contentMode: ContentMode
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    init(asset: PHAsset, size: CGSize, contentMode: ContentMode = .fill) {
        self.asset = asset
        self.size = size
        self.contentMode = contentMode
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
        }
        .task {
            await loadHighQualityThumbnail()
        }
    }
    
    private func loadHighQualityThumbnail() async {
        // Configure image request options for high quality
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        // Use larger target size for better quality
        // Scale based on screen scale for proper resolution
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: min(size.width * scale, 600),
            height: min(size.height * scale, 600)
        )
        
        // Track if we've already resumed to prevent multiple resumes
        var hasResumed = false
        
        do {
            image = await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: contentMode == .fill ? .aspectFill : .aspectFit,
                    options: options
                ) { result, info in
                    // Guard against multiple resume calls
                    guard !hasResumed else { return }
                    
                    // Check for cancellation or errors
                    let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    let hasError = (info?[PHImageErrorKey] != nil)
                    
                    if cancelled || hasError {
                        // PHImageManager will call again with the final result
                        return
                    }
                    
                    // Mark as resumed and return the image
                    hasResumed = true
                    continuation.resume(returning: result)
                }
            }
        } catch {
            print("Error loading high quality thumbnail: \(error)")
        }
        
        isLoading = false
    }
}
