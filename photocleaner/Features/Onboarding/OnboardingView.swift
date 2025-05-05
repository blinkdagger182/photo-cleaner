import SwiftUI
import AVKit
import Photos

// MARK: - Interactive Swipe Card Stack View
struct FrostedCardStackView: View {
    let images = ["onboard-1", "onboard-2", "onboard-3"]
    @State private var topIndex: Int = 0
    @State private var removedIndices: Set<Int> = []
    
    // Configuration for card stacking effect
    private let cardOffset: CGFloat = -30
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
    
    // Animation hint states
    @State private var isShowingLeftHint = false
    @State private var isShowingRightHint = false
    @State private var animationOffset: CGFloat = 0
    @State private var animationLoopCount = 0
    @State private var animationTimer: Timer?

    // Card dimensions with 4:5 ratio - using fixed width
    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 375 // 4:5 ratio (300 * 1.25)
    
    // Animation configurations
    private let hintAnimationOffset: CGFloat = 40
    private let animationDelay: Double = 0.7
    private let animationDuration: Double = 0.6
    private let pauseBetweenAnimations: Double = 5.0 // Longer pause between animation cycles
    private let maxAnimationLoops = 3 // Show animation a maximum of 3 times
    
    // Calculate current offset and rotation
    private var currentOffset: CGSize {
        CGSize(
            width: offset.width + (isDragging ? dragOffset.width : 0) + animationOffset,
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
    
    // Opacity for tags - now considers hint animation states
    private var tagOpacity: CGFloat {
        if isShowingLeftHint || isShowingRightHint {
            return 1.0
        }
        return min(dragPercentage * 2, 1.0)
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
            .onAppear {
                // Only show animation hint for the top card
                if showOverlay && cardPosition == 0 {
                    startHintAnimation()
                }
            }
            .onDisappear {
                // Stop the animation timer when the view disappears
                animationTimer?.invalidate()
                animationTimer = nil
            }
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
        if currentOffset.width > 0 || isShowingRightHint {
            SwipeTagLabel(text: "KEEP", color: .green, angle: -15, xOffset: 20)
                .opacity(tagOpacity)
                .animation(.easeOut(duration: 0.2), value: tagOpacity)
        }
    }
    
    // Delete label overlay
    @ViewBuilder
    private var deleteLabel: some View {
        if currentOffset.width < 0 || isShowingLeftHint {
            SwipeTagLabel(text: "DELETE", color: .red, angle: 15, xOffset: -20)
                .opacity(tagOpacity)
                .animation(.easeOut(duration: 0.2), value: tagOpacity)
        }
    }
    
    // Right arrow hint overlay
    @ViewBuilder
    private var rightArrowHint: some View {
        if isShowingRightHint {
            Image(systemName: "chevron.right")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.green)
                .padding(.trailing, 30)
                .opacity(tagOpacity)
                .transition(.opacity)
        }
    }
    
    // Left arrow hint overlay
    @ViewBuilder
    private var leftArrowHint: some View {
        if isShowingLeftHint {
            Image(systemName: "chevron.left")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.red)
                .padding(.leading, 30)
                .opacity(tagOpacity)
                .transition(.opacity)
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
    
    // Start the hint animation sequence
    private func startHintAnimation() {
        // Initial delay before first animation
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay) {
            runAnimationSequence()
        }
    }
    
    // Run a single animation sequence (left, center, right, center)
    private func runAnimationSequence() {
        // Don't run more animations if the user has started dragging
        guard !isDragging && animationLoopCount < maxAnimationLoops else { return }
        
        // 1. Animate to the left
        withAnimation(.easeInOut(duration: animationDuration)) {
            animationOffset = -hintAnimationOffset
            isShowingLeftHint = true
        }
        
        // 2. Animate back to center
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                animationOffset = 0
                isShowingLeftHint = false
            }
            
            // 3. Animate to the right
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: animationDuration)) {
                    animationOffset = hintAnimationOffset
                    isShowingRightHint = true
                }
                
                // 4. Animate back to center
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.3) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        animationOffset = 0
                        isShowingRightHint = false
                    }
                    
                    // Increment the loop count
                    animationLoopCount += 1
                    
                    // Schedule the next animation with increasing pause duration
                    let adjustedPause = pauseBetweenAnimations + Double(animationLoopCount) * 2.0
                    
                    // Schedule next animation cycle if we haven't reached the maximum
                    if animationLoopCount < maxAnimationLoops {
                        animationTimer?.invalidate()
                        animationTimer = Timer.scheduledTimer(withTimeInterval: adjustedPause, repeats: false) { _ in
                            runAnimationSequence()
                        }
                    }
                }
            }
        }
    }
    
    // Handle the end of drag gesture - also stop animation cycles
    private func handleDragGestureEnd(value: DragGesture.Value) {
        isDragging = false
        
        // Stop animation cycles when user interacts
        animationTimer?.invalidate()
        animationTimer = nil
        animationLoopCount = maxAnimationLoops // Prevent further animations
        
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
    @EnvironmentObject private var toastService: ToastService
    @State private var photoCount: Int = 0
    @State private var showPermissionDeniedAlert = false
    @State private var currentPage = 0
    @State private var isCompletingOnboarding = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                if isCompletingOnboarding {
                    // This is a temporary view shown while transitioning to the main app
                    // It prevents the TabView from resetting to the first page
                    Color(.systemBackground).ignoresSafeArea()
                } else {
                    TabView(selection: $currentPage) {
                        IntroPageView(goToNextPage: goToNextPage)
                            .tag(0)
                        
                        PermissionPageView(goToNextPage: requestPhotoPermission)
                            .tag(1)
                        
                        SwipeTutorialPageView(photoCount: photoCount, onGetStarted: handleGetStarted)
                            .tag(2)
                    }
                    .tabViewStyle(.page)
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
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
    
    private func goToNextPage() {
        withAnimation {
            currentPage += 1
        }
    }
    
    private func requestPhotoPermission() {
        Task {
            if photoManager.authorizationStatus == .notDetermined {
                await photoManager.requestAuthorization()
                
                switch photoManager.authorizationStatus {
                case .authorized, .limited:
                    await fetchPhotoCount()
                    goToNextPage()
                case .denied, .restricted:
                    showPermissionDeniedAlert = true
                default:
                    break
                }
            } else if photoManager.authorizationStatus == .authorized ||
                      photoManager.authorizationStatus == .limited {
                await fetchPhotoCount()
                goToNextPage()
            } else {
                showPermissionDeniedAlert = true
            }
        }
    }
    
    private func fetchPhotoCount() async {
        let fetchOptions = PHFetchOptions()
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        photoCount = result.count
    }

    private func handleGetStarted() {
        // First, set the flag to prevent TabView from resetting
        withAnimation {
            isCompletingOnboarding = true
        }
        
        // Check if we already have permission, otherwise request it first
        Task {
            if photoManager.authorizationStatus == .notDetermined {
                await photoManager.requestAuthorization()
                
                // After permission request, fetch photo count if granted
                if photoManager.authorizationStatus == .authorized || 
                   photoManager.authorizationStatus == .limited {
                    await fetchPhotoCount()
                    completeOnboarding()
                } else {
                    // Reset the completion flag if we need to show an alert
                    isCompletingOnboarding = false
                    showPermissionDeniedAlert = true
                }
            } else if photoManager.authorizationStatus == .authorized || 
                      photoManager.authorizationStatus == .limited {
                // Permission already granted, complete onboarding
                completeOnboarding()
            } else {
                // Reset the completion flag if we need to show an alert
                isCompletingOnboarding = false
                showPermissionDeniedAlert = true
            }
        }
    }
    
    private func completeOnboarding() {
        // Add a small delay to ensure smooth transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Set hasSeenOnboarding to true to trigger the app's navigation to the main interface
            withAnimation(.easeInOut(duration: 0.6)) {
                hasSeenOnboarding = true
            }
            
            if photoCount > 0 {
                let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: photoCount), number: .decimal)
                toastService.showInfo("You've got \(formattedCount) photos. Let's get started.")
            }
        }
    }
}

