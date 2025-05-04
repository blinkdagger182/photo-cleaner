import Photos
import SwiftUI
import UIKit
import StoreKit

struct SwipeCardView: View {
    let group: PhotoGroup
    @Binding var forceRefresh: Bool

    @EnvironmentObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var toast: ToastService
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    // State for paywall presentation
    @State private var showPaywall = false
    
    // State for memory saved modal
    @State private var showMemorySavedModal = false
    @State private var memorySavedMB: Double = 0
    @State private var totalMemoryMB: Double = 0
    
    // Use the new ViewModel to manage state
    @StateObject private var viewModel: SwipeCardViewModel
    
    // Track hasAppeared state to keep animations consistent
    @State private var hasAppeared = false
    
    // Is this view being shown from the Discover tab
    private let isDiscoverTab: Bool
    
    // Zoom state
    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0
    
    // Fly-off animation state
    @State private var showFlyOffLabel: Bool = false
    @State private var flyOffLabelText: String = ""
    @State private var flyOffLabelColor: Color = .clear
    @State private var flyOffLabelOffset: CGSize = .zero
    @State private var flyOffLabelRotation: Angle = .zero
    @State private var flyOffLabelOpacity: Double = 0.0

    init(group: PhotoGroup, forceRefresh: Binding<Bool>, isDiscoverTab: Bool = false) {
        self.group = group
        self._forceRefresh = forceRefresh
        self.isDiscoverTab = isDiscoverTab
        // Initialize the ViewModel with the group, image view tracker, and discover tab flag
        self._viewModel = StateObject(wrappedValue: SwipeCardViewModel(
            group: group, 
            imageViewTracker: ImageViewTracker.shared,
            isDiscoverTab: isDiscoverTab
        ))
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        if group.count == 0 {
                            Text("No photos available")
                                .foregroundColor(.gray)
                        } else if viewModel.isLoading && viewModel.preloadedImages.isEmpty {
                            // Show loading indicator only on initial load
                            VStack(spacing: 16) {
                                skeletonStack(
                                    width: geometry.size.width * 0.85,
                                    height: geometry.size.height * 0.4
                                )

                                VStack(spacing: 8) {
                                    Text("We are fetching images...")
                                        .font(.headline)
                                        .foregroundColor(.gray)

                                    Text("🧘 Patience, young padawan...")
                                        .font(.subheadline)
                                        .italic()
                                        .foregroundColor(.secondary)
                                }
                                .multilineTextAlignment(.center)
                            }
                            .padding(.top, 60)
                        } else {
                            // Show images with proper fallbacks
                            ForEach(
                                (0..<min(2, max(group.count - viewModel.currentIndex, 0))).reversed(),
                                id: \.self
                            ) { index in
                                let actualIndex = viewModel.currentIndex + index

                                if index == 0 && actualIndex < viewModel.preloadedImages.count,
                                   let image = viewModel.preloadedImages[actualIndex] {
                                    // Use our new SwipePhotoCard component for the top card with live photo support
                                    SwipePhotoCard(
                                        asset: group.asset(at: actualIndex) ?? PHAsset(),
                                        image: image,
                                        index: actualIndex,
                                        isTopCard: true,
                                        offset: viewModel.offset
                                    )
                                    .frame(maxWidth: .infinity)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                // Only process drag if not currently zooming
                                                if currentScale <= 1.0 {
                                                    viewModel.handleDragGesture(value: value)
                                                }
                                            }
                                            .onEnded { value in
                                                // Only process drag end if not currently zooming
                                                if currentScale <= 1.0 {
                                                    viewModel.handleDragGestureEnd(value: value)
                                                }
                                            }
                                    )
                                    .simultaneousGesture(magnification)
                                    .id("\(viewModel.currentIndex)-\(index)") // Key for animation
                                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                                } else if index == 1 && actualIndex < viewModel.preloadedImages.count,
                                          let image = viewModel.preloadedImages[actualIndex] {
                                    // Use our SwipePhotoCard for background card too, but without gesture support
                                    SwipePhotoCard(
                                        asset: group.asset(at: actualIndex) ?? PHAsset(),
                                        image: image,
                                        index: actualIndex,
                                        isTopCard: false,
                                        offset: .zero // Background card doesn't move
                                    )
                                    .frame(maxWidth: .infinity)
                                    .opacity(0.4) // Background card is dimmed
                                    .id("\(viewModel.currentIndex)-\(index)") // Key for animation
                                    .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
                                } else if actualIndex < group.count {
                                    // If no image is available yet but we have a previous image, show it with overlay
                                    if index == 0, let prevImage = viewModel.previousImage {
                                        Image(uiImage: prevImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: geometry.size.width * 0.85)
                                            .padding()
                                            .background(Color.white)
                                            .clipShape(
                                                RoundedRectangle(
                                                    cornerRadius: 30, style: .continuous)
                                            )
                                            .shadow(radius: 8)
                                            .overlay(
                                                ZStack {
                                                    Color.black.opacity(0.2)
                                                    ProgressView()
                                                        .scaleEffect(1.5)
                                                        .tint(.white)
                                                }
                                            )
                                    }
                                }
                            }
                            
