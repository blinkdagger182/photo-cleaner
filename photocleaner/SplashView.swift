import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var toast: ToastService
    @EnvironmentObject var updateService: UpdateService
    @Environment(\.colorScheme) var colorScheme

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
        "It's cln. time."
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
                    Image("CLN")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 50)
                        .opacity(fadeOut ? 0 : 1)

                    Text(currentTagline)
                        .font(.headline)
                        .foregroundColor(.primary) // Automatically adapts to dark/light
                        .transition(.opacity)
                        .id(currentTagline)
                        .opacity(fadeOut ? 0 : 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground)) // Adaptive background
                .ignoresSafeArea()
                .task {
                    currentTagline = splashTaglines[currentIndex]

                    Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentIndex = (currentIndex + 1) % splashTaglines.count
                            currentTagline = splashTaglines[currentIndex]
                        }
                    }

                    // We only check status here, not request permission
                    // For returning users, we'll request if needed in ContentView
                    await photoManager.checkCurrentStatus()

                    try? await Task.sleep(nanoseconds: 4_000_000_000)

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
        .fullScreenCover(isPresented: $updateService.shouldForceUpdate) {
            ForceUpdateOverlayView(notes: updateService.updateNotes)
        }
        .interactiveDismissDisabled(true)

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
