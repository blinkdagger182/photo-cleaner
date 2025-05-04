import SwiftUI
import Photos
import PhotosUI

struct SwipePhotoCard: View {
    // MARK: - Properties
    let asset: PHAsset
    let image: UIImage?
    let index: Int
    let isTopCard: Bool
    let offset: CGSize
    var onTap: (() -> Void)? = nil
    
    // Live Photo support
    @StateObject private var livePhotoLoader = LivePhotoLoader()
    @State private var isLongPressing: Bool = false
    @State private var showLivePhoto: Bool = false
    
    // Animations
    private let springAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.7)
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Static image layer
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .opacity(showLivePhoto ? 0 : 1)
                } else {
                    // Fallback if no image available
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .scaleEffect(1.5)
                        )
                }
                
                // Live photo layer
                if let livePhoto = livePhotoLoader.livePhoto, isTopCard {
                    LivePhotoView(livePhoto: livePhoto, isPlaying: isLongPressing)
                        .opacity(showLivePhoto ? 1 : 0)
                }
                
                // Live Photo indicator
                if asset.isLivePhoto && !showLivePhoto && isTopCard {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "livephoto")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                                .padding(12)
                        }
                        Spacer()
                    }
                }
                
                // Add a separate transparent layer for gesture handling
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onChanged { isPressing in
                                print("🟢 SwipePhotoCard: Long press state changed to \(isPressing)")
                                
                                // Only respond if we have a live photo loaded
                                if livePhotoLoader.livePhoto != nil {
                                    if isPressing && !isLongPressing {
                                        isLongPressing = true
                                        
                                        // Provide haptic feedback on press start
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        
                                        withAnimation(springAnimation) {
                                            showLivePhoto = true
                                        }
                                    } else if !isPressing && isLongPressing {
                                        isLongPressing = false
                                        withAnimation(springAnimation) {
                                            showLivePhoto = false
                                        }
                                    }
                                } else if isPressing {
                                    print("🟢 SwipePhotoCard: No live photo available to play")
                                }
                            }
                    )
                    .onTapGesture {
                        // Call the tap action if provided
                        onTap?()
                    }
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(radius: 8)
            .offset(x: isTopCard ? offset.width : 0, y: isTopCard ? offset.height : 0)
            .rotationEffect(
                isTopCard ? .degrees(Double(offset.width / 12)) : .zero,
                anchor: .center
            )
            .onAppear {
                print("🟢 SwipePhotoCard: onAppear for index \(index), isLivePhoto: \(asset.isLivePhoto)")
                
                // Print debug info about image quality
                if let image = image {
                    let quality = "\(image.size.width)x\(image.size.height)"
                    print("🟢 SwipePhotoCard: Image quality at index \(index): \(quality)")
                    
                    // Check for unexpectedly small image sizes
                    if image.size.width < 500 || image.size.height < 500 {
                        print("⚠️ SwipePhotoCard: Low quality image detected at index \(index): \(quality)")
                    }
                }
                
                // Only load live photo if this asset actually is a live photo
                if asset.isLivePhoto {
                    // Use a more conservative target size for better performance
                    let targetSize = CGSize(
                        width: min(asset.pixelWidth, 1080),
                        height: min(asset.pixelHeight, 1080)
                    )
                    print("🟢 SwipePhotoCard: Loading live photo for asset \(index) with size \(targetSize)")
                    livePhotoLoader.loadLivePhoto(for: asset, targetSize: targetSize)
                }
            }
            .onDisappear {
                print("🟢 SwipePhotoCard: onDisappear for index \(index)")
                livePhotoLoader.cancelLoading()
            }
        }
    }
}

// MARK: - Preview
#Preview {
    // This preview uses a mock asset - in real usage, pass a real PHAsset
    SwipePhotoCard(
        asset: PHAsset(),
        image: UIImage(systemName: "photo"),
        index: 0,
        isTopCard: true,
        offset: .zero
    )
    .frame(height: 500)
    .padding()
} 