                            // Add Static drag label with same style as before, but above cards
                            if viewModel.offset != .zero, let swipeLabel = viewModel.swipeLabel {
                                let labelColor = swipeLabel == "Delete" ? 
                                    Color(red: 0.55, green: 0.35, blue: 0.98) : // Purple for Delete
                                    Color.green                                 // Green for Keep
                                    
                                Text(swipeLabel.uppercased())
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(labelColor)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.clear)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(labelColor, lineWidth: 3)
                                            )
                                    )
                                    .rotationEffect(.degrees(-15))
                                    .opacity(1)
                                    .offset(
                                        x: swipeLabel == "Keep" ? -40 : 40,
                                        y: -geometry.size.height / 4
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                    .animation(.easeInOut(duration: 0.2), value: swipeLabel)
                                    .zIndex(100) // Ensure it's above cards
                            }
                            
                            // Fly-off animation label
                            if showFlyOffLabel {
                                Text(flyOffLabelText.uppercased())
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(flyOffLabelColor)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.clear)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(flyOffLabelColor, lineWidth: 3)
                                            )
                                    )
                                    .rotationEffect(flyOffLabelRotation)
                                    .opacity(flyOffLabelOpacity)
                                    .offset(flyOffLabelOffset)
                                    .zIndex(101) // Above everything
                            }

                            // Show a loading indicator when actively loading more images
                            // if viewModel.isLoading {
                            //     HStack {
                            //         Spacer()
                            //         VStack {
                            //             Spacer()
                            //             ProgressView()
                            //                 .scaleEffect(1.5)
                            //             Text("Loading more...")
                            //                 .font(.caption)
                            //                 .foregroundColor(.gray)
                            //                 .padding(.top, 8)
                            //             Spacer()
                            //         }
                            //         Spacer()
                            //     }
                            //     .frame(width: 150, height: 100)
                            //     .background(Color.white.opacity(0.9))
                            //     .cornerRadius(12)
                            //     .shadow(radius: 8)
                            //     .padding(.bottom, 50)
                            // }
                        }
                    }

                    Spacer()

                    Text("\(viewModel.currentIndex + 1)/\(group.count)")
                        .font(.caption)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                    #if DEBUG
                    // Debug button for Live Photo testing
                    if let currentAsset = group.asset(at: viewModel.currentIndex),
                       currentAsset.isLivePhoto,
                       let currentImage = viewModel.currentIndex < viewModel.preloadedImages.count ? viewModel.preloadedImages[viewModel.currentIndex] : nil {
                        LivePhotoDebugButton(asset: currentAsset, image: currentImage)
                            .padding(.top, 8)
                    }
                    #endif

                    VStack(spacing: 20) {
                        HStack(spacing: 40) {
                            CircleButton(icon: "trash", tint: Color(red: 0.55, green: 0.35, blue: 0.98)) {
                                if viewModel.isCurrentImageReadyForInteraction() {
                                    viewModel.triggerDeleteFromButton()
                                } else {
                                    toast.show("Please wait for the image to fully load before deleting", duration: 2.0)
                                }
                            }
                            Button(action: {
                                if viewModel.isCurrentImageReadyForInteraction() {
                                    viewModel.triggerBookmarkFromButton()
                                } else {
                                    toast.show("Please wait for the image to fully load before saving", duration: 2.0)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Text("Maybe")
                                        .foregroundColor(.yellow)
                                        .font(.system(size: 16, weight: .medium))
                                    Image(systemName: "questionmark")
                                        .foregroundColor(.yellow)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                // .background(
                                //     Capsule()
                                //         .fill(Color.yellow.opacity(0.15)
                                //         .strokesBorder(Color.black, lineWidth: 1.5)
                                // )
                                // )
                                .background(
                                    Capsule()
                                        .strokeBorder(Color.yellow, lineWidth: 1.5)
                                )
                            }

                            CircleButton(icon: "checkmark", tint: .green) {
                                if viewModel.isCurrentImageReadyForInteraction() {
                                    viewModel.triggerKeepFromButton()
                                } else {
                                    toast.show("Please wait for the image to fully load before keeping", duration: 2.0)
                                }
                            }
                        }
                        
                        #if DEBUG
                        if isDiscoverTab {
                            Button(action: {
                                viewModel.showRCPaywall = true
                            }) {
                                Text("Test Paywall")
                                    .font(.caption)
                                    .padding(6)
                                    .background(Color.orange.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        #endif
                    }
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle(group.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        if viewModel.isCurrentImageReadyForInteraction() {
                            viewModel.shareCurrentImage()
                        } else {
                            toast.show("Please wait for the image to load before sharing", duration: 2.0)
                        }
                    }) {
                        HStack(spacing: 4) {
                            if viewModel.isSharing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.primary)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color(.systemGroupedBackground).opacity(0.8))
                        .cornerRadius(8)
                        .contentShape(Rectangle()) // Makes the entire area tappable
                        .buttonStyle(.plain)
                    }
                    .disabled(viewModel.isSharing)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Next") {
                        viewModel.prepareDeletePreview()
                    }
                    .disabled(group.count == 0)
                }
            }
        }
        .onAppear {
            hasAppeared = true
            
            // Initialize the view model with environment objects
            viewModel.photoManager = photoManager
            viewModel.toast = toast
            viewModel.imageViewTracker = ImageViewTracker.shared
            
            // Set the force refresh callback
            viewModel.forceRefreshCallback = {
                self.forceRefresh.toggle()
            }
            
            // Set up the fly-off animation callback
            viewModel.triggerLabelFlyOff = { text, color, direction in
                // Start with the label visible at the card's position
                self.flyOffLabelText = text
                self.flyOffLabelColor = color
                self.flyOffLabelOffset = .zero
                self.flyOffLabelRotation = .degrees(-15)
                self.flyOffLabelOpacity = 1.0
                self.showFlyOffLabel = true
                
                // Random components for the animation
                let isKeep = text == "Keep"
                let randomDuration = Double.random(in: 0.4...0.8)
                let randomHeightOffset = CGFloat.random(in: -350...(-120))
                let randomWidthMultiplier = CGFloat.random(in: 1.2...2.0)
                let baseRotation = Double.random(in: 20...60)
                
                // KEEP: Right to Left, DELETE: Left to Right
                let finalRotation = isKeep ? -baseRotation : baseRotation
                
                // Animate the label flying off with randomness
                withAnimation(.easeOut(duration: randomDuration)) {
                    // KEEP labels fly right to left, DELETE labels fly left to right
                    self.flyOffLabelOffset = CGSize(
                        width: isKeep ? -200 * randomWidthMultiplier : 200 * randomWidthMultiplier,
                        height: randomHeightOffset
                    )
                    self.flyOffLabelRotation = .degrees(finalRotation)
                    
                    // Random fade timing to make it appear more natural
                    self.flyOffLabelOpacity = 0.0
                }
                
                // Reset the state after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + randomDuration + 0.1) {
                    self.showFlyOffLabel = false
                }
            }
            
            // Notify the view model that the view has appeared
            viewModel.onAppear()

            // Register for memory warnings
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { _ in
                clearMemory()
                // Also clear the PHAsset size cache
                PHAsset.clearSizeCache()
            }
        }
        .id(forceRefresh)
        .onDisappear {
            viewModel.onDisappear()
            clearMemory()
            // Remove observer
            NotificationCenter.default.removeObserver(
                self,
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
        }
        .overlay(toast.overlayView, alignment: .bottom)
        .fullScreenCover(isPresented: $viewModel.showDeletePreview, onDismiss: {
            // Clean up any observers when the preview is dismissed
            viewModel.onDeletePreviewDismissed()
        }) {
            DeletePreviewView(forceRefresh: $forceRefresh, onDeletionComplete: { result in
                // Handle the deletion result by showing the memory saved modal
                if result.success {
                    self.memorySavedMB = result.memorySavedMB
                    self.totalMemoryMB = result.totalMemoryMB
                    self.showMemorySavedModal = true
                }
            })
                .environmentObject(photoManager)
                .environmentObject(toast)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(subscriptionManager)
        }
        .fullScreenCover(isPresented: $viewModel.showRCPaywall) {
            PaywallView()
                .environmentObject(subscriptionManager)
        }
        .overlay {
            if showMemorySavedModal {
                // Semi-transparent background
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        // Do nothing, prevent tap through
                    }
                
                // Modal
                MemorySavedModal(
                    memorySavedMB: memorySavedMB,
                    totalMemoryMB: totalMemoryMB,
                    onClose: {
                        showMemorySavedModal = false
                    },
                    onRate: {
                        requestAppReview()
                        showMemorySavedModal = false
                    }
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(100)
            }
        }
        .animation(.spring(), value: showMemorySavedModal)
        #if DEBUG
        // Add debug overlay for swipe count in Discover tab
        .overlay(alignment: .topTrailing) {
            if isDiscoverTab {
                let swipeCount = viewModel.discoverSwipeTracker?.swipeCount ?? 0
                let threshold = viewModel.discoverSwipeTracker?.threshold ?? 5
                
                Text("Swipes: \(swipeCount)/\(threshold)")
                    .font(.caption)
                    .padding(6)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .padding(8)
            }
        }
        #endif
    }

    // MARK: - Gestures
    var magnification: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                // Only allow zooming with two fingers
                if value != 1.0 {  // This helps identify a true pinch gesture
                    // Allow zooming to a larger scale (Instagram-like)
                    self.finalScale = max(value, 1.0)
                    
                    // Reset any drag offset when zooming starts
                    if self.currentScale == 1.0 && self.finalScale > 1.0 {
                        viewModel.offset = .zero
                    }
                }
            }
            .onEnded { _ in
                // Always animate back to original size when gesture ends (Instagram-like behavior)
                withAnimation(.spring()) {
                    self.currentScale = 1.0
                    self.finalScale = 1.0
                }
            }
    }

    // MARK: - Helpers
    
    private func clearMemory() {
        // Use memory warning to clear caches
        viewModel.clearMemory()
    }

    private func skeletonStack(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach((0..<2).reversed(), id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color(white: 0.9))
                        .frame(width: width, height: height)
                        .offset(x: CGFloat(index * 6), y: CGFloat(index * 6))
                        .shadow(radius: 6)
                        .shimmering()

                    if index == 0 {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                    }
                }
            }
        }
    }

    // Function to request app review
    private func requestAppReview() {
        // Check if we're on a physical device (StoreKit review prompts don't work in simulators)
        #if !targetEnvironment(simulator)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            print("No window scene found, skipping review request")
            return
        }
        
        // Request the review
        if #available(iOS 14.0, *) {
            SKStoreReviewController.requestReview(in: windowScene)
        } else {
            // Fallback on earlier versions
            SKStoreReviewController.requestReview()
        }
        #else
        // We're running in the simulator, show a message via toast
        toast.show("App review requested. This only works on physical devices.", duration: 2.0)
        #endif
    }
}

struct CircleButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 60, height: 60)
                .background(Circle().strokeBorder(tint, lineWidth: 2))
        }
    }
}

extension View {
    func shimmering(active: Bool = true, duration: Double = 1.25) -> some View {
        modifier(ShimmerModifier(active: active, duration: duration))
    }
}

struct ShimmerModifier: ViewModifier {
    let active: Bool
    let duration: Double

    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        if !active {
            return AnyView(content)
        }

        return AnyView(
            content
                .redacted(reason: .placeholder)
                .overlay(
                    GeometryReader { geometry in
                        let gradient = LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear, Color.white.opacity(0.6), Color.clear,
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        Rectangle()
                            .fill(gradient)
                            .rotationEffect(.degrees(30))
                            .offset(x: geometry.size.width * phase)
                            .frame(width: geometry.size.width * 1.5)
                            .blendMode(.plusLighter)
                            .animation(
                                .linear(duration: duration).repeatForever(autoreverses: false),
                                value: phase)
                    }
                    .mask(content)
                )
                .onAppear {
                    phase = 1.5
                }
        )
    }
}
