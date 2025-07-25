import SwiftUI
import Photos
import UIKit
import PhotosUI

// Custom view that mimics ContentUnavailableView but works on iOS 16
struct FallbackContentUnavailableView: View {
    let title: String
    let systemImage: String
    let description: Text?
    
    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            if let description = description {
                description
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    
    var body: some View {
        Group {
            switch photoManager.authorizationStatus {
            case .notDetermined:
                RequestAccessView {
                    Task {
                        await photoManager.requestAuthorization()
                    }
                }

            case .authorized, .limited:
                if photoManager.photoGroups.isEmpty && photoManager.isLoadingInitialData {
                    // Show loading state for progressive loading rather than empty state
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        Text("Loading your photos...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("This may take a moment for large libraries")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else if photoManager.photoGroups.isEmpty && !photoManager.isLoadingInitialData {
                    // Empty library state
                    FallbackContentUnavailableView("No Photos",
                                           systemImage: "photo.on.rectangle",
                                           description: Text("Your photo library is empty or we don't have access to any photos"))
                } else {
                    // Show main UI as soon as we have some data
                    PhotoGroupView(photoManager: photoManager)
                        .environmentObject(photoManager)
                        .environmentObject(toast)
                        .overlay(
                            // Show subtle loading indicator when background loading is happening
                            photoManager.isLoadingCompleteLibrary ? 
                            VStack {
                                Spacer()
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading complete library...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .padding()
                            }
                            : nil,
                            alignment: .bottom
                        )
                }

            case .denied, .restricted:
                FallbackContentUnavailableView("No Access to Photos",
                                       systemImage: "lock.fill",
                                       description: Text("Please enable photo access in Settings"))
                .overlay(
                    Button("Open Settings") {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.primary.opacity(0.9))
                    .foregroundColor(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20),
                    alignment: .bottom
                )

            @unknown default:
                EmptyView()
            }
        }
    }
}

struct RequestAccessView: View {
    let onRequest: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 50))
            Text("Photo Access Required")
                .font(.title)
            Text("This app needs access to your photos to help you clean up similar photos")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Grant Access") {
                onRequest()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct LimitedAccessView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @StateObject private var viewModel = LimitedAccessViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // 🔔 Banner: Only viewing selected photos
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You're viewing only selected photos.")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Button(action: {
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let root = scene.windows.first?.rootViewController {
                                viewModel.openPhotoLibraryPicker(from: root)
                            }
                        }) {
                            Text("Add More Photos")
                                .font(.subheadline)
                                .bold()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // 📸 Section header
                    sectionHeader(title: "Selected Photos")

                    let group = viewModel.createPhotoGroup(with: photoManager.allAssets)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        LimitedAccessAlbumCell(group: group, viewModel: viewModel)
                            .onTapGesture {
                                viewModel.selectedGroup = group
                            }
                    }
                    .padding()
                }
            }

        }
        .sheet(item: $viewModel.selectedGroup) { group in
            SwipeCardView(group: group, forceRefresh: $viewModel.forceRefresh)
                .environmentObject(photoManager)
                .environmentObject(toast)
        }
        .onAppear {
            print("👀 LimitedAccessView is visible")
            viewModel.onAppear()
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
}

@MainActor
class LimitedAccessViewModel: ObservableObject {
    @Published var selectedGroup: PhotoGroup?
    @Published var forceRefresh = false
    
    func onAppear() {
        // Any initialization logic that needs to happen when the view appears
    }
    
    func openPhotoLibraryPicker(from viewController: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
    }
    
    func createPhotoGroup(with assets: [PHAsset]) -> PhotoGroup {
        return PhotoGroup(
            id: UUID(),
            assets: assets,
            title: "Selected Photos",
            monthDate: nil
        )
    }
}

// Add a specialized AlbumCell for LimitedAccessView after the LimitedAccessViewModel class
struct LimitedAccessAlbumCell: View {
    let group: PhotoGroup
    @State private var thumbnail: UIImage?
    let viewModel: LimitedAccessViewModel
    
    init(group: PhotoGroup, viewModel: LimitedAccessViewModel) {
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