// MARK: - Page Views
struct IntroPageView: View {
    var goToNextPage: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 30) {
                Spacer()
                
                Image("CLN")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(radius: 8)
                
                Text("Welcome to cln.")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                
                Text("The average person has over 10,000 photos on their phone.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Spacer()
                
                Button(action: goToNextPage) {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.primary.opacity(0.9))
                        .foregroundColor(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .frame(width: geometry.size.width)
        }
    }
}

struct PermissionPageView: View {
    var goToNextPage: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 30) {
                Spacer()
                
                Image("smartalbums_image")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150, height: 150)
                
                Text("Photo Access")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                
                Text("We need access to your photo library to help you clean it. You'll stay in full control.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Spacer()
                
                Button(action: goToNextPage) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.primary.opacity(0.9))
                        .foregroundColor(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .frame(width: geometry.size.width)
        }
    }
}

struct SwipeTutorialPageView: View {
    var photoCount: Int
    var onGetStarted: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Text("This is just a demo. No photos will be deleted yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
                
                // Card stack with adaptive height
                FrostedCardStackView()
                    .frame(height: geometry.size.height * 0.6)
                
                // Centered tagline with proper spacing
                CyclingTaglineView()
                    .padding(.top, 10)
                    .padding(.horizontal)
                
                Spacer()
                
                // Photo count display
                if photoCount > 0 {
                    let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: photoCount), number: .decimal)
                    Text("You've got \(formattedCount) photos. Let's get started.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 10)
                }
                
                // Get started button
                Button(action: onGetStarted) {
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
            .frame(width: geometry.size.width)
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
