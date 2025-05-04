import SwiftUI
import Photos
import PhotosUI

struct LivePhotoView: UIViewRepresentable {
    // MARK: - Properties
    var livePhoto: PHLivePhoto?
    var isPlaying: Bool
    var contentMode: UIView.ContentMode = .scaleAspectFill
    
    // MARK: - UIViewRepresentable
    func makeUIView(context: Context) -> PHLivePhotoView {
        print("🔵 LivePhotoView: makeUIView called")
        let livePhotoView = PHLivePhotoView()
        livePhotoView.delegate = context.coordinator
        livePhotoView.contentMode = contentMode
        livePhotoView.clipsToBounds = true
        return livePhotoView
    }
    
    func updateUIView(_ livePhotoView: PHLivePhotoView, context: Context) {
        // Update the live photo if it changes
        if livePhotoView.livePhoto != livePhoto {
            print("🔵 LivePhotoView: Updating with new live photo")
            livePhotoView.livePhoto = livePhoto
        }
        
        // Play or stop the live photo based on isPlaying state, avoiding unnecessary calls
        if isPlaying && !context.coordinator.isCurrentlyPlaying {
            print("🔵 LivePhotoView: Starting playback")
            livePhotoView.startPlayback(with: .full)
            context.coordinator.isCurrentlyPlaying = true
        } else if !isPlaying && context.coordinator.isCurrentlyPlaying {
            print("🔵 LivePhotoView: Stopping playback")
            livePhotoView.stopPlayback()
            context.coordinator.isCurrentlyPlaying = false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var parent: LivePhotoView
        var isCurrentlyPlaying: Bool = false
        
        init(_ parent: LivePhotoView) {
            self.parent = parent
        }
        
        // MARK: - PHLivePhotoViewDelegate
        func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            print("🔵 LivePhotoView: Will begin playback")
            isCurrentlyPlaying = true
        }
        
        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            print("🔵 LivePhotoView: Did end playback")
            isCurrentlyPlaying = false
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
    private var loadingTimeout: DispatchWorkItem?
    
    func loadLivePhoto(for asset: PHAsset, targetSize: CGSize) {
        print("🔵 LivePhotoLoader: Attempting to load live photo")
        guard asset.mediaType == .image, asset.isLivePhoto else {
            print("🔵 LivePhotoLoader: Asset is not a live photo")
            self.livePhoto = nil
            return
        }
        
        print("🔵 LivePhotoLoader: Asset is a live photo, loading...")
        isLoading = true
        error = nil
        
        // Cancel any previous request
        cancelLoading()
        
        // Set up a timeout for the request (5 seconds)
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            print("🔵 LivePhotoLoader: Live photo load timed out")
            self.cancelLoading()
            DispatchQueue.main.async {
                self.isLoading = false
                self.error = NSError(domain: "LivePhotoLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Loading timed out"])
            }
        }
        loadingTimeout = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutItem)
        
        // Configure options for live photo loading
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic // Start with lower quality, then improve
        options.isNetworkAccessAllowed = true
        options.version = .current
        
        // Use a more conservative target size for better performance
        let scaledSize = scaledTargetSize(from: targetSize, scale: 0.8)
        
        print("🔵 LivePhotoLoader: Requesting live photo with size \(scaledSize)")
        
        // Request the live photo
        requestID = imageManager.requestLivePhoto(
            for: asset,
            targetSize: scaledSize, 
            contentMode: .aspectFill,
            options: options
        ) { [weak self] (livePhoto, info) in
            guard let self = self else { return }
            
            // Cancel the timeout
            self.loadingTimeout?.cancel()
            self.loadingTimeout = nil
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                // Check for cancellation
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    print("🔵 LivePhotoLoader: Request was cancelled")
                    return
                }
                
                // Check for errors
                if let error = info?[PHImageErrorKey] as? Error {
                    print("🔵 LivePhotoLoader: Error loading live photo: \(error)")
                    self.error = error
                    return
                }
                
                // Check for success
                if let livePhoto = livePhoto {
                    print("🔵 LivePhotoLoader: Successfully loaded live photo")
                    self.livePhoto = livePhoto
                } else {
                    print("🔵 LivePhotoLoader: No live photo was returned")
                    // If we're degraded, we might get an update later
                    if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
                        print("🔵 LivePhotoLoader: This is a degraded result, waiting for better quality")
                    } else {
                        self.error = NSError(domain: "LivePhotoLoader", code: -2, userInfo: [NSLocalizedDescriptionKey: "No live photo available"])
                    }
                }
            }
        }
    }
    
    private func scaledTargetSize(from originalSize: CGSize, scale: CGFloat) -> CGSize {
        // If the original size is zero or very small, use a reasonable default
        if originalSize.width < 100 || originalSize.height < 100 {
            return CGSize(width: 1080, height: 1080)
        }
        
        // Apply the scale factor
        return CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
    }
    
    func cancelLoading() {
        // Cancel timeout
        loadingTimeout?.cancel()
        loadingTimeout = nil
        
        // Cancel any active request
        if let requestID = requestID {
            imageManager.cancelImageRequest(requestID)
            self.requestID = nil
        }
        
        // Stop caching images
        imageManager.stopCachingImagesForAllAssets()
        isLoading = false
    }
    
    deinit {
        cancelLoading()
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
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onChanged { isPressing in
                                print("🔵 LivePhotoCard: Long press detected: \(isPressing)")
                                if livePhotoLoader.livePhoto != nil && !isLongPressing && isPressing {
                                    print("🔵 LivePhotoCard: Activating live photo")
                                    
                                    // Provide haptic feedback
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.prepare()
                                    generator.impactOccurred()
                                    
                                    isLongPressing = true
                                    withAnimation(springAnimation) {
                                        showLivePhoto = true
                                    }
                                } else if !isPressing && isLongPressing {
                                    print("🔵 LivePhotoCard: Deactivating live photo")
                                    isLongPressing = false
                                    withAnimation(springAnimation) {
                                        showLivePhoto = false
                                    }
                                }
                            }
                    )
            }
        }
        .clipped()
        .onAppear {
            print("🔵 LivePhotoCard: onAppear")
            // Use a more reasonable target size to improve performance
            let targetSize = CGSize(
                width: min(asset.pixelWidth, 1080),
                height: min(asset.pixelHeight, 1080)
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