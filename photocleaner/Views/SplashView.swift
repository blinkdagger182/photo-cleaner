import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var isLoading = true
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
                // Initialize the tagline
                currentTagline = splashTaglines[currentIndex]

                // Rotate through taglines
                Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentIndex = (currentIndex + 1) % splashTaglines.count
                        currentTagline = splashTaglines[currentIndex]
                    }
                }

                // Request photo authorization
                await coordinator.photoManager.requestAuthorization()

                // Check app version
                await coordinator.updateService.checkAppVersion()
                
                // Show force update if needed
                if coordinator.updateService.shouldForceUpdate {
                    coordinator.modalCoordinator.showForceUpdate(notes: coordinator.updateService.updateNotes)
                } else if coordinator.updateService.shouldShowOptionalUpdate {
                    coordinator.modalCoordinator.showOptionalUpdate(notes: coordinator.updateService.updateNotes) {
                        coordinator.updateService.dismissedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                        coordinator.updateService.shouldShowOptionalUpdate = false
                    }
                }

                // Wait for splash duration
                try? await Task.sleep(nanoseconds: 4_000_000_000)

                // Fade out animation
                withAnimation(.easeOut(duration: 0.5)) {
                    fadeOut = true
                }

                // Wait for fade out to complete
                try? await Task.sleep(nanoseconds: 500_000_000)

                // Navigate to main content
                coordinator.completeStartup()
            }
        }
        .withModalCoordination(coordinator.modalCoordinator)
    }
}
