import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @StateObject private var photoManager = PhotoManager()
    @StateObject var toast = ToastService()
    @State private var fadeOut = false

    var body: some View {
        ZStack {
            if isActive {
                ContentView()
                    .environmentObject(photoManager)
                    .environmentObject(toast)
                    .transition(.opacity) // smooth fade
            } else {
                VStack {
                    Image("splashscreen")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .opacity(fadeOut ? 0 : 1)
                    Text("Finding you good news...")
                        .font(.headline)
                        .opacity(fadeOut ? 0 : 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .ignoresSafeArea()
                .task {
                    await photoManager.requestAuthorization()

                    try? await Task.sleep(nanoseconds: 2_000_000_000)

                    // Smooth fade out before switching
                    withAnimation(.easeOut(duration: 0.5)) {
                        fadeOut = true
                    }

                    // Wait a bit for the fade animation to finish
                    try? await Task.sleep(nanoseconds: 500_000_000)

                    withAnimation {
                        isActive = true
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}
