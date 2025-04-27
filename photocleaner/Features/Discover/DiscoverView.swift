import SwiftUI
import Photos

struct DiscoverView: View {
    @StateObject private var viewModel: DiscoverViewModel
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    
    @State private var forceRefresh = false
    
    init(photoManager: PhotoManager) {
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(photoManager: photoManager))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                // Only show content if we have albums or are generating
                if !viewModel.showEmptyState || viewModel.isGenerating {
                    VStack(spacing: 24) {
                        // Header with "CLN" logo
                        HStack {
                            Text("Discover")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Image("CLN")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 40)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        // Featured albums carousel
                        if !viewModel.featuredAlbums.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Featured Albums")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(viewModel.featuredAlbums, id: \.id) { album in
                                            FeaturedAlbumCard(album: album)
                                                .onTapGesture {
                                                    viewModel.selectedAlbum = album
                                                }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        // Categories
                        ForEach(Array(viewModel.categorizedAlbums.keys.sorted()), id: \.self) { category in
                            if let albums = viewModel.categorizedAlbums[category], !albums.isEmpty && category != "All" {
                                CategorySection(
                                    title: category,
                                    albums: albums,
                                    onTap: { album in
                                        viewModel.selectedAlbum = album
                                    }
                                )
                            }
                        }
                    }
                    .padding(.bottom, 32)
                } else {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                            .padding(.top, 60)
                        
                        Text("Discover Smart Albums")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Create smart albums based on your photos. We'll analyze them and group them into meaningful collections.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                        
                        Button(action: {
                            viewModel.generateAlbums()
                        }) {
                            Text("Generate Albums")
                                .fontWeight(.semibold)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 32)
                }
            }
            .overlay(
                Group {
                    if viewModel.isGenerating {
                        VStack {
                            Spacer()
                            
                            HStack {
                                Spacer()
                                
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                    
                                    Text("Generating albums...")
                                        .font(.headline)
                                    
                                    Text("This may take a moment")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(24)
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .shadow(radius: 10)
                                
                                Spacer()
                            }
                            
                            Spacer()
                        }
                        .background(Color.black.opacity(0.4))
                        .edgesIgnoringSafeArea(.all)
                    }
                }
            )
            .refreshable {
                viewModel.loadAlbums()
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.showEmptyState {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            viewModel.generateAlbums()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(viewModel.isGenerating)
                    }
                }
            }
        }
        .sheet(item: $viewModel.selectedAlbum) { album in
            SmartAlbumDetailView(album: album, forceRefresh: $forceRefresh)
                .environmentObject(photoManager)
                .environmentObject(toast)
        }
        .overlay(
            // Show "load more" button at the bottom when there are already some albums
            VStack {
                Spacer()
                if !viewModel.showEmptyState && !viewModel.isGenerating && !viewModel.allSmartAlbums.isEmpty {
                    Button(action: {
                        viewModel.generateMoreAlbums()
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Generate More Albums")
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.bottom, 20)
                    }
                }
            }
        )
        .onAppear {
            // Refresh albums when view appears
            viewModel.loadAlbums()
        }
    }
}

