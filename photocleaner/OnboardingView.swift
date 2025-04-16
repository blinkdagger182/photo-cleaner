import SwiftUI
import AVKit
import Photos

// MARK: - Interactive Swipe Card Stack View
struct FrostedCardStackView: View {
    let images = ["image1", "image2", "image3"]
    @State private var topIndex: Int = 0

    var body: some View {
        VStack(spacing: -160) { // Stack upward
            ForEach(topIndex..<images.count, id: \.self) { index in
                let imageName = images[index]
                let isTopCard = index == topIndex

                SwipeCard(imageName: imageName, showOverlay: isTopCard) {
                    topIndex += 1
                }
                .zIndex(Double(images.count - index))
            }
            // Final Logo Text (not swipeable)
            Text("cln.")
                .font(.largeTitle.bold())
                .foregroundColor(.primary)
                .padding(.top, 12)
        }
        .padding(.top, 60)
    }
}

// MARK: - Swipe Card
struct SwipeCard: View {
    let imageName: String
    var showOverlay: Bool
    var onSwiped: () -> Void

    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 300, height: 180)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 36))
                .shadow(radius: 5)
                .overlay(
                    Group {
                        if showOverlay {
                            if offset.width + dragOffset.width > 60 {
                                SwipeTagLabel(text: "Keep", color: .green)
                            } else if offset.width + dragOffset.width < -60 {
                                SwipeTagLabel(text: "Delete", color: .red)
                            }
                        }
                    }, alignment: .topLeading
                )
                .offset(x: offset.width + dragOffset.width, y: offset.height)
                .rotationEffect(.degrees(Double(offset.width + dragOffset.width) / 20))
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            if abs(value.translation.width) > 100 {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    offset.width = value.translation.width > 0 ? 1000 : -1000
                                    onSwiped()
                                }
                            } else {
                                withAnimation(.spring()) {
                                    offset = .zero
                                }
                            }
                        }
                )
        }
    }
}

// MARK: - Swipe Tag Label
struct SwipeTagLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundColor(color)
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding()
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
