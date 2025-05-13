import SwiftUI
import Photos

struct AlbumGalleryView: View {
    // MARK: - Properties
    let group: PhotoGroup
    @Binding var selectedAssetIndex: Int
    @Binding var isGalleryVisible: Bool
    @State private var selectedAsset: PHAsset?
    @State private var isFullScreenMode: Bool = false
    @State private var gridColumns = [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 2)]
    
    // Modal dismissal properties
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var photoManager: PhotoManager
    
    // MARK: - UI Properties
    private let spacing: CGFloat = 2
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            if isFullScreenMode, let selectedAsset = selectedAsset {
                // Full screen single photo view with swipe navigation
                SinglePhotoView(
                    asset: selectedAsset,
                    group: group,
                    currentIndex: $selectedAssetIndex,
                    isFullScreenMode: $isFullScreenMode
                )
                .transition(.opacity)
                .zIndex(2)
                .ignoresSafeArea()
            } else {
                // Grid gallery view
                ZStack {
                    // Background
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Add drag indicator at the top center
                        Capsule()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        
                        // Navigation bar
                        HStack {
                            Button(action: {
                                withAnimation(.spring()) {
                                    isGalleryVisible = false
                                    dismiss()
                                }
                            }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Circle())
                            }
                            
                            Spacer()
                            
                            Text(group.title)
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Button(action: {
                                // Select multiple photos functionality would go here
                            }) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, geometry.safeAreaInsets.top + 8)
                        .padding(.bottom, 8)
                        .background(
                            Color(UIColor.systemBackground)
                                .opacity(0.95)
                                .ignoresSafeArea()
                        )
                        
                        // Photo grid
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: spacing) {
                                ForEach(0..<group.count, id: \.self) { index in
                                    if let asset = group.asset(at: index) {
                                        GalleryThumbnail(
                                            asset: asset,
                                            size: calculateThumbnailSize(geometry: geometry),
                                            isSelected: index == selectedAssetIndex
                                        )
                                        .onTapGesture {
                                            selectedAssetIndex = index
                                            selectedAsset = asset
                                            withAnimation(.easeInOut) {
                                                isFullScreenMode = true
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, spacing)
                            .padding(.bottom, geometry.safeAreaInsets.bottom)
                        }
                        .simultaneousGesture(
                            // Add a drag gesture to dismiss the modal with a swipe down
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.height > 0 && !isDragging {
                                        isDragging = true
                                    }
                                    
                                    if isDragging {
                                        dragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if dragOffset > 100 {
                                        // Dismiss the modal if dragged down far enough
                                        withAnimation(.spring()) {
                                            isGalleryVisible = false
                                            dismiss()
                                        }
                                    } else {
                                        // Reset if not dragged far enough
                                        withAnimation(.spring()) {
                                            dragOffset = 0
                                            isDragging = false
                                        }
                                    }
                                }
                        )
                    }
                    .offset(y: dragOffset)
                }
                .background(Color(UIColor.systemBackground))
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .ignoresSafeArea()
        .statusBar(hidden: isFullScreenMode)
        .onDisappear {
            isGalleryVisible = false
        }
    }
    
    // MARK: - Helper Methods
    private func calculateThumbnailSize(geometry: GeometryProxy) -> CGSize {
        let columns = traitBasedColumnCount(width: geometry.size.width)
        let width = (geometry.size.width - (spacing * (CGFloat(columns) + 1))) / CGFloat(columns)
        return CGSize(width: width, height: width)
    }
    
    // Adjust columns based on device width like iOS Photos app
    private func traitBasedColumnCount(width: CGFloat) -> Int {
        if width < 400 {
            return 3 // iPhone portrait
        } else if width < 800 {
            return 4 // iPhone landscape, iPad portrait
        } else {
            return 5 // iPad landscape
        }
    }
}

// MARK: - Gallery Thumbnail Component
struct GalleryThumbnail: View {
    let asset: PHAsset
    let size: CGSize
    let isSelected: Bool
    
    init(asset: PHAsset, size: CGSize, isSelected: Bool = false) {
        self.asset = asset
        self.size = size
        self.isSelected = isSelected
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Asset Image
            AssetThumbnailView(asset: asset, size: size)
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.width)
                .clipped()
                .overlay(
                    isSelected ? 
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.blue, lineWidth: 3) : nil
                )
            
            // Live Photo indicator
            if asset.mediaSubtypes.contains(.photoLive) {
                Image(systemName: "livephoto")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(4)
            }
            
            // Video duration indicator
            if asset.mediaType == .video {
                Text(formatDuration(asset.duration))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(4)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}

