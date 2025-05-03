import SwiftUI
import Photos

// Import the high quality image component

/// A simple fallback album view that uses SwiftUI LazyVGrid instead of UIKit
/// This is used as a fallback when the optimized components cause rendering issues
struct FallbackAlbumGrid: View {
    // Albums to display
    var albums: [SmartAlbumGroup]
    
    // Callback when an album is selected
    var onAlbumSelected: (SmartAlbumGroup) -> Void
    
    // Grid layout
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(albums) { album in
                FallbackAlbumCell(album: album)
                    .onTapGesture {
                        onAlbumSelected(album)
                    }
            }
        }
        .padding(.horizontal)
    }
}

/// A simple album cell that uses SwiftUI instead of UIKit
struct FallbackAlbumCell: View {
    let album: SmartAlbumGroup
    
    var body: some View {
        VStack(alignment: .leading) {
            // Cover image or placeholder
            ZStack {
                if let asset = album.fetchAssets().first {
                    HighQualityAssetImage(asset: asset, size: CGSize(width: 180, height: 120))
                        .frame(height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 120)
                }
                
                // Gradient overlay for text readability
                LinearGradient(
                    gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.7)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .cornerRadius(8)
            
            // Album title
            Text(album.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .padding(.top, 4)
            
            // Photo count
            Text("\(album.fetchAssets().count) photos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 160)
    }
}

/// A simple carousel that uses SwiftUI instead of UIKit
struct FallbackFeaturedCarousel: View {
    // Albums to display
    var albums: [SmartAlbumGroup]
    
    // Callback when an album is selected
    var onAlbumSelected: (SmartAlbumGroup) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(albums) { album in
                    FallbackFeaturedCell(album: album)
                        .onTapGesture {
                            onAlbumSelected(album)
                        }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// A featured album cell that uses SwiftUI instead of UIKit
struct FallbackFeaturedCell: View {
    let album: SmartAlbumGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Create an image container with proper aspect ratio and dimensions
            if let asset = album.fetchAssets().first {
                // Use larger size to ensure high quality
                HighQualityAssetImage(asset: asset, size: CGSize(width: 800, height: 600), contentMode: .fill)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 340, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 2)
                    .overlay(
                        // Gradient overlay for text readability
                        LinearGradient(
                            gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.7)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 340, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 2)
            }
            
            // Album title
            Text(album.title)
                .font(.headline)
                .fontWeight(.medium)
                .lineLimit(2)
                .padding(.top, 4)
            
            // Photo count
            Text("\(album.fetchAssets().count) photos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 340)
    }
}

/// A simple image view that loads PHAsset thumbnails with minimal memory usage
struct FallbackAssetImage: View {
    let asset: PHAsset
    let size: CGSize
    
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        
        // Use a very small size to prevent memory issues
        let targetSize = CGSize(width: min(size.width, 100), height: min(size.height, 100))
        
        manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                DispatchQueue.main.async {
                    self.image = result
                }
            }
        }
    }
}
