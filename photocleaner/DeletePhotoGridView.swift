import SwiftUI
import Photos

struct DeletePhotoGridView: View {
    @Binding var entries: [DeletePreviewEntry]
    @Binding var selectedEntries: Set<UUID>
    @EnvironmentObject var coordinator: AppCoordinator

    let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(entries, id: \.id) { entry in
                    let isSelected = selectedEntries.contains(entry.id)
                    AssetImageView(asset: entry.asset)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipped()
                        .overlay(
                            isSelected ? Color.black.opacity(0.25) : Color.clear
                        )
                        .overlay(
                            isSelected ? Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .padding(6) : nil,
                            alignment: .topTrailing
                        )
                        .onTapGesture {
                            if isSelected {
                                selectedEntries.remove(entry.id)
                            } else {
                                selectedEntries.insert(entry.id)
                            }
                        }
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}

// A reusable view to load an image from a PHAsset
struct AssetImageView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 300, height: 300),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let image = result {
                self.image = image
            }
        }
    }
}
