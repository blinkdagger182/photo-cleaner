import SwiftUI
import Photos

struct DeletePreviewView: View {
    @ObservedObject var viewModel: DeletePreviewViewModel
    @Environment(\.dismiss) private var dismiss
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Are you sure you want to delete these \(viewModel.entries.count) photos?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding()
                
                Text("This will permanently delete photos from your device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(viewModel.entries) { entry in
                            ImageThumbnail(asset: entry.asset)
                                .frame(height: 100)
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    
                    Button(action: {
                        viewModel.confirmDeletion()
                        dismiss()
                    }) {
                        Text("Delete")
                            .bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("Delete Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ImageThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.3)
                ProgressView()
            }
        }
        .task {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            self.image = image
        }
    }
} 