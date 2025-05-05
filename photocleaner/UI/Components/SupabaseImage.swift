import SwiftUI

/// A view that displays an image from Supabase storage with a local fallback
struct SupabaseImage: View {
    let imageName: String
    let bucketName: String
    let contentMode: ContentMode
    let shouldShowLoadingIndicator: Bool
    var onImageLoaded: ((Bool) -> Void)? // Callback for when image loads (true = from Supabase, false = fallback)
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    
    init(
        imageName: String,
        bucketName: String = "marketing",
        contentMode: ContentMode = .fit,
        showLoadingIndicator: Bool = true,
        onImageLoaded: ((Bool) -> Void)? = nil
    ) {
        self.imageName = imageName
        self.bucketName = bucketName
        self.contentMode = contentMode
        self.shouldShowLoadingIndicator = showLoadingIndicator
        self.onImageLoaded = onImageLoaded
    }
    
    var body: some View {
        Group {
            if let uiImage = image {
                // Successfully loaded from Supabase
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading && shouldShowLoadingIndicator {
                // Still loading and configured to show loading state
                ZStack {
                    Color.gray.opacity(0.1)
                    ProgressView()
                        .scaleEffect(0.7)
                }
            } else {
                // Either loading failed or we're configured to not show loading state
                // Local fallback image
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .onAppear {
                        if loadFailed {
                            print("⚠️ Using local fallback for \(imageName)")
                            onImageLoaded?(false) // Signal that we're using fallback
                        }
                    }
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        do {
            // Add a short delay to prevent frequent loading attempts
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 second
            
            // Attempt to load from Supabase
            if let supabaseImage = await SupabaseStorageService.shared.fetchImage(
                name: imageName, 
                from: bucketName
            ) {
                // Successfully loaded from Supabase
                await MainActor.run {
                    image = supabaseImage
                    isLoading = false
                    loadFailed = false
                    onImageLoaded?(true) // Signal successful load from Supabase
                }
            } else {
                // Failed to load from Supabase, will fall back to local image
                await MainActor.run {
                    isLoading = false
                    loadFailed = true
                    onImageLoaded?(false) // Signal that we're using fallback
                }
            }
        } catch {
            print("❌ Error in SupabaseImage loading task: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                loadFailed = true
                onImageLoaded?(false) // Signal that we're using fallback
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Show Supabase image with loading indicator
        Text("Supabase Image (with loading)")
            .font(.caption)
        
        SupabaseImage(imageName: "premium_alert_banner") { success in
            print("Image loaded from Supabase: \(success)")
        }
        .frame(width: 300, height: 150)
        .background(Color.gray.opacity(0.1))
        
        // Show Supabase image without loading indicator
        Text("Supabase Image (no loading)")
            .font(.caption)
        
        SupabaseImage(
            imageName: "premium_alert_banner",
            showLoadingIndicator: false
        )
        .frame(width: 300, height: 150)
        .background(Color.gray.opacity(0.1))
        
        // Show local image as reference
        Text("Local Image Reference")
            .font(.caption)
        
        Image("premium_alert_banner")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 300, height: 150)
            .background(Color.gray.opacity(0.1))
    }
    .padding()
} 