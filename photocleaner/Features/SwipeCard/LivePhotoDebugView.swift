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
    @State private var isLongPressing: Bool = false
    @State private var showLog: Bool = false
    @State private var logs: [String] = []
    
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        logs.append(logEntry)
        
        // Limit log entries to prevent performance issues
        if logs.count > 100 {
            logs.removeFirst(logs.count - 100)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Live Photo Debug View")
                    .font(.headline)
                
                assetInfoSection
                
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
                    
                    // Long press test overlay
                    Color.clear
                        .frame(height: 400)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.3)
                                .onChanged { isPressing in
                                    addLog("Long press state changed to: \(isPressing)")
                                    isLongPressing = isPressing
                                    
                                    if isPressing && livePhotoLoader.livePhoto != nil {
                                        isPlaying = true
                                        withAnimation(.spring()) {
                                            showLivePhoto = true
                                        }
                                    } else if !isPressing {
                                        isPlaying = false
                                        withAnimation(.spring()) {
                                            showLivePhoto = false
                                        }
                                    }
                                }
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isLongPressing ? Color.red : Color.blue, lineWidth: 2)
                )
                
                controlsSection
                
                // Log toggle button
                Button(action: {
                    withAnimation {
                        showLog.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: "terminal")
                        Text(showLog ? "Hide Debug Log" : "Show Debug Log")
                    }
                    .padding(8)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                // Debug log
                if showLog {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Debug Log")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: {
                                logs.removeAll()
                                addLog("Log cleared")
                            }) {
                                Text("Clear")
                                    .font(.caption)
                                    .padding(4)
                                    .background(Color.red.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(logs.reversed(), id: \.self) { log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding()
        }
        .onAppear {
            addLog("LivePhotoDebugView appeared for asset \(asset.localIdentifier)")
            if asset.isLivePhoto {
                // Use a more reasonable target size for better performance
                let targetSize = CGSize(
                    width: min(asset.pixelWidth, 1080),
                    height: min(asset.pixelHeight, 1080)
                )
                addLog("Loading live photo with size \(targetSize)")
                livePhotoLoader.loadLivePhoto(for: asset, targetSize: targetSize)
            }
        }
    }
    
    // MARK: - Asset Info Section
    private var assetInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(asset.isLivePhoto ? "This is a Live Photo" : "This is NOT a Live Photo")
                    .foregroundColor(asset.isLivePhoto ? .green : .red)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("Media Type: \(mediaTypeString(asset.mediaType))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("Asset ID:").gridColumnAlignment(.trailing)
                    Text(asset.localIdentifier)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                GridRow {
                    Text("Size:")
                    Text("\(asset.pixelWidth) × \(asset.pixelHeight) px")
                }
                
                if let creationDate = asset.creationDate {
                    GridRow {
                        Text("Created:")
                        Text(creationDate, style: .date)
                    }
                }
                
                if asset.duration > 0 {
                    GridRow {
                        Text("Duration:")
                        Text(asset.durationText ?? "Unknown")
                    }
                }
            }
            .font(.caption)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Controls Section
    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Manual playback button
                Button(action: {
                    addLog("Manual toggle live photo playback")
                    if livePhotoLoader.livePhoto != nil {
                        isPlaying.toggle()
                        withAnimation(.spring()) {
                            showLivePhoto = isPlaying
                        }
                    } else {
                        addLog("No live photo available to play")
                    }
                }) {
                    Text(isPlaying ? "Stop" : "Play")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(isPlaying ? Color.red : Color.blue)
                        .cornerRadius(8)
                }
                
                // Reload button
                Button(action: {
                    addLog("Reload live photo requested")
                    // Use a more reasonable target size
                    let targetSize = CGSize(
                        width: min(asset.pixelWidth, 1080),
                        height: min(asset.pixelHeight, 1080)
                    )
                    livePhotoLoader.loadLivePhoto(for: asset, targetSize: targetSize)
                }) {
                    Text("Reload")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
            }
            
            // Status indicators
            HStack(spacing: 12) {
                if livePhotoLoader.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading...")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                } else if livePhotoLoader.livePhoto != nil {
                    Label("Live Photo Ready", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Label("Not Loaded", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            // Error display
            if let error = livePhotoLoader.error {
                Text("Error: \(error.localizedDescription)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
            }
            
            // Instruction for long press
            if asset.isLivePhoto {
                Text("Long press on the image above to test live photo activation")
                    .font(.caption)
                    .italic()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
    
    // Helper to convert PHAsset.MediaType to string
    private func mediaTypeString(_ type: PHAssetMediaType) -> String {
        switch type {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
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
                Text("Debug Live Photo")
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