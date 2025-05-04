import SwiftUI
import Photos
import PhotosUI

/// A debugging view to isolate and test the LivePhoto functionality
struct LivePhotoDebugView: View {
    let asset: PHAsset
    let image: UIImage?
    
    @StateObject private var livePhotoLoader = LivePhotoLoader()
    @State private var isPlaying: Bool = false
    @State private var showLivePhoto: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Live Photo Debug View")
                .font(.headline)
            
            if asset.isLivePhoto {
                Text("This is a Live Photo")
                    .foregroundColor(.green)
            } else {
                Text("This is NOT a Live Photo")
                    .foregroundColor(.red)
            }
            
            ZStack {
                // Static image
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 400)
                        .opacity(showLivePhoto ? 0 : 1)
                        .cornerRadius(12)
                }
                
                // Live photo
                if let livePhoto = livePhotoLoader.livePhoto {
                    LivePhotoView(livePhoto: livePhoto, isPlaying: isPlaying)
                        .frame(height: 400)
                        .cornerRadius(12)
                        .opacity(showLivePhoto ? 1 : 0)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue, lineWidth: 2)
            )
            
            VStack(spacing: 12) {
                Button(action: {
                    print("📱 Debug: Toggle live photo playback")
                    if livePhotoLoader.livePhoto != nil {
                        isPlaying.toggle()
                        withAnimation(.spring()) {
                            showLivePhoto = isPlaying
                        }
                    } else {
                        print("📱 Debug: No live photo available to play")
                    }
                }) {
                    Text(isPlaying ? "Stop Live Photo" : "Play Live Photo")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    print("📱 Debug: Reload live photo")
                    let targetSize = CGSize(
                        width: asset.pixelWidth > 0 ? asset.pixelWidth : 1000,
                        height: asset.pixelHeight > 0 ? asset.pixelHeight : 1000
                    )
                    livePhotoLoader.loadLivePhoto(for: asset, targetSize: targetSize)
                }) {
                    Text("Reload Live Photo")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
                
                if livePhotoLoader.isLoading {
                    ProgressView()
                        .padding()
                }
                
                if let error = livePhotoLoader.error {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }
                
                Text("Is Live Photo Available: \(livePhotoLoader.livePhoto != nil ? "Yes" : "No")")
                    .padding()
            }
        }
        .padding()
        .onAppear {
            print("📱 Debug: LivePhotoDebugView appeared for asset \(asset.localIdentifier)")
            if asset.isLivePhoto {
                let targetSize = CGSize(
                    width: asset.pixelWidth > 0 ? asset.pixelWidth : 1000,
                    height: asset.pixelHeight > 0 ? asset.pixelHeight : 1000
                )
                print("📱 Debug: Loading live photo with size \(targetSize)")
                livePhotoLoader.loadLivePhoto(for: asset, targetSize: targetSize)
            }
        }
    }
}

/// A button that can be added to the SwipeCardView to navigate to the debug view
struct LivePhotoDebugButton: View {
    let asset: PHAsset
    let image: UIImage?
    @State private var showDebugView = false
    
    var body: some View {
        Button(action: {
            showDebugView = true
        }) {
            HStack {
                Image(systemName: "ladybug")
                Text("Debug")
            }
            .padding(8)
            .background(Color.black.opacity(0.7))
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .sheet(isPresented: $showDebugView) {
            LivePhotoDebugView(asset: asset, image: image)
        }
    }
} 