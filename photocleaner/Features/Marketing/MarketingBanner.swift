import SwiftUI

struct MarketingBanner: View {
    var onTap: () -> Void
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main banner content
            Button(action: onTap) {
                HStack(spacing: 16) {
                    // Logo/Icon section
                    Image("smartalbums_image")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                    
                    // Text content
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLN. Discover")
                            .font(.headline)
                            .foregroundColor(.yellow)
                        
                        Text("Your memories, magically sorted. Just one tap away.")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    // CTA Button
                    Text("Get started")
                        .font(.callout)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.mint)
                        .foregroundColor(.black)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Image("gradient-background")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 16)
    }
}

// Scale animation for the button


#Preview {
    VStack {
        Spacer()
        MarketingBanner {
            print("Banner tapped")
        } onDismiss: {
            print("Banner dismissed")
        }
        Spacer()
    }
    .background(Color.gray.opacity(0.2))
}

struct PremiumAlertBanner: View {
    var onTap: () -> Void
    var onDismiss: () -> Void
    @Binding var showPaywall: Bool
    
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @State private var isLoading = true
    @State private var hasLoadedImage = false
    
    // Thresholds
    private let dismissThreshold: CGFloat = 150
    private let velocityThreshold: CGFloat = 1000

    var body: some View {
        ZStack {
            // Full screen overlay to capture taps outside the banner
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onDismiss()
                }
            
            // Main banner content
            Button(action: {
                onDismiss()
                onTap()
            }) {
                VStack(spacing: 12) {
                    // Use either Supabase image or local fallback
                    Group {
                        if isLoading {
                            // Show loading indicator while we're checking
                            ProgressView()
                                .frame(width: 280, height: 150)
                                .background(Color.gray.opacity(0.1))
                        } else {
                            // Either Supabase image loaded or fallback
                            Image("premium_alert_banner")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 280)
                        }
                    }
                    
                    Text("View Collections")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.mint)
                        .foregroundColor(.black)
                        .cornerRadius(20)

                    Text("Swipe To Dismiss")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.bottom, 4)
                }
                .background(Color.white.opacity(0.9))
                .cornerRadius(24)
                .padding()
                .shadow(radius: 8)
            }
            .buttonStyle(ScaleButtonStyle())
            .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        let totalOffset = CGSize(
                            width: offset.width + value.translation.width,
                            height: offset.height + value.translation.height
                        )

                        let velocity = sqrt(pow(value.predictedEndTranslation.width, 2) + pow(value.predictedEndTranslation.height, 2))

                        if abs(totalOffset.width) > dismissThreshold || abs(totalOffset.height) > dismissThreshold || velocity > velocityThreshold {
                            withAnimation(.easeOut(duration: 0.3)) {
                                offset = CGSize(
                                    width: value.translation.width > 0 ? 1000 : -1000,
                                    height: value.translation.height > 0 ? 1000 : -1000
                                )
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onDismiss()
                            }
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                offset = .zero
                            }
                        }
                    }
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: dragOffset)
            .task {
                // Check if image exists but limit the loading time
                // After 1.5 seconds max, show the fallback
                let imageExists = await withTimeout(seconds: 1.5) {
                    await SupabaseStorageService.shared.imageExists(name: "premium_alert_banner", in: "marketing")
                }
                
                // Set loading to false regardless of result
                isLoading = false
                hasLoadedImage = true
                
                // Debug the result
                print("🔍 Image exists check result: \(imageExists)")
            }
        }
    }
    
    /// Run an async task with a timeout
    private func withTimeout<T>(seconds: Double, task: @escaping () async -> T) async -> T? {
        return await withTaskGroup(of: Optional<T>.self) { group in
            // Add the actual task
            group.addTask {
                return await task()
            }
            
            // Add a timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            
            // Return the first non-nil result or nil if timeout
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }
            
            return nil
        }
    }
}
