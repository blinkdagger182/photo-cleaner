import SwiftUI
import Photos
import CoreLocation

struct DiscoverView: View {
    @StateObject private var viewModel: DiscoverViewModel
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    
    @State private var forceRefresh = false
    @State private var showTitleGeneratorTest = false
    
    init(photoManager: PhotoManager) {
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(photoManager: photoManager))
    }
    
    // Connect toast service when view appears
    private func connectToastService() {
        viewModel.toast = toast
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
                                AlbumCategorySection(
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
                            Text("Generate Smart Albums")
                                .padding()
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
                                        .padding()
                                    
                                    Text("Generating Smart Albums...")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("This may take a moment")
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(24)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(16)
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
                viewModel.loadAlbums(forceRefresh: true)
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.showEmptyState {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(action: {
                                viewModel.loadAlbums(forceRefresh: true)
                            }) {
                                Label("Refresh Albums", systemImage: "arrow.clockwise")
                            }
                            .disabled(viewModel.isGenerating)
                            
                            Button(action: {
                                // Present the title generator test view
                                showTitleGeneratorTest = true
                            }) {
                                Label("Test Title Generator", systemImage: "sparkles")
                            }
                            
                            Button(action: {
                                // Regenerate titles for existing albums
                                self.regenerateAlbumTitles()
                            }) {
                                Label("Regenerate Album Titles", systemImage: "wand.and.stars")
                            }
                            .disabled(viewModel.isGenerating || viewModel.allSmartAlbums.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(item: $viewModel.selectedAlbum) { album in
            SmartAlbumDetailView(album: album, forceRefresh: $forceRefresh)
                .environmentObject(photoManager)
                .environmentObject(toast)
        }
        .sheet(isPresented: $showTitleGeneratorTest) {
            AlbumTitleGeneratorTests()
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
            // Connect toast service and refresh albums when view appears
            connectToastService()
            viewModel.loadAlbums()
        }
    }
}

// MARK: - Album Category Section
struct AlbumCategorySection: View {
    let title: String
    let albums: [SmartAlbumGroup]
    let onTap: (SmartAlbumGroup) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(albums, id: \.id) { album in
                        AlbumCard(album: album)
                            .onTapGesture {
                                onTap(album)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Featured Album Card
struct FeaturedAlbumCard: View {
    let album: SmartAlbumGroup
    
    @State private var thumbnail: UIImage?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack(alignment: .bottomLeading) {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                
                // Gradient overlay for text visibility
                LinearGradient(
                    gradient: Gradient(colors: [
                        .black.opacity(0.7),
                        .black.opacity(0.3),
                        .clear
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 100)
                
                // Title and photo count overlay
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    Text("\(album.assetIds.count) photos")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(16)
            }
            .frame(width: 280, height: 280)
            .cornerRadius(16)
            .clipped()
            .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
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
                targetSize: CGSize(width: 600, height: 600),
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
}

// MARK: - Album Card
struct AlbumCard: View {
    let album: SmartAlbumGroup
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: 160, height: 160)
            .cornerRadius(12)
            .clipped()
            
            // Title
            Text(album.title)
                .font(.headline)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
            
            // Photo count
            Text("\(album.assetIds.count) photos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 160)
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
                    SwipeCardView(group: photoGroup, forceRefresh: $forceRefresh, isDiscoverTab: true)
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

// MARK: - DiscoverView Extensions
extension DiscoverView {
    // Function to regenerate titles for existing albums
    func regenerateAlbumTitles() {
        guard !viewModel.allSmartAlbums.isEmpty else { return }
        
        // Show loading toast
        toast.show("Regenerating album titles...", duration: 2.0)
        
        // Process in background to avoid UI freeze
        DispatchQueue.global(qos: .userInitiated).async {
            // Get the persistent container
            let context = PersistenceController.shared.container.viewContext
            
            // Process each album
            for album in viewModel.allSmartAlbums {
                // Generate a new title
                let newTitle = viewModel.generateBeautifulTitle(for: album)
                
                // Update the album title
                DispatchQueue.main.async {
                    album.title = newTitle
                    
                    // Save changes
                    do {
                        try context.save()
                    } catch {
                        print("❌ Failed to save updated album title: \(error)")
                    }
                }
            }
            
            // Show completion toast
            DispatchQueue.main.async {
                viewModel.loadAlbums() // Refresh the UI
                toast.show("Album titles regenerated!", duration: 2.0)
            }
        }
    }
}
