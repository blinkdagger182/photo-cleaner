import SwiftUI
import AVKit
import Photos

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var fadeIn = false
    @State private var fadeOut = false
    @State private var showPermissionDeniedAlert = false
    
    @EnvironmentObject private var photoManager: PhotoManager

    private let videoAspectRatio: CGFloat = 766.0 / 1080.0 // ≈ 0.709

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer(minLength: 16)

                    Text("Welcome To")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Image("CLN")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 32))
                        .shadow(radius: 4)

                    // Calculate max video height based on total screen space
                    let maxVideoHeight = geometry.size.height * 0.25
                    let videoWidth = maxVideoHeight * videoAspectRatio

                    VideoPlayerView(fadeIn: $fadeIn, fadeOut: $fadeOut)
                        .frame(width: videoWidth, height: maxVideoHeight)
                        .cornerRadius(16)

                    Text("Swipe through your photos and clean up your library easily.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)

                    Spacer()

                    Button(action: {
                        Task {
                            // Check if we need to request permission
                            if photoManager.authorizationStatus == .notDetermined {
                                // Request photo library access
                                await photoManager.requestAuthorization()
                                
                                // Handle the result
                                switch photoManager.authorizationStatus {
                                case .authorized, .limited:
                                    // If authorized, complete onboarding
                                    completeOnboarding()
                                case .denied, .restricted:
                                    // If denied, show an alert
                                    showPermissionDeniedAlert = true
                                default:
                                    break
                                }
                            } else if photoManager.authorizationStatus == .authorized || 
                                      photoManager.authorizationStatus == .limited {
                                // Already authorized, just complete onboarding
                                completeOnboarding()
                            } else {
                                // Already denied, show the alert
                                showPermissionDeniedAlert = true
                            }
                        }
                    }) {
                        Text("Get started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.primary.opacity(0.9))
                            .foregroundColor(Color(UIColor.systemBackground))
                            .cornerRadius(16)
                            .padding(.horizontal, 32)
                    }
                    .opacity(fadeIn ? 1 : 0)
                    .padding(.bottom, 30)
                }
                .frame(width: geometry.size.width)
                .onAppear {
                    withAnimation(.easeIn(duration: 1.0)) {
                        fadeIn = true
                    }
                }
                .task {
                    // Delay checking photo library status until the view is fully appeared
                    // This prevents premature triggering of the system permission alert
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
        }
    }
    
    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.6)) {
            fadeOut = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            hasSeenOnboarding = true
        }
    }
}
