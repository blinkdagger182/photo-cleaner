import SwiftUI
import Photos
import PhotosUI

struct LivePhotoView: UIViewRepresentable {
    // MARK: - Properties
    var livePhoto: PHLivePhoto?
    var isPlaying: Bool
    
    // MARK: - UIViewRepresentable
    func makeUIView(context: Context) -> PHLivePhotoView {
        print("🔵 LivePhotoView: makeUIView called")
        let livePhotoView = PHLivePhotoView()
        livePhotoView.delegate = context.coordinator
        livePhotoView.contentMode = .scaleAspectFill
        livePhotoView.clipsToBounds = true
        return livePhotoView
    }
    
    func updateUIView(_ livePhotoView: PHLivePhotoView, context: Context) {
        // Update the live photo if it changes
        if let livePhoto = livePhoto {
            print("🔵 LivePhotoView: Updating with live photo")
            livePhotoView.livePhoto = livePhoto
            
            // Play or stop the live photo based on isPlaying state
            if isPlaying {
                print("🔵 LivePhotoView: Starting playback")
                livePhotoView.startPlayback(with: .full)
            } else {
                print("🔵 LivePhotoView: Stopping playback")
                livePhotoView.stopPlayback()
            }
        } else {
            print("🔵 LivePhotoView: No live photo available")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var parent: LivePhotoView
        
        init(_ parent: LivePhotoView) {
            self.parent = parent
        }
        
        // MARK: - PHLivePhotoViewDelegate
        func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            print("🔵 LivePhotoView: Will begin playback")
        }
        
        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            print("🔵 LivePhotoView: Did end playback")
        }
    }
}

// MARK: - LivePhoto Asset Loader
class LivePhotoLoader: ObservableObject {
    @Published var livePhoto: PHLivePhoto?
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    private let imageManager = PHCachingImageManager()
    private var requestID: PHImageRequestID?
    
    func loadLivePhoto(for asset: PHAsset, targetSize: CGSize) {
        print("🔵 LivePhotoLoader: Attempting to load live photo")
        guard asset.isLivePhoto else {
            print("🔵 LivePhotoLoader: Asset is not a live photo")
            self.livePhoto = nil
            return
        }
        
        print("🔵 LivePhotoLoader: Asset is a live photo, loading...")
        isLoading = true
        error = nil
        
        // Cancel any previous request
        cancelLoading()
        
        // Configure options for high-quality live photo
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        
        // Use our optimized caching method
        requestID = imageManager.requestLivePhoto(
            for: asset,
            targetSize: targetSize, 
            contentMode: .aspectFill,
            options: options
        ) { [weak self] (livePhoto, info) in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = info?[PHImageErrorKey] as? Error {
                    print("🔵 LivePhotoLoader: Error loading live photo: \(error)")
                    self?.error = error
                    return
                }
                
                if let livePhoto = livePhoto {
                    print("🔵 LivePhotoLoader: Successfully loaded live photo")
                    self?.livePhoto = livePhoto
                } else {
                    print("🔵 LivePhotoLoader: No live photo was returned")
                }
            }
        }
    }
    
    func cancelLoading() {
        // Cancel any active request
        if let requestID = requestID {
            imageManager.cancelImageRequest(requestID)
            self.requestID = nil
        }
        
        // Stop caching images
        imageManager.stopCachingImagesForAllAssets()
        isLoading = false
    }
}

// MARK: - LivePhotoCard View
struct LivePhotoCard: View {
    let asset: PHAsset
    let staticImage: UIImage?
    
    @StateObject private var livePhotoLoader = LivePhotoLoader()
    @State private var isLongPressing: Bool = false
    @State private var showLivePhoto: Bool = false
    
    // Make animation faster and more responsive
    private let springAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.7)
    
    var body: some View {
        ZStack {
            // Static image as base layer
            if let staticImage = staticImage {
                Image(uiImage: staticImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(showLivePhoto ? 0 : 1)
            }
            
            // Live photo view
            if let livePhoto = livePhotoLoader.livePhoto {
                LivePhotoView(livePhoto: livePhoto, isPlaying: isLongPressing)
                    .opacity(showLivePhoto ? 1 : 0)
            }
            
            // Add a transparent layer for the gesture detection
            if asset.isLivePhoto {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onChanged { _ in
                                print("🔵 LivePhotoCard: Long press detected directly")
                                if livePhotoLoader.livePhoto != nil && !isLongPressing {
                                    print("🔵 LivePhotoCard: Activating live photo directly")
                                    
                                    // Provide haptic feedback
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.prepare()
                                    generator.impactOccurred()
                                    
                                    isLongPressing = true
                                    withAnimation(springAnimation) {
                                        showLivePhoto = true
                                    }
                                }
                            }
                            .onEnded { _ in
                                print("🔵 LivePhotoCard: Long press ended directly")
                                isLongPressing = false
                                withAnimation(springAnimation) {
                                    showLivePhoto = false
                                }
                            }
                    )
            }
        }
        .clipped()
        .onAppear {
            print("🔵 LivePhotoCard: onAppear")
            // Determine appropriate size based on the asset dimensions
            let targetSize = CGSize(
                width: asset.pixelWidth > 0 ? asset.pixelWidth : 1000, 
                height: asset.pixelHeight > 0 ? asset.pixelHeight : 1000
            )
            
            // Pre-load the live photo when the view appears
            if asset.isLivePhoto {
                print("🔵 LivePhotoCard: This is a live photo, size: \(targetSize)")
                livePhotoLoader.loadLivePhoto(for: asset, targetSize: targetSize)
            } else {
                print("🔵 LivePhotoCard: This is NOT a live photo")
            }
        }
        .onDisappear {
            print("🔵 LivePhotoCard: onDisappear")
            livePhotoLoader.cancelLoading()
        }
    }
} 