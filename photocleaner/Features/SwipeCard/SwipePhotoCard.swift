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
    
    // Live Photo support
    @StateObject private var livePhotoLoader = LivePhotoLoader()
    @State private var isLongPressing: Bool = false
    @State private var showLivePhoto: Bool = false
    
    // Track if user is swiping to disable force press during swipes
    @State private var isCurrentlySwiping: Bool = false
    
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
                
                // Add a separate transparent layer for force press handling (on Live Photos only)
                if isTopCard && asset.isLivePhoto {
                    Color.clear
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            // Track swiping to disable force press during swipes
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Check if user is swiping (moved more than 15 points)
                                    let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                                    
                                    if dragDistance > 15 && !isCurrentlySwiping {
                                        print("🟢 SwipePhotoCard: User started swiping - disabling force press")
                                        isCurrentlySwiping = true
                                        
                                        // Stop any current live photo playback
                                        if isLongPressing {
                                            isLongPressing = false
                                            withAnimation(.easeOut(duration: 0.1)) {
                                                showLivePhoto = false
                                            }
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    // Reset swipe state when drag ends
                                    isCurrentlySwiping = false
                                }
                        )
                        .overlay(
                            // Use a custom view for proper force touch detection
                            ForceTouchDetector { isForcePressed in
                                // Only respond if we have a live photo loaded AND user is not swiping
                                guard livePhotoLoader.livePhoto != nil, !isCurrentlySwiping else {
                                    // If swiping or no live photo, stop any current playback
                                    if isLongPressing {
                                        isLongPressing = false
                                        withAnimation(.easeOut(duration: 0.1)) {
                                            showLivePhoto = false
                                        }
                                    }
                                    return
                                }
                                
                                print("🟢 SwipePhotoCard: Force press state changed to \(isForcePressed)")
                                
                                // Photos app behavior: play while force pressing, stop immediately when not force pressing
                                if isForcePressed && !isLongPressing {
                                    // Starting to force press - provide haptic feedback and start live photo
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                    
                                    isLongPressing = true
                                    withAnimation(.easeIn(duration: 0.15)) {
                                        showLivePhoto = true
                                    }
                                } else if !isForcePressed && isLongPressing {
                                    // Stopped force pressing - immediately stop live photo
                                    isLongPressing = false
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        showLivePhoto = false
                                    }
                                }
                            }
                        )
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
                // Only load live photo if this asset actually is a live photo
                if asset.isLivePhoto {
                    let targetSize = CGSize(
                        width: asset.pixelWidth > 0 ? asset.pixelWidth : 1000,
                        height: asset.pixelHeight > 0 ? asset.pixelHeight : 1000
                    )
                    print("🟢 SwipePhotoCard: Loading live photo for asset \(index) with size \(targetSize)")
                    livePhotoLoader.loadLivePhoto(for: asset, targetSize: targetSize)
                }
            }
            .onDisappear {
                print("🟢 SwipePhotoCard: onDisappear for index \(index)")
                livePhotoLoader.cancelLoading()
                
                // Reset states
                isLongPressing = false
                showLivePhoto = false
                isCurrentlySwiping = false
            }
        }
    }
}

// MARK: - Force Touch Detector
struct ForceTouchDetector: UIViewRepresentable {
    let onForceChanged: (Bool) -> Void
    
    func makeUIView(context: Context) -> ForceTouchView {
        let view = ForceTouchView()
        view.onForceChanged = onForceChanged
        return view
    }
    
    func updateUIView(_ uiView: ForceTouchView, context: Context) {
        uiView.onForceChanged = onForceChanged
    }
}

class ForceTouchView: UIView {
    var onForceChanged: ((Bool) -> Void)?
    private var isCurrentlyForcePressed = false
    private var longPressTimer: Timer?
    private var touchStartTime: Date?
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        touchStartTime = Date()
        handleTouchForce(touches)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        handleTouchForce(touches)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        endForceTouch()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        endForceTouch()
    }
    
    private func endForceTouch() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        touchStartTime = nil
        
        if isCurrentlyForcePressed {
            isCurrentlyForcePressed = false
            onForceChanged?(false)
        }
    }
    
    private func handleTouchForce(_ touches: Set<UITouch>) {
        guard let touch = touches.first else { return }
        
        // Check if device supports force touch
        if touch.maximumPossibleForce > 0 {
            // Use actual force detection (3D Touch on older devices)
            let forceRatio = touch.force / touch.maximumPossibleForce
            let shouldBeForcePressed = forceRatio > 0.75 // Threshold for force press
            
            if shouldBeForcePressed != isCurrentlyForcePressed {
                isCurrentlyForcePressed = shouldBeForcePressed
                onForceChanged?(shouldBeForcePressed)
            }
        } else {
            // Fallback to time-based detection for devices without force touch
            // This mimics Haptic Touch behavior on newer devices
            if !isCurrentlyForcePressed && longPressTimer == nil {
                longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    if !self.isCurrentlyForcePressed && self.touchStartTime != nil {
                        self.isCurrentlyForcePressed = true
                        self.onForceChanged?(true)
                    }
                }
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