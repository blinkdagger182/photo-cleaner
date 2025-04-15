import SwiftUI
import AVKit
import Photos

// MARK: - Onboarding Problem Page
struct OnboardingProblemPageView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
                Spacer()

                Text("Welcome To")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            
            
                Spacer(minLength: 16)

                HStack {
                    Spacer()
                    Image("CLN")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 36))
                        .shadow(radius: 5)
                    Spacer()
                }
            
            
                Spacer(minLength: 200)
        }
        .padding(.horizontal)
    }
}

// MARK: - Onboarding Solution Page
struct OnboardingSolutionPageView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("Your Gallery's a Mess...")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Image("problem_image")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 250)
                .padding(.horizontal, 32)
            
            Text("We get it. Your camera roll is packed, but don't worry — we've got your back.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Get Started Page
struct OnboardingGetStartedPageView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @EnvironmentObject private var photoManager: PhotoManager
    @State private var fadeIn = false
    @State private var fadeOut = false
    @State private var showPermissionDeniedAlert = false
    @Binding var triggerAction: Bool
    
    private let videoAspectRatio: CGFloat = 766.0 / 1080.0 // ≈ 0.709
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                Spacer()
                
                Text("Swipe to Clean")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Image("solution_image")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 250)
                    .padding(.horizontal, 32)
                
                Text("Left to delete. Right to keep. \n Every photo gets a second chance — but only if you want it to. ")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Spacer()

                // Calculate max video height based on total screen space
                let maxVideoHeight = geometry.size.height * 0.25
                let videoWidth = maxVideoHeight * videoAspectRatio

                VideoPlayerView(fadeIn: $fadeIn, fadeOut: $fadeOut)
                    .frame(width: videoWidth, height: maxVideoHeight)
                    .cornerRadius(16)

                Text("Your camera roll, cleaner. Your mind, lighter. \n Tap 'Let's Start' and begin swiping your way to clarity.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .onAppear {
                withAnimation(.easeIn(duration: 1.0)) {
                    fadeIn = true
                }
            }
            .onChange(of: triggerAction) { newValue in
                if newValue {
                    handleGetStartedAction()
                    triggerAction = false
                }
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
    
    private func handleGetStartedAction() {
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

// MARK: - Main Onboarding Container
struct OnboardingView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @State private var currentPage = 0
    @State private var triggerGetStarted = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            VStack {
                TabView(selection: $currentPage) {
                    OnboardingProblemPageView()
                        .tag(0)
                    
                    OnboardingSolutionPageView()
                        .tag(1)
                    
                    OnboardingGetStartedPageView(triggerAction: $triggerGetStarted)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Spacer()

                Button(action: {
                    if currentPage < 2 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        triggerGetStarted = true
                    }
                }) {
                    Text(currentPage == 2 ? "Get Started" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.primary.opacity(0.9))
                        .foregroundColor(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 30)
            }
        }
        .task {
            // Check current authorization status without requesting
            await photoManager.checkCurrentStatus()
        }
    }
}
