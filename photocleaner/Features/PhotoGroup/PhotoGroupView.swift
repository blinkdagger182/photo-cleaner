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
                    ScrollDetector(
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
                                if viewModel.yearGroups.isEmpty {
                                    noPhotosView
                                } else {
                                    ForEach(viewModel.yearGroups) { yearGroup in
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text("\(yearGroup.year)")
                                                .font(.title)
                                                .bold()
                                                .padding(.horizontal)

                                            LazyVGrid(columns: columns, spacing: 16) {
                                                ForEach(yearGroup.months, id: \.id) { group in
                                                    Button {
                                                        viewModel.updateSelectedGroup(group)
                                                    } label: {
                                                        AlbumCell(group: group)
                                                    }
                                                    .buttonStyle(ScaleButtonStyle())
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 16) {
                                    sectionHeader(title: "My Albums")
                                    
                                    // Debug view to print album names
                                    Color.clear
                                        .frame(width: 0, height: 0)
                                        .onAppear {
                                            print("DEBUG: Available albums:")
                                            for group in viewModel.photoGroups {
                                                print("- \(group.title) (\(group.count) photos)")
                                            }
                                        }
                                    
                                    let filteredGroups = viewModel.photoGroups.filter { $0.title == "Maybe?" }
                                    
                                    if filteredGroups.isEmpty {
                                        noPhotosView
                                    } else {
                                        LazyVGrid(columns: columns, spacing: 20) {
                                            ForEach(filteredGroups, id: \.id) { group in
                                                Button {
                                                    viewModel.updateSelectedGroup(group)
                                                } label: {
                                                    AlbumCell(group: group)
                                                }
                                                .buttonStyle(ScaleButtonStyle())
                                            }
                                        }
                                        .padding(.horizontal)
                                    }

                                    Spacer(minLength: 40)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
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