// MARK: - Asset Thumbnail View
struct AssetThumbnailView: View {
    let asset: PHAsset
    let size: CGSize
    
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: size.width * 2, height: size.height * 2),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}

// MARK: - Single Photo View for Full Screen Mode
struct SinglePhotoView: View {
    let asset: PHAsset
    let group: PhotoGroup
    @Binding var currentIndex: Int
    @Binding var isFullScreenMode: Bool
    
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isLivePhotoPlaying: Bool = false
    @State private var livePhoto: PHLivePhoto?
    @State private var showControls: Bool = true
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Navigation Bar and controls
            if showControls {
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation(.spring()) {
                                isFullScreenMode = false
                                scale = 1.0
                                offset = .zero
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Index indicator
                        Text("\(currentIndex + 1) of \(group.count)")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(16)
                        
                        Spacer()
                        
                        Button(action: {
                            // Share functionality would go here
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Bottom toolbar
                    HStack(spacing: 24) {
                        Button(action: {
                            // Favorite functionality
                        }) {
                            Image(systemName: "heart")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        
                        Button(action: {
                            // Edit functionality
                        }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        
                        Button(action: {
                            // Delete functionality
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.5)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
                }
                .transition(.opacity)
                .zIndex(2)
            }
            
            // Photo Content
            Group {
                if asset.mediaSubtypes.contains(.photoLive), let livePhoto = livePhoto {
                    LivePhotoView(livePhoto: livePhoto, isPlaying: isLivePhotoPlaying)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            LongPressGesture(minimumDuration: 0.3)
                                .onEnded { _ in
                                    isLivePhotoPlaying.toggle()
                                }
                        )
                } else if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, 1.0), 5.0)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if scale < 1.1 {
                            withAnimation {
                                scale = 1.0
                                offset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1.0 {
                            // Allow dragging when zoomed in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        lastOffset = offset
                        if scale <= 1.0 {
                            withAnimation {
                                offset = .zero
                            }
                        }
                    }
            )
            .gesture(
                // Double tap to zoom
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation {
                            if scale > 1.0 {
                                scale = 1.0
                                offset = .zero
                            } else {
                                scale = 2.5
                            }
                        }
                    }
            )
            .gesture(
                // Single tap to toggle controls
                TapGesture()
                    .onEnded {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
            )
            .contentShape(Rectangle())
            .gesture(
                // Swipe to navigate between photos
                DragGesture()
                    .onEnded { value in
                        if scale <= 1.0 {
                            let horizontalAmount = value.translation.width
                            let verticalAmount = value.translation.height
                            
                            // Only respond to horizontal swipes when not zoomed in
                            if abs(horizontalAmount) > 50 && abs(horizontalAmount) > abs(verticalAmount) {
                                withAnimation(.spring()) {
                                    if horizontalAmount > 0 && currentIndex > 0 {
                                        // Swipe right - previous photo
                                        currentIndex -= 1
                                        loadFullImage(for: group.asset(at: currentIndex))
                                    } else if horizontalAmount < 0 && currentIndex < group.count - 1 {
                                        // Swipe left - next photo
                                        currentIndex += 1
                                        loadFullImage(for: group.asset(at: currentIndex))
                                    }
                                }
                            }
                        }
                    }
            )
            .zIndex(1)
        }
        .onAppear {
            loadFullImage(for: asset)
            if asset.mediaSubtypes.contains(.photoLive) {
                loadLivePhoto()
            }
        }
    }
    
    private func loadFullImage(for asset: PHAsset?) {
        guard let asset = asset else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
    
    private func loadLivePhoto() {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestLivePhoto(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { livePhoto, _ in
            self.livePhoto = livePhoto
        }
    }
}

// MARK: - Preview
#Preview {
    // This preview uses mock data - in real usage, pass actual PhotoGroup
    AlbumGalleryView(
        group: PhotoGroup(
            assets: [],
            title: "Sample Album",
            monthDate: Date()
        ),
        selectedAssetIndex: .constant(0),
        isGalleryVisible: .constant(true)
    )
    .environmentObject(PhotoManager())
} 