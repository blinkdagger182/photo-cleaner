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
            ZStack {
                ScrollView {
                    ScrollDetectorView(
                        yOffset: $scrollPosition,
                        onScrollDirectionChanged: { isScrollingDown in
                            // When scrolling down, notify parent
                            if isScrollingDown {
                                print("Scrolling DOWN")
                                onScroll?(-20)
                            } else {
                                print("Scrolling UP")
                                onScroll?(20)
                            }
                        }
                    )
                    
                    VStack(spacing: 0) {
                        HStack(alignment: .center) {
                            // 🟨 Left: Banner text + buttons
                            if viewModel.authorizationStatus == .limited {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("You're viewing only selected photos.")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)

                                    Button("Add More Photos") {
                                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                           let root = scene.windows.first?.rootViewController {
                                            viewModel.openPhotoLibraryPicker(from: root)
                                        }
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Go to Settings to Allow Full Access") {
                                        viewModel.openSettings()
                                    }
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.yellow.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 16)

                        // 🔄 Top Row: Picker and cln. logo
                        HStack(alignment: .bottom) {
                            Picker("View Mode", selection: $viewModel.viewByYear) {
                                Text("By Month").tag(true)
                                Text("My Albums").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity)

                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        // 📅 Main content
                        VStack(alignment: .leading, spacing: 20) {
                            if viewModel.viewByYear {
                                if viewModel.yearGroups.isEmpty && (photoManager.isLoadingInitialData || photoManager.isLoadingCompleteLibrary) {
                                    // Show skeleton loaders for year view when loading - extends beyond screen
                                    ForEach(2018...2024, id: \.self) { year in
                                        VStack(alignment: .leading, spacing: 16) {
                                            HStack {
                                                // Skeleton year title
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.2))
                                                    .frame(width: 80, height: 28)
                                                    .cornerRadius(6)
                                                    .padding(.horizontal)

                                                Spacer()
                                            }

                                            LazyVGrid(columns: columns, spacing: 16) {
                                                // Show many skeleton albums per year to fill entire screen
                                                ForEach(0..<(year >= 2023 ? 12 : year >= 2021 ? 10 : 8), id: \.self) { index in
                                                    AlbumCellSkeleton(index: index + (year - 2018) * 15)
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                } else if viewModel.yearGroups.isEmpty {
                                    // Empty state when not loading
                                    noPhotosView
                                } else {
                                    ForEach(viewModel.yearGroups, id: \.id) { yearGroup in
                                        VStack(alignment: .leading, spacing: 16) {
                                            HStack {
                                                Text("\(yearGroup.year)")
                                                    .font(.title)
                                                    .bold()
                                                    .padding(.horizontal)

                                                Spacer()
                                            }

                                            LazyVGrid(columns: columns, spacing: 16) {
                                                ForEach(yearGroup.months, id: \.id) { group in
                                                    Button {
                                                        viewModel.updateSelectedGroup(group)
                                                    } label: {
                                                        AlbumCell(group: group)
                                                    }
                                                    .buttonStyle(ScaleButtonStyle())
                                                }
                                                
                                                // Show additional skeleton loaders if still loading more for this year
                                                if photoManager.isLoadingCompleteLibrary {
                                                    ForEach(0..<8, id: \.self) { index in
                                                        AlbumCellSkeleton(index: index + yearGroup.months.count + yearGroup.year)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 16) {
                                    sectionHeader(title: "My Albums")
                                    
                                    if viewModel.filteredPhotoGroups.isEmpty {
                                        // Show skeleton loaders when loading, empty state otherwise
                                        if photoManager.isLoadingInitialData || photoManager.isLoadingCompleteLibrary {
                                            LazyVGrid(columns: columns, spacing: 20) {
                                                // Show 20 skeleton cells to completely fill the screen
                                                ForEach(0..<20, id: \.self) { index in
                                                    AlbumCellSkeleton(index: index)
                                                }
                                            }
                                            .padding(.horizontal)
                                        } else {
                                            noPhotosView
                                        }
                                    } else {
                                        LazyVGrid(columns: columns, spacing: 20) {
                                            // Show actual albums
                                            ForEach(viewModel.filteredPhotoGroups, id: \.id) { group in
                                                Button {
                                                    viewModel.updateSelectedGroup(group)
                                                } label: {
                                                    AlbumCell(group: group)
                                                }
                                                .buttonStyle(ScaleButtonStyle())
                                            }
                                            
                                            // Show additional skeleton loaders if still loading more
                                            if photoManager.isLoadingCompleteLibrary {
                                                ForEach(0..<10, id: \.self) { index in
                                                    AlbumCellSkeleton(index: index + viewModel.filteredPhotoGroups.count)
                                                }
                                            }
                                        }
                                        .padding(.horizontal)

                                    Spacer(minLength: 40)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                                    }
                .coordinateSpace(name: "scrollView")
                .refreshable {
                    await refreshPhotos()
                }
                .blur(radius: isPhotoAccessDenied ? 8 : 0)
                .overlay {
                    if isPhotoAccessDenied {
                        photoAccessDeniedView
                    }
                }
            }
        }
        .sheet(item: $viewModel.selectedGroup) { group in
            SwipeCardView(group: group, forceRefresh: $viewModel.shouldForceRefresh)
                .onAppear {
                    print("\u{1F4E4} Showing SwipeCardView for:", group.title, "Asset count:", group.count)
                }
                .environmentObject(photoManager)
                .environmentObject(toast)
        }
        .alert("Photo Access Required", isPresented: $showPermissionDeniedAlert) {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This app needs access to your photos to help you organize and clean your library. Please enable access in Settings.")
        }
    }

    private func refreshPhotos() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        await viewModel.refreshPhotoLibrary()
        
        // Show toast notification
        toast.show("Photo library refreshed", type: .success)
    }

    private var isPhotoAccessDenied: Bool {
        photoManager.authorizationStatus == .denied ||
        photoManager.authorizationStatus == .restricted ||
        photoManager.authorizationStatus == .notDetermined
    }
    
    private var photoAccessDeniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Photo Library Access Required")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
            
            Text("To help you organize and clean your photo library, we need permission to access your photos.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            
            Button(action: requestPhotoAccess) {
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
        }
        .padding(32)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(24)
        .padding(24)
    }
    
    private func requestPhotoAccess() {
        Task {
            if photoManager.authorizationStatus == .notDetermined {
                await photoManager.requestAuthorization()
                
                // Show settings alert if permission was denied
                if photoManager.authorizationStatus == .denied ||
                   photoManager.authorizationStatus == .restricted {
                    showPermissionDeniedAlert = true
                }
            } else {
                // If already denied or restricted, show settings alert
                showPermissionDeniedAlert = true
            }
        }
    }

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.title2)
                .bold()
            Spacer()
        }
        .padding(.horizontal)
    }

    private var noPhotosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No photos here")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Skeleton Loader Components

struct AlbumCellSkeleton: View {
    @State private var shimmer = false
    let index: Int
    
    init(index: Int = 0) {
        self.index = index
    }
    
    // Add some variation to make it more realistic
    private var titleWidth: CGFloat {
        [60, 85, 100, 75, 90][index % 5]
    }
    
    private var countWidth: CGFloat {
        [30, 45, 38, 42, 35][index % 5]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Skeleton thumbnail matching AlbumCell exactly
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: UIScreen.main.bounds.width / 2 - 30, height: 120)
                .overlay(
                    // Shimmer effect
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.4),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask(RoundedRectangle(cornerRadius: 8))
                    .offset(x: shimmer ? 200 : -200)
                    .animation(
                        Animation.linear(duration: 1.8)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.1),
                        value: shimmer
                    )
                )
                .clipped()
            
            // Skeleton title - matches AlbumCell text layout with variation
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .frame(width: titleWidth, height: 16)
            
            // Skeleton count - matches AlbumCell caption layout with variation
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.15))
                .frame(width: countWidth, height: 12)
        }
        .frame(width: UIScreen.main.bounds.width / 2 - 30, alignment: .leading)
        .onAppear {
            withAnimation {
                shimmer = true
            }
        }
    }
}

struct AlbumCell: View {
    let group: PhotoGroup
    @State private var thumbnail: UIImage?

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
        guard group.count > 0 else { return }

        let key = "LastViewedIndex_\(group.id.uuidString)"
        let savedIndex = UserDefaults.standard.integer(forKey: key)
        let safeIndex = min(savedIndex, group.count - 1)
        guard let asset = group.asset(at: safeIndex) else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let size = CGSize(width: 600, height: 600)
        
        // Track if we've already resumed to prevent multiple resumes
        var hasResumed = false

        thumbnail = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Guard against multiple resume calls
                guard !hasResumed else { return }
                
                // Check for cancellation or errors
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = (info?[PHImageErrorKey] != nil)
                
                if cancelled || hasError {
                    // PHImageManager will call again with the final result
                    return
                }
                
                // Mark as resumed and return the image
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
