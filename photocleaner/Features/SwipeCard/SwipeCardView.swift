import Photos
import SwiftUI
import UIKit

struct SwipeCardView: View {
    let group: PhotoGroup
    @Binding var forceRefresh: Bool

    @EnvironmentObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var toast: ToastService
    
    // Use the new ViewModel to manage state
    @StateObject private var viewModel: SwipeCardViewModel
    
    // Track hasAppeared state to keep animations consistent
    @State private var hasAppeared = false
    
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

    init(group: PhotoGroup, forceRefresh: Binding<Bool>) {
        self.group = group
        self._forceRefresh = forceRefresh
        // Initialize the ViewModel with just the group
        self._viewModel = StateObject(wrappedValue: SwipeCardViewModel(group: group))
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

                                ZStack {
                                    if actualIndex < viewModel.preloadedImages.count,
                                        let image = viewModel.preloadedImages[actualIndex]
                                    {
                                        // We have the image, display it
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .scaleEffect(finalScale * currentScale)
                                            .gesture(index == 0 ? magnification : nil)
                                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
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
                                        } else {
                                            // No previous image available, show skeleton with less white
                                            RoundedRectangle(cornerRadius: 30)
                                                .fill(Color(white: 0.95))
                                                .frame(width: geometry.size.width * 0.85)
                                                .shadow(radius: 8)
                                                .overlay(
                                                    VStack {
                                                        ProgressView()
                                                            .padding(.bottom, 8)
                                                        Text("Loading image...")
                                                            .font(.caption)
                                                            .foregroundColor(.gray)
                                                    }
                                                )
                                                .padding()
                                        }
                                    }

                                    // Remove the overlay label from here
                                }
                                .frame(maxWidth: .infinity)
                                .background(Color.black)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 30, style: .continuous)
                                )
                                .shadow(radius: 8)
                                .offset(
                                    x: index == 0 ? viewModel.offset.width : 0,
                                    y: index == 0 ? viewModel.offset.height : 0
                                )
                                .rotationEffect(
                                    index == 0 ? .degrees(Double(viewModel.offset.width / 12)) : .zero,
                                    anchor: .center
                                )
                                .opacity(index == 1 ? 0.4 : 1.0)
                                .animation(
                                    hasAppeared && index == 0
                                        ? .interactiveSpring(response: 0.3, dampingFraction: 0.7)
                                        : (index == 0 ? .easeInOut(duration: 0.3) : .none), 
                                    value: viewModel.offset
                                )
                                .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
                                .zIndex(Double(-index))
                                .highPriorityGesture(
                                    index == 0
                                        ? DragGesture()
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
                                        : nil
                                )
                                .id("\(viewModel.currentIndex)-\(index)") // Key for animation
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

                    HStack(spacing: 40) {
                        CircleButton(icon: "trash", tint: Color(red: 0.55, green: 0.35, blue: 0.98)) {
                            if viewModel.isCurrentImageReadyForInteraction() {
                                viewModel.triggerDeleteFromButton()
                            } else {
                                toast.show("Please wait for the image to fully load before deleting", duration: 2.0)
                            }
                        }
                        CircleButton(icon: "bookmark", tint: .yellow) {
                            if viewModel.isCurrentImageReadyForInteraction() {
                                viewModel.triggerBookmarkFromButton()
                            } else {
                                toast.show("Please wait for the image to fully load before saving", duration: 2.0)
                            }
                        }
                        CircleButton(icon: "checkmark", tint: .green) {
                            if viewModel.isCurrentImageReadyForInteraction() {
                                viewModel.triggerKeepFromButton()
                            } else {
                                toast.show("Please wait for the image to fully load before keeping", duration: 2.0)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle(group.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            DeletePreviewView(forceRefresh: $forceRefresh)
                .environmentObject(photoManager)
                .environmentObject(toast)
        }
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
