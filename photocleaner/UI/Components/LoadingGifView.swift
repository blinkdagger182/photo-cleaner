import SwiftUI
import UIKit
import ImageIO
import Foundation

struct LoadingGifView: View {
    let size: CGFloat
    
    init(size: CGFloat = 100) {
        self.size = size
    }
    
    var body: some View {
        ZStack {
            if let gifData = loadGifData() {
                // Try UIKit approach first, maintain original gif proportions
                GifImageView(data: gifData)
                    .frame(maxWidth: size, maxHeight: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Fallback to animated pulse effect for a nice loading experience
                AnimatedLoadingFallback(size: size)
            }
        }
    }
    
    private func loadGifData() -> Data? {
        // Try loading from dataset first
        if let dataAsset = NSDataAsset(name: "loading") {
            print("✅ Successfully loaded loading gif from dataset")
            return dataAsset.data
        }
        
        // Fallback: try loading as regular bundle resource
        guard let url = Bundle.main.url(forResource: "loading", withExtension: "gif") else {
            print("⚠️ Could not find loading.gif in bundle or dataset")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            print("✅ Successfully loaded loading gif from bundle")
            return data
        } catch {
            print("⚠️ Could not load loading.gif data: \(error)")
            return nil
        }
    }
}

struct GifImageView: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor.clear
        imageView.clipsToBounds = true
        
        // Create animated image from GIF data
        let cfData = data as CFData
        if let source = CGImageSourceCreateWithData(cfData, nil) {
            let frameCount = CGImageSourceGetCount(source)
            var images: [UIImage] = []
            var totalDuration: TimeInterval = 0
            
            for i in 0..<frameCount {
                if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                    let image = UIImage(cgImage: cgImage)
                    images.append(image)
                    
                    // Get frame duration
                    if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                       let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                        let frameDuration = gifDict[kCGImagePropertyGIFDelayTime] as? TimeInterval ?? 0.1
                        totalDuration += frameDuration
                    }
                }
            }
            
            if !images.isEmpty {
                imageView.animationImages = images
                imageView.animationDuration = max(totalDuration, 1.0) // Minimum 1 second
                imageView.animationRepeatCount = 0 // Infinite loop
                imageView.startAnimating()
                
                // Set intrinsic content size to original gif dimensions
                if let firstImage = images.first {
                    imageView.frame.size = firstImage.size
                }
                
                print("✅ Started animating GIF with \(images.count) frames, duration: \(totalDuration)s")
            } else {
                print("⚠️ Could not extract frames from GIF")
                // Fallback to static image
                imageView.image = UIImage(data: data)
            }
        } else {
            print("⚠️ Could not create image source from GIF data")
            // Try loading as static image
            imageView.image = UIImage(data: data)
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        // Ensure animation is running
        if !uiView.isAnimating && uiView.animationImages != nil {
            uiView.startAnimating()
        }
    }
}

struct AnimatedLoadingFallback: View {
    let size: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Pulsing circles
            ForEach(0..<3) { index in
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    .frame(width: size * 0.6, height: size * 0.6)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
                    .opacity(isAnimating ? 0.1 : 0.8)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.3),
                        value: isAnimating
                    )
            }
            
            // Center icon
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: size * 0.3, weight: .light))
                .foregroundColor(.blue)
                .opacity(0.7)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LoadingGifView(size: 100)
            .frame(width: 200, height: 200)
            .background(Color.gray.opacity(0.1))
        
        AnimatedLoadingFallback(size: 100)
            .frame(width: 200, height: 200)
            .background(Color.gray.opacity(0.1))
    }
} 