// MARK: - Featured Album Card
struct FeaturedAlbumCard: View {
    let album: SmartAlbumGroup
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 280, height: 200)
                        .clipped()
                        .cornerRadius(16)
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [.clear, .black.opacity(0.5)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .cornerRadius(16)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 280, height: 200)
                        .overlay(
                            ProgressView()
                                .scaleEffect(1.2)
                        )
                }
                
                // Score badge
                VStack {
                    HStack {
                        Spacer()
                        
                        Text("\(album.relevanceScore)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(6)
                            .background(scoreColor(for: album.relevanceScore))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                }
                .padding(8)
            }
            
            // Title
            Text(album.title)
                .font(.headline)
                .lineLimit(1)
            
            // Photo count
            Text("\(album.assetIds.count) photos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 280)
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard let thumbnailAsset = album.thumbnailAsset() else { return }
        
        // First load a lower quality thumbnail quickly for immediate display
        await loadQuickThumbnail(for: thumbnailAsset)
        
        // Then load a high-quality version
        await loadHighQualityThumbnail(for: thumbnailAsset)
    }
    
    private func loadQuickThumbnail(for asset: PHAsset) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        
        var hasResumed = false
        
        let result = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !hasResumed else { return }
                
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = (info?[PHImageErrorKey] != nil)
                
                if cancelled || hasError {
                    return
                }
                
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
        
        if let result = result {
            await MainActor.run {
                self.thumbnail = result
            }
        }
    }
    
    private func loadHighQualityThumbnail(for asset: PHAsset) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        
        var hasResumed = false
        
        let result = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1200, height: 1200),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !hasResumed else { return }
                
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = (info?[PHImageErrorKey] != nil)
                
                if cancelled || hasError {
                    return
                }
                
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
        
        if let result = result {
            await MainActor.run {
                self.thumbnail = result
            }
        }
    }
    
    private func scoreColor(for score: Int32) -> Color {
        switch score {
        case 0..<40:
            return .gray
        case 40..<60:
            return .blue
        case 60..<80:
            return .purple
        default:
            return .pink
        }
    }
}

// MARK: - Category Section
struct CategorySection: View {
    let title: String
    let albums: [SmartAlbumGroup]
    let onTap: (SmartAlbumGroup) -> Void
    
    let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(albums, id: \.id) { album in
                    SmartAlbumCell(album: album)
                        .onTapGesture {
                            onTap(album)
                        }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Smart Album Cell
struct SmartAlbumCell: View {
    let album: SmartAlbumGroup
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 120)
                        .overlay(
                            ProgressView()
                        )
                }
            }
            .frame(height: 120)
            
            // Title
            Text(album.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            
            // Photo count
            Text("\(album.assetIds.count) photos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard let thumbnailAsset = album.thumbnailAsset() else { return }
        
        // First load a lower quality thumbnail quickly for immediate display
        await loadQuickThumbnail(for: thumbnailAsset)
        
        // Then load a high-quality version
        await loadHighQualityThumbnail(for: thumbnailAsset)
    }
    
    private func loadQuickThumbnail(for asset: PHAsset) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        
        var hasResumed = false
        
        let result = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !hasResumed else { return }
                
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = (info?[PHImageErrorKey] != nil)
                
                if cancelled || hasError {
                    return
                }
                
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
        
        if let result = result {
            await MainActor.run {
                self.thumbnail = result
            }
        }
    }
    
    private func loadHighQualityThumbnail(for asset: PHAsset) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        
        var hasResumed = false
        
        let result = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 800, height: 800),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !hasResumed else { return }
                
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = (info?[PHImageErrorKey] != nil)
                
                if cancelled || hasError {
                    return
                }
                
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
        
        if let result = result {
            await MainActor.run {
                self.thumbnail = result
            }
        }
    }
}

// MARK: - Smart Album Detail View
struct SmartAlbumDetailView: View {
    let album: SmartAlbumGroup
    @Binding var forceRefresh: Bool
    
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    
    @Environment(\.dismiss) private var dismiss
    @State private var photoGroup: PhotoGroup?
    
    var body: some View {
        NavigationStack {
            Group {
                if let photoGroup = photoGroup {
                    SwipeCardView(group: photoGroup, forceRefresh: $forceRefresh)
                        .environmentObject(photoManager)
                        .environmentObject(toast)
                } else {
                    ProgressView("Loading photos...")
                }
            }
            .navigationTitle(album.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Convert SmartAlbumGroup to PhotoGroup for the SwipeCardView
            let assets = album.fetchAssets()
            photoGroup = PhotoGroup(
                assets: assets,
                title: album.title,
                monthDate: nil
            )
        }
    }
} 
