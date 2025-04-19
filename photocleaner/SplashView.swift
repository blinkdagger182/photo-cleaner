import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var toast: ToastService
    @EnvironmentObject var updateService: UpdateService
    @Environment(\.colorScheme) var colorScheme

    @State private var fadeOut = false
    @State private var showWord1 = false
    @State private var showWord2 = false
    @State private var showWord3 = false

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

                    HStack(spacing: 8) {
                        if showWord1 {
                            Text("Swipe")
                                .transition(.opacity)
                        }
                        if showWord2 {
                            Text("to")
                                .transition(.opacity)
                        }
                        if showWord3 {
                            Text("Clean")
                                .transition(.opacity)
                        }
                    }
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                    .opacity(fadeOut ? 0 : 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .ignoresSafeArea()
                .task {
                    // Staggered word-by-word soft fade
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showWord1 = true
                    }

                    try? await Task.sleep(nanoseconds: 500_000_000)
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showWord2 = true
                    }

                    try? await Task.sleep(nanoseconds: 500_000_000)
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showWord3 = true
                    }

                    await photoManager.checkCurrentStatus()

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
            OptionalUpdateSheet(notes: updateService.updateNotes) {
                updateService.dismissedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                updateService.shouldShowOptionalUpdate = false
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}
