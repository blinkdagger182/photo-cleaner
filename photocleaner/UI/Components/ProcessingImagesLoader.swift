import SwiftUI

/// A beautiful full-screen loader that displays a skeleton animation
/// while the app processes and organizes albums.
///
/// This implementation is a lightweight wrapper around the SkeletonLoaderView
/// to maintain backward compatibility with existing code.
struct ProcessingImagesLoader: View {
    // MARK: - Properties
    
    var progress: Double
    var totalPhotoCount: Int
    var processedAlbumCount: Int
    
    // MARK: - Body
    
    var body: some View {
        SkeletonLoaderView(
            progress: progress, 
            totalPhotoCount: totalPhotoCount, 
            processedAlbumCount: processedAlbumCount
        )
    }
}

// MARK: - Preview

struct ProcessingImagesLoader_Previews: PreviewProvider {
    static var previews: some View {
        ProcessingImagesLoader(
            progress: 0.65,
            totalPhotoCount: 1250,
            processedAlbumCount: 12
        )
    }
} 