import SwiftUI
import Photos
import PhotosUI

// MARK: - LivePhotoView
struct LivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    var isPlaying: Bool
    
    func makeUIView(context: Context) -> PHLivePhotoView {
        let livePhotoView = PHLivePhotoView()
        livePhotoView.livePhoto = livePhoto
        livePhotoView.delegate = context.coordinator
        return livePhotoView
    }
    
    func updateUIView(_ livePhotoView: PHLivePhotoView, context: Context) {
        // Update the live photo if needed
        if livePhotoView.livePhoto != livePhoto {
            livePhotoView.livePhoto = livePhoto
        }
        
        // Start or stop playback based on isPlaying
        if isPlaying {
            livePhotoView.startPlayback(with: .full)
        } else {
            livePhotoView.stopPlayback()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var parent: LivePhotoView
        
        init(_ parent: LivePhotoView) {
            self.parent = parent
        }
        
        func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            print("LivePhotoView: Will begin playback")
        }
        
        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            print("LivePhotoView: Did end playback")
        }
    }
}

// MARK: - LivePhotoLoader
class LivePhotoLoader: ObservableObject {
    @Published var livePhoto: PHLivePhoto?
    @Published var isLoading = false
    private var requestID: PHImageRequestID?
    
    func loadLivePhoto(for asset: PHAsset, targetSize: CGSize = PHImageManagerMaximumSize) {
        // Skip if already loading or if the asset is not a live photo
        guard !isLoading, asset.mediaSubtypes.contains(.photoLive) else { return }
        
        isLoading = true
        
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        // Cancel any existing request
        if let requestID = requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        
        // Request the live photo
        requestID = PHImageManager.default().requestLivePhoto(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] livePhoto, info in
            DispatchQueue.main.async {
                self?.livePhoto = livePhoto
                self?.isLoading = false
                self?.requestID = nil
            }
        }
    }
    
    func cancelLoading() {
        if let requestID = requestID {
            PHImageManager.default().cancelImageRequest(requestID)
            self.requestID = nil
        }
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
            if asset.mediaSubtypes.contains(.photoLive) {
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
            if asset.mediaSubtypes.contains(.photoLive) {
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