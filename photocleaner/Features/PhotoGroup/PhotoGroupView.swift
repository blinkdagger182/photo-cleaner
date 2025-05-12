import SwiftUI
import Photos
import UIKit

struct PhotoGroupView: View {
    @StateObject private var viewModel: PhotoGroupViewModel
    @EnvironmentObject var toast: ToastService
    @EnvironmentObject var photoManager: PhotoManager
    @State private var showPermissionDeniedAlert = false
    @State private var isRefreshing = false
    
    // Track scroll offset for banner dismissal
    @State private var scrollPosition: CGFloat = 0
    @State private var previousScrollPosition: CGFloat = 0
    @State private var scrollDirectionDown = false
    var onScroll: ((CGFloat) -> Void)? = nil
    
    // State for navigation to SwipeCardView
    @State private var selectedGroup: PhotoGroup? = nil
    @State private var isShowingSwipeCard = false
    @State private var albumCoverImage: UIImage? = nil
    
    init(photoManager: PhotoManager, onScroll: ((CGFloat) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PhotoGroupViewModel(photoManager: photoManager))
        self.onScroll = onScroll
    }

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.authorizationStatus == .denied {
                    PermissionDeniedView(onRequestAccess: {
                        viewModel.openPhotoLibraryPicker(from: UIApplication.shared.windows.first!.rootViewController!)
                    }, onOpenSettings: {
                        viewModel.openSettings()
                    })
                } else if viewModel.authorizationStatus == .limited {
                    PhotoGroupLimitedAccessView(onRequestAccess: {
                        viewModel.openPhotoLibraryPicker(from: UIApplication.shared.windows.first!.rootViewController!)
                    })
                } else if viewModel.yearGroups.isEmpty {
                    VStack {
                        Spacer()
                        Text("No photos found")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        if viewModel.viewByYear {
                            ForEach(viewModel.yearGroups, id: \.id) { yearGroup in
                                VStack(alignment: .leading) {
                                    Text("\(yearGroup.year)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal)
                                    
                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(yearGroup.months, id: \.id) { group in
                                            Button {
                                                // Check for high-quality cached image first
                                                let cachedImage = AlbumHighQualityCache.shared.getCachedFirstImage(for: group)
                                                
                                                // If we have a cached image, use it directly
                                                if let cachedImage = cachedImage {
                                                    viewModel.updateSelectedGroup(group)
                                                    selectedGroup = group
                                                    albumCoverImage = cachedImage
                                                    isShowingSwipeCard = true
                                                } else {
                                                    // If no cached image, use the high-priority loading method
                                                    // This ensures we get the best quality image as quickly as possible
                                                    AlbumHighQualityCache.shared.preloadFirstImageWithHighPriority(for: group) { image in
                                                        viewModel.updateSelectedGroup(group)
                                                        selectedGroup = group
                                                        albumCoverImage = image
                                                        isShowingSwipeCard = true
                                                    }
                                                }
                                            } label: {
                                                AlbumCell(group: group, viewModel: viewModel)
                                            }
                                            .buttonStyle(ScaleButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(viewModel.photoGroups, id: \.id) { group in
                                    Button {
                                        // Check for high-quality cached image first
                                        let cachedImage = AlbumHighQualityCache.shared.getCachedFirstImage(for: group)
                                        
                                        // If we have a cached image, use it directly
                                        if let cachedImage = cachedImage {
                                            viewModel.updateSelectedGroup(group)
                                            selectedGroup = group
                                            albumCoverImage = cachedImage
                                            isShowingSwipeCard = true
                                        } else {
                                            // If no cached image, use the high-priority loading method
                                            // This ensures we get the best quality image as quickly as possible
                                            AlbumHighQualityCache.shared.preloadFirstImageWithHighPriority(for: group) { image in
                                                viewModel.updateSelectedGroup(group)
                                                selectedGroup = group
                                                albumCoverImage = image
                                                isShowingSwipeCard = true
                                            }
                                        }
                                    } label: {
                                        AlbumCell(group: group, viewModel: viewModel)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                    .background(GeometryReader { proxy -> Color in
                        DispatchQueue.main.async {
                            scrollPosition = proxy.frame(in: .named("scroll")).minY
                            scrollDirectionDown = scrollPosition > previousScrollPosition
                            previousScrollPosition = scrollPosition
                            onScroll?(scrollPosition)
                        }
                        return Color.clear
                    })
                }
            }
            .coordinateSpace(name: "scroll")
            .refreshable {
                isRefreshing = true
                await viewModel.refreshPhotoLibrary()
                isRefreshing = false
            }
            .navigationTitle("Albums")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation {
                            viewModel.toggleViewMode()
                        }
                    } label: {
                        Image(systemName: viewModel.viewByYear ? "rectangle.grid.1x2" : "rectangle.stack")
                            .imageScale(.large)
                    }
                }
            }
            .onAppear {
                viewModel.triggerFadeInAnimation()
                
                // Pre-cache first images for all albums when the view appears
                Task {
                    await photoManager.preCacheFirstImages()
                }
            }
            .sheet(isPresented: $isShowingSwipeCard) {
                if let group = selectedGroup {
                    SwipeCardView(
                        group: group,
                        forceRefresh: $viewModel.shouldForceRefresh,
                        initialThumbnail: albumCoverImage
                    )
                    .environmentObject(photoManager)
                    .environmentObject(toast)
                }
            }
        }
    }
}

struct PermissionDeniedView: View {
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Photo Library Access Required")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("To help you organize and clean your photo library, we need permission to access your photos.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            
            Button(action: onRequestAccess) {
                Text("Allow Access")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .foregroundColor(.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary, lineWidth: 1)
                    )
                    .cornerRadius(16)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            
            Button(action: onOpenSettings) {
                Text("Open Settings")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(24)
        .padding(24)
    }
}

struct PhotoGroupLimitedAccessView: View {
    let onRequestAccess: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You're viewing only selected photos.")
                .font(.subheadline)
                .foregroundColor(.primary)

            Button("Add More Photos") {
                onRequestAccess()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
        .padding()
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct AlbumCell: View {
    let group: PhotoGroup
    @State private var thumbnail: UIImage?
    let viewModel: PhotoGroupViewModel
    
    init(group: PhotoGroup, viewModel: PhotoGroupViewModel) {
        self.group = group
        self.viewModel = viewModel
    }

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

            Text("\(group.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: UIScreen.main.bounds.width / 2 - 30, alignment: .leading)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        do {
            // First check if we have a high-quality cached image
            // Use try-catch for error handling
            if let cachedImage = try? AlbumHighQualityCache.shared.getCachedFirstImage(for: group) {
                await MainActor.run {
                    self.thumbnail = cachedImage
                }
                return
            }
            
            // Otherwise load the thumbnail as before
            if let asset = group.thumbnailAsset {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = true
                
                let size = CGSize(width: 300, height: 300)
                
                let result = await withCheckedContinuation { continuation in
                    // Add a flag to ensure continuation is only resumed once
                    var hasResumed = false
                    
                    PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: size,
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        // Only resume if we haven't already
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(returning: image)
                        }
                    }
                }
                
                if let result = result {
                    await MainActor.run {
                        self.thumbnail = result
                    }
                }
            }
        } catch {
            print("Error loading thumbnail: \(error)")
        }
    }
}
