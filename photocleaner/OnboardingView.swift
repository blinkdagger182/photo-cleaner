import SwiftUI
import AVKit
import Photos

// MARK: - Interactive Swipe Card Stack View
struct FrostedCardStackView: View {
    let images = ["onboard-1", "image2", "image3"]
    @State private var topIndex: Int = 0
    @State private var removedIndices: Set<Int> = []
    
    // Configuration for card stacking effect
    private let cardOffset: CGFloat = -20
    private let cardScale: CGFloat = 0.05

    var body: some View {
        GeometryReader { geometry in
            containerView(geometry: geometry)
        }
    }
    
    private func containerView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Stack of cards
            cardsView(geometry: geometry)
            
            // Final logo when finished
            logoView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, geometry.size.height * 0.05)
    }
    
    private func cardsView(geometry: GeometryProxy) -> some View {
        ForEach(0..<images.count, id: \.self) { index in
            if index >= topIndex && index < topIndex + 3 {
                cardView(for: index, geometry: geometry)
            }
        }
    }
    
    private func cardView(for index: Int, geometry: GeometryProxy) -> some View {
        let stackPosition = index - topIndex
        let imageName = images[index]
        let isTopCard = index == topIndex
        
        return SwipeCard(
            imageName: imageName,
            showOverlay: isTopCard,
            cardPosition: stackPosition,
            screenSize: geometry.size
        ) {
            // Mark this card as removed and animate next card
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                removedIndices.insert(index)
                topIndex += 1
            }
        }
        .scaleEffect(1 - CGFloat(stackPosition) * cardScale)
        .offset(y: CGFloat(stackPosition) * cardOffset)
        .shadow(
            color: .black.opacity(0.2),
            radius: 5,
            x: 0,
            y: 6 + CGFloat(stackPosition) * 2
        )
        .zIndex(Double(100 - index))
        .disabled(!isTopCard)
    }
    
    @ViewBuilder
    private var logoView: some View {
        if topIndex >= images.count {
            VStack {
                Image("CLN")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(radius: 8)
                    .transition(.scale.combined(with: .opacity))
                
                Text("Designed for peace of mind.")
                    .font(.title2)
                    .fontWeight(.medium)
                    .padding(.top)
            }
            .transition(.opacity)
            .animation(.easeInOut, value: topIndex)
        }
    }
}

// MARK: - Swipe Card
struct SwipeCard: View {
    let imageName: String
    var showOverlay: Bool
    var cardPosition: Int // Position in stack (0 = top)
    var screenSize: CGSize
    var onSwiped: () -> Void

    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    // Card dimensions with 4:5 ratio - using fixed width
    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 375 // 4:5 ratio (300 * 1.25)
    
    // Calculate current offset and rotation
    private var currentOffset: CGSize {
        CGSize(
            width: offset.width + (isDragging ? dragOffset.width : 0),
            height: 0 // Keep fixed vertical position
        )
    }
    
    private var currentRotation: Double {
        Double(currentOffset.width) / 20
    }
    
    // Calculate UI states based on drag amount
    private var dragPercentage: CGFloat {
        let maxDrag: CGFloat = 100
        let percentage = abs(currentOffset.width) / maxDrag
        return min(percentage, 1.0)
    }
    
    // Opacity for tags
    private var tagOpacity: CGFloat {
        min(dragPercentage * 2, 1.0)
    }
    
    // Card depth appearance based on position
    private var cardOpacity: Double {
        showOverlay ? 1.0 : 1.0 - Double(cardPosition) * 0.15
    }
    
    // Card border width variation
    private var cardBorderWidth: CGFloat {
        showOverlay ? 1.5 : 1.0
    }

