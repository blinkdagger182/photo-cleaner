import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @StateObject private var photoManager = PhotoManager()
    @StateObject private var toast = ToastService()
    @EnvironmentObject var updateService: UpdateService

    @State private var fadeOut = false

    // Tagline rotation
    @State private var splashTaglines = [
        "Bye, clutter.",
        "Make space. Keep memories.",
        "So fresh. So cln.",
        "Storage? Sorted.",
        "Tap. Swipe. Clear.",
        "Lighten up.",
        "Clean phone. Clear mind.",
        "cln. starts now.",
        "It’s cln. time."
    ]
    @State private var currentIndex = 0
    @State private var currentTagline = ""

    var body: some View {
        ZStack {
            if isActive {
                ContentView()
                    .environmentObject(photoManager)
                    .environmentObject(toast)
                    .transition(.opacity)
            } else {
                VStack(spacing: 16) {
                    Image("splashscreen")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .opacity(fadeOut ? 0 : 1)

                    Text(currentTagline)
                        .font(.headline)
                        .transition(.opacity)
                        .id(currentTagline)
                        .opacity(fadeOut ? 0 : 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .ignoresSafeArea()
                .task {
                    // Set first tagline
                    currentTagline = splashTaglines[currentIndex]

                    // Rotate taglines every 1.5 seconds
                    Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentIndex = (currentIndex + 1) % splashTaglines.count
                            currentTagline = splashTaglines[currentIndex]
                        }
                    }

                    // Request permissions
                    await photoManager.requestAuthorization()

                    // Show splash for 4 seconds
                    try? await Task.sleep(nanoseconds: 4_000_000_000)

                    // Fade out animation
                    withAnimation(.easeOut(duration: 0.5)) {
                        fadeOut = true
                    }

                    try? await Task.sleep(nanoseconds: 500_000_000)

                    withAnimation {
                        isActive = true
                    }
                }
            }
        }

        // 🚫 Force update: full-screen & undismissable
        .fullScreenCover(isPresented: $updateService.shouldForceUpdate) {
            ForceUpdateOverlayView(notes: updateService.updateNotes)
        }
        .interactiveDismissDisabled(true) // applies to fullScreenCover

        // ⚠️ Optional update: dismissible
        .sheet(isPresented: $updateService.shouldShowOptionalUpdate) {
            OptionalUpdateSheet(
                notes: updateService.updateNotes
            ) {
                updateService.dismissedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                updateService.shouldShowOptionalUpdate = false
            }
        }

        .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}
