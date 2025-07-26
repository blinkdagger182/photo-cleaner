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
        VStack(alignment: .leading, spacing: 8) {
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
            
            // Album title with fixed height for 2 lines
            Text(album.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
            
            // Photo count
            Text("\(album.fetchAssets().count) photos")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 180)
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
            // Cover image or placeholder with no inner padding
            ZStack(alignment: .bottomLeading) {
                if let asset = album.fetchAssets().first {
                    HighQualityAssetImage(asset: asset, size: CGSize(width: 340, height: 220), contentMode: .fill)
                        .frame(width: 340, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 340, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Gradient overlay for text readability
                LinearGradient(
                    gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.7)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 340, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 4)
            
            // Album title
            Text(album.title)
                .font(.headline)
                .fontWeight(.medium)
                .lineLimit(2)
                .padding(.top, 8)
                .padding(.horizontal, 8)
            
            // Photo count
            Text("\(album.fetchAssets().count) photos")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
        .frame(width: 350)
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
