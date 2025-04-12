import SwiftUI
import Photos

struct AlbumCell: View {
    let group: PhotoGroup
    @State private var thumbnail: UIImage?
    
    private let photoManager = PhotoManager.shared

    var body: some View {
        VStack(alignment: .leading) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.1)
                    ProgressView()
                }
            }
            .frame(width: UIScreen.main.bounds.width / 2 - 30, height: 120)
            .clipped()
            .cornerRadius(8)

            Text(group.title)
                .font(.subheadline)
                .lineLimit(1)

            Text("\(group.assets.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: UIScreen.main.bounds.width / 2 - 30, alignment: .leading)
        .task {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        photoManager.fetchAlbumCoverImage(for: group) { image in
            self.thumbnail = image
        }
    }
} 