    var body: some View {
        mainCardView
            .offset(x: currentOffset.width, y: 0)
            .rotationEffect(.degrees(currentRotation))
            .gesture(dragGestureProvider)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: dragOffset)
    }
    
    // Main card view with all overlays
    private var mainCardView: some View {
        cardContainer
            .overlay(alignment: .topLeading) { keepLabel }
            .overlay(alignment: .topTrailing) { deleteLabel }
            .frame(maxWidth: .infinity)
    }
    
    // Card container with content
    private var cardContainer: some View {
        ZStack {
            // Card background
            // RoundedRectangle(cornerRadius: 36)
            //     .fill(Color.white.opacity(0.8))
            //     .shadow(radius: 5)
            
            // Card content image
            cardImage
        }
        .frame(maxWidth: .infinity)
    }
    
    // Card content image
    private var cardImage: some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: cardWidth, height: cardHeight)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 36))
            .overlay(
                RoundedRectangle(cornerRadius: 36)
                    .stroke(Color.white.opacity(0.6), lineWidth: cardBorderWidth)
            )
            .opacity(cardOpacity)
    }
    
    // Keep label overlay
    @ViewBuilder
    private var keepLabel: some View {
        if currentOffset.width > 0 {
            SwipeTagLabel(text: "KEEP", color: .green, angle: -15, xOffset: 20)
                .opacity(tagOpacity)
                .animation(.easeOut(duration: 0.2), value: tagOpacity)
        }
    }
    
    // Delete label overlay
    @ViewBuilder
    private var deleteLabel: some View {
        if currentOffset.width < 0 {
            SwipeTagLabel(text: "DELETE", color: .red, angle: 15, xOffset: -20)
                .opacity(tagOpacity)
                .animation(.easeOut(duration: 0.2), value: tagOpacity)
        }
    }
    
    // Drag gesture provider
    private var dragGestureProvider: some Gesture {
        showOverlay ?
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                    isDragging = true
                }
                .onEnded(handleDragGestureEnd) : nil
    }
    
    // Handle the end of drag gesture
    private func handleDragGestureEnd(value: DragGesture.Value) {
        isDragging = false
        
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
            .offset(x: xOffset, y: 20) // Position slightly down from the top edge of the card
    }
}

// MARK: - Cycling Tagline View
struct CyclingTaglineView: View {
    @State private var currentIndex = 0
    
    // Use static for the taglines array
    private static let taglines = [
        "Swipe left to delete.",
        "Swipe right to keep.",
        "Clean your gallery in minutes."
    ]
    
    // Computed property for current tagline
    private var currentTagline: String {
        Self.taglines[currentIndex]
    }

    var body: some View {
        taglineText
            .onAppear(perform: startTaglineTimer)
    }
    
    // Extracted text view
    private var taglineText: some View {
        Text(currentTagline)
            .font(.title3)
            .fontWeight(.medium)
            .foregroundColor(.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal)
    }
    
    // Timer start function
    private func startTaglineTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                currentIndex = (currentIndex + 1) % Self.taglines.count
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
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                contentView(geometry: geometry)
            }
        }
        .task {
            await photoManager.checkCurrentStatus()
        }
        .alert("Photo Access Required", isPresented: $showPermissionDeniedAlert) {
            permissionAlertButtons
        } message: {
            Text("This app needs access to your photos to help you organize and clean up your library. Please enable access in Settings.")
        }
    }
    
    // Main content view
    private func contentView(geometry: GeometryProxy) -> some View {
        VStack {
            // Card stack with adaptive height
            FrostedCardStackView()
                .frame(height: geometry.size.height * 0.6)
            
            // Centered tagline with proper spacing
            CyclingTaglineView()
                .padding(.top, 30)
                .padding(.horizontal)
            
            Spacer()
            
            // Get started button
            getStartedButton
        }
        .padding(.top, geometry.size.height * 0.05)
    }
    
    // Get started button
    private var getStartedButton: some View {
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
    
    // Permission alert buttons
    private var permissionAlertButtons: some View {
        Group {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
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

// Add this right before your #Preview
extension PhotoManager {
    static var preview: PhotoManager {
        let manager = PhotoManager()
        // Set any needed initial state for preview here
        return manager
    }
}

extension ToastService {
    static var preview: ToastService {
        let service = ToastService()
        // Set any needed initial state for preview here
        return service
    }
}

#Preview {
    OnboardingView()
        .environmentObject(PhotoManager.preview)
        .environmentObject(ToastService.preview)
}
