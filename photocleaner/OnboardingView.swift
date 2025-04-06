import SwiftUI
import AVKit

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var fadeIn = false
    @State private var fadeOut = false

    private let videoAspectRatio: CGFloat = 888.0 / 1208.0 // ≈ 0.735

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
                        withAnimation(.easeInOut(duration: 0.6)) {
                            fadeOut = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            hasSeenOnboarding = true
                        }
                    }) {
                        Text("Get started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.primary.opacity(0.9))
                            .foregroundColor(.white)
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
            }
        }
    }
}
