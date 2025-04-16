import SwiftUI
import AVKit
import Photos

// MARK: - Interactive Swipe Card Stack View
struct FrostedCardStackView: View {
    let images = ["image1", "image2", "image3"]
    @State private var topIndex: Int = 0
    @State private var removedIndices: Set<Int> = []
    
    // Configuration for card stacking effect
    private let cardOffset: CGFloat = -12 // Negative for upward offset
    private let cardScale: CGFloat = 0.05 // Scale reduction per card in stack

    var body: some View {
        ZStack {
            // Show cards from the stack (only those not yet removed)
            ForEach(0..<images.count, id: \.self) { index in
                if index >= topIndex && index < topIndex + 3 {
                    let stackPosition = index - topIndex
                    let imageName = images[index]
                    let isTopCard = index == topIndex
                    
                    SwipeCard(
                        imageName: imageName,
                        showOverlay: isTopCard,
                        cardPosition: stackPosition
                    ) {
                        // Mark this card as removed and animate next card
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            removedIndices.insert(index)
                            topIndex += 1
                        }
                    }
                    .scaleEffect(1 - CGFloat(stackPosition) * cardScale)
                    .offset(y: CGFloat(stackPosition) * cardOffset)
                    .zIndex(Double(100 - index)) // Ensure proper stacking with unique z values
                    .disabled(!isTopCard) // Only top card is interactive
                }
            }
            
            // Show final logo when all cards are swiped
            if topIndex >= images.count {
                VStack {
                    Image("CLN")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(radius: 8)
                        .transition(.scale.combined(with: .opacity))
                    
                    Text("Ready to clean your photos!")
                        .font(.title2)
                        .fontWeight(.medium)
                        .padding(.top)
                }
                .transition(.opacity)
                .animation(.easeInOut, value: topIndex)
            }
        }
        .frame(height: 220) // Fixed height container
        .padding(.top, 30)
    }
}

// MARK: - Swipe Card
struct SwipeCard: View {
    let imageName: String
    var showOverlay: Bool
    var cardPosition: Int // Position in stack (0 = top)
    var onSwiped: () -> Void

    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    // Card dimensions
    private let cardWidth: CGFloat = 320
    private let cardHeight: CGFloat = 180
    
    // Calculate current offset and rotation
    private var currentOffset: CGSize {
        // Only apply horizontal drag offset, keep vertical position fixed
        return CGSize(
            width: offset.width + (isDragging ? dragOffset.width : 0),
            height: 0 // Keep fixed vertical position
        )
    }
    
    private var currentRotation: Double {
        // Rotation proportional to drag amount
        return Double(currentOffset.width) / 20
    }
    
    // Calculate UI states based on drag amount
    private var dragPercentage: CGFloat {
        let maxDrag: CGFloat = 100
        let percentage = abs(currentOffset.width) / maxDrag
        return min(percentage, 1.0)
    }
    
    // Opacity for tags
    private var tagOpacity: CGFloat {
        return min(dragPercentage * 2, 1.0)
    }

    var body: some View {
        ZStack {
            // Card content
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 36))
                .overlay(
                    RoundedRectangle(cornerRadius: 36)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(radius: 5)
        }
        .overlay(alignment: .topLeading) {
            // KEEP label
            if currentOffset.width > 0 {
                SwipeTagLabel(text: "KEEP", color: .green, angle: -15, xOffset: 20)
                    .opacity(tagOpacity)
                    .animation(.easeOut(duration: 0.2), value: tagOpacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            // DELETE label
            if currentOffset.width < 0 {
                SwipeTagLabel(text: "DELETE", color: .red, angle: 15, xOffset: -20)
                    .opacity(tagOpacity)
                    .animation(.easeOut(duration: 0.2), value: tagOpacity)
            }
        }
        .offset(x: currentOffset.width, y: 0) // Only move horizontally when dragging
        .rotationEffect(.degrees(currentRotation))
        .gesture(
            showOverlay ? // Only top card gets gesture
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        // Only update if we're the top card
                        state = value.translation
                        isDragging = true
                    }
                    .onEnded { value in
                        isDragging = false
                        
                        // Decide if the card should be swiped out
                        if abs(value.translation.width) > 100 {
                            // Swipe it out with animation
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset.width = value.translation.width > 0 ? 1000 : -1000
                            }
                            
                            // Small delay before triggering the callback
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onSwiped()
                            }
                        } else {
                            // Snap back to center
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                offset = .zero
                            }
                        }
                    } : nil
        )
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: dragOffset)
    }
}

// MARK: - Swipe Tag Label
struct SwipeTagLabel: View {
    let text: String
    let color: Color
    let angle: Double
    let xOffset: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .heavy))
            .foregroundColor(color)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: 4)
            )
            .rotationEffect(.degrees(angle))
            .offset(x: xOffset, y: 20)
    }
}

// MARK: - Cycling Tagline View
struct CyclingTaglineView: View {
    @State private var currentIndex = 0
    private let taglines = [
        "Swipe left to delete.",
        "Swipe right to keep.",
        "Clean your gallery in minutes."
    ]

    var body: some View {
        Text(taglines[currentIndex])
            .font(.headline)
            .foregroundColor(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentIndex = (currentIndex + 1) % taglines.count
                    }
                }
            }
    }
}

// MARK: - Unified Onboarding View
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @EnvironmentObject private var photoManager: PhotoManager
    @State private var showPermissionDeniedAlert = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                FrostedCardStackView()

                CyclingTaglineView()
                    .padding(.top, 16)

                Spacer()

                Button(action: handleGetStartedAction) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.primary.opacity(0.9))
                        .foregroundColor(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 40)
            }
        }
        .task {
            await photoManager.checkCurrentStatus()
        }
        .alert("Photo Access Required", isPresented: $showPermissionDeniedAlert) {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This app needs access to your photos to help you organize and clean up your library. Please enable access in Settings.")
        }
    }

    private func handleGetStartedAction() {
        Task {
            if photoManager.authorizationStatus == .notDetermined {
                await photoManager.requestAuthorization()

                switch photoManager.authorizationStatus {
                case .authorized, .limited:
                    completeOnboarding()
                case .denied, .restricted:
                    showPermissionDeniedAlert = true
                default:
                    break
                }
            } else if photoManager.authorizationStatus == .authorized ||
                      photoManager.authorizationStatus == .limited {
                completeOnboarding()
            } else {
                showPermissionDeniedAlert = true
            }
        }
    }

    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.6)) {
            hasSeenOnboarding = true
        }
    }
}
