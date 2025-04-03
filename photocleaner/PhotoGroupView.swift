
import SwiftUI
import Photos

struct PhotoGroupView: View {
    let photoGroups: [PhotoGroup]
    @State private var selectedGroup: PhotoGroup?
    @State private var showingPhotoReview = false
    
    var body: some View {
        NavigationStack {
            List(photoGroups) { group in
                PhotoGroupCell(group: group)
                    .onTapGesture {
                        selectedGroup = group
                        showingPhotoReview = true
                    }
            }
            .navigationTitle("Photo Groups")
            .sheet(isPresented: $showingPhotoReview) {
                if let group = selectedGroup {
                    SwipeCardView(group: group)
                }
            }
        }
    }
}

struct PhotoGroupCell: View {
    let group: PhotoGroup
    @State private var thumbnail: UIImage?
    
    var body: some View {
        HStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                ProgressView()
                    .frame(width: 60, height: 60)
            }
            
            VStack(alignment: .leading) {
                Text("\(group.assets.count) Photos")
                    .font(.headline)
                if let date = group.creationDate {
                    Text(date.formatted())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard let asset = group.thumbnailAsset else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        
        let size = CGSize(width: 120, height: 120)
        
        thumbnail = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
