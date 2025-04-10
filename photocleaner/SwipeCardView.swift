import SwiftUI
import Photos
import UIKit

struct SwipeCardView: View {
    let group: PhotoGroup
    @Binding var forceRefresh: Bool

    @EnvironmentObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var toast: ToastService

    @State private var currentIndex: Int = 0
    @State private var offset = CGSize.zero
    @State private var preloadedImages: [UIImage?] = []
    @State private var loadedCount = 0
    @State private var isLoading = false
    @State private var viewHasAppeared = false
    @State private var hasStartedLoading = false
    
    private let maxBufferSize = 5  // Keep only 5 images in memory
    private let preloadThreshold = 3  // Start preloading when 3 images away from end
    @State private var showDeletePreview = false
    @State private var deletePreviewEntries: [DeletePreviewEntry] = []
    @State private var swipeLabel: String? = nil
    @State private var swipeLabelColor: Color = .green
    @State private var hasAppeared = false
    private let lastViewedIndexKeyPrefix = "LastViewedIndex_"

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        if group.assets.isEmpty {
                            Text("No photos available")
                                .foregroundColor(.gray)
                        } else if isLoading || preloadedImages.isEmpty {
                            VStack(spacing: 16) {
                                skeletonStack(
                                    width: geometry.size.width * 0.85,
                                    height: geometry.size.height * 0.4
                                )

                                VStack(spacing: 8) {
                                    Text("We are fetching images...")
                                        .font(.headline)
                                        .foregroundColor(.gray)

                                    Text("🧘 Patience, young padawan...")
                                        .font(.subheadline)
                                        .italic()
                                        .foregroundColor(.secondary)
                                }
                                .multilineTextAlignment(.center)
                            }
                            .padding(.top, 60)
                        } else {
                            ForEach((0..<min(2, group.assets.count - currentIndex)).reversed(), id: \.self) { index in
                                let actualIndex = currentIndex + index
                                if actualIndex < preloadedImages.count, let image = preloadedImages[actualIndex] {
                                    ZStack {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: geometry.size.width * 0.85)
                                            .padding()
                                            .background(Color.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                                            .shadow(radius: 8)

                                        // Overlay label
                                        if index == 0, let swipeLabel = swipeLabel {
                                            Text(swipeLabel.uppercased())
                                                .font(.system(size: 36, weight: .bold))
                                                .foregroundColor(swipeLabelColor)
                                                .padding(.horizontal, 20)
                                                .padding(.vertical, 10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(Color.white.opacity(0.8))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 12)
                                                                .stroke(swipeLabelColor, lineWidth: 3)
                                                        )
                                                )
                                                .rotationEffect(.degrees(-15))
                                                .opacity(1)
                                                .offset(x: swipeLabel == "Keep" ? -40 : 40, y: -geometry.size.height / 4)
                                                .transition(.opacity.combined(with: .move(edge: .top)))
                                                .animation(.easeInOut(duration: 0.2), value: swipeLabel)
                                        }
                                    }
                                    .offset(
                                        x: index == 0 ? offset.width : CGFloat(index * 6),
                                        y: index == 0 ? offset.width / 10 : CGFloat(index * 6)
                                    )
                                    .rotationEffect(index == 0 ? .degrees(Double(offset.width / 15)) : .zero, anchor: .bottomTrailing)
                                    .animation(hasAppeared && index == 0 ? .interactiveSpring(response: 0.3, dampingFraction: 0.7) : .none, value: offset)
                                    .zIndex(Double(-index))
                                    .gesture(
                                        index == 0 ? DragGesture()
                                            .onChanged { value in
                                                offset = value.translation
                                                if offset.width > 50 {
                                                    swipeLabel = "Keep"
                                                    swipeLabelColor = .green
                                                } else if offset.width < -50 {
                                                    swipeLabel = "Delete"
                                                    swipeLabelColor = .red
                                                } else {
                                                    swipeLabel = nil
                                                }
                                            }
                                            .onEnded { value in
                                                handleSwipeGesture(value)
                                                swipeLabel = nil
                                            }
                                        : nil
                                    )
                                } else {
                                    spinnerCard(width: geometry.size.width * 0.85, index: index)
                                }
                            }
                        }
                    }

                    Spacer()

                    Text("\(currentIndex + 1)/\(group.assets.count)")
                        .font(.caption)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)

                    HStack(spacing: 40) {
                        CircleButton(icon: "trash", tint: .red) {
                            handleLeftSwipe()
                        }
                        CircleButton(icon: "bookmark", tint: .yellow) {
                            handleBookmark()
                        }
                        CircleButton(icon: "checkmark", tint: .green) {
                            handleRightSwipe()
                        }
                    }
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle(group.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Next") {
                        prepareDeletePreview()
                    }
                    .disabled(group.assets.isEmpty)
                }
            }
        }
        .onAppear {
            viewHasAppeared = true
            hasAppeared = true
            tryStartPreloading()
            
            // Register for memory warnings
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main) { [self] _ in
                    clearMemory()
                }
        }
        .id(forceRefresh)
        .onDisappear {
            saveProgress()
            clearMemory()
            // Remove observer
            NotificationCenter.default.removeObserver(
                self,
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
        }
        .overlay(toast.overlayView, alignment: .bottom)
        .fullScreenCover(isPresented: $showDeletePreview) {
            DeletePreviewView(
                entries: $deletePreviewEntries,
                forceRefresh: $forceRefresh
            )
            .environmentObject(photoManager)
            .environmentObject(toast)
        }
    }

    // MARK: - Helpers

    private func tryStartPreloading() {
        guard viewHasAppeared,
              group.assets.count > 0,
              !hasStartedLoading else {
            return
        }

        hasStartedLoading = true
        isLoading = true

        Task {
            resetViewState()
            await preloadImages(from: 0)
            isLoading = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                forceRefresh.toggle()
            }
        }
    }

    private func resetViewState() {
        currentIndex = UserDefaults.standard.integer(forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
        if hasAppeared {
            withAnimation(.none) {
                offset = .zero
            }
        } else {
            offset = .zero
        }
        preloadedImages = []
        loadedCount = 0
    }

    private func saveProgress() {
        photoManager.updateLastViewedIndex(for: group.id, index: currentIndex)
        UserDefaults.standard.set(currentIndex, forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
    }

    private func spinnerCard(width: CGFloat, index: Int) -> some View {
        RoundedRectangle(cornerRadius: 30)
            .fill(Color(white: 0.95))
            .frame(width: width)
            .shadow(radius: 8)
            .overlay(ProgressView())
            .padding()
            .offset(x: index == 0 ? offset.width : CGFloat(index * 6),
                    y: CGFloat(index * 6))
            .rotationEffect(index == 0 ? .degrees(Double(offset.width / 20)) : .zero)
            .zIndex(Double(-index))
    }

    private func handleSwipeGesture(_ value: DragGesture.Value) {
        let threshold: CGFloat = 100
        if value.translation.width < -threshold {
            handleLeftSwipe()
        } else if value.translation.width > threshold {
            handleRightSwipe()
        }
        withAnimation(.spring()) {
            if hasAppeared {
                withAnimation(.none) {
                    offset = .zero
                }
            } else {
                offset = .zero
            }
        }
    }

    private func handleLeftSwipe() {
        let asset = group.assets[currentIndex]
//        photoManager.removeAsset(asset, fromGroupWithDate: group.monthDate)
//        photoManager.addAsset(asset, toAlbumNamed: "Deleted")
        photoManager.markForDeletion(asset)

        toast.show("Marked for deletion. Press Next to permanently delete from storage.", action: "Undo") {
            photoManager.restoreToPhotoGroups(asset, inMonth: group.monthDate)
            refreshCard(at: currentIndex, with: asset)
            photoManager.unmarkForDeletion(asset)
        }

        Task { await moveToNext() }
    }

    private func handleBookmark() {
        let asset = group.assets[currentIndex]
        photoManager.bookmarkAsset(asset)
        photoManager.markForFavourite(asset)

        toast.show("Photo saved", action: "Undo") {
            photoManager.removeAsset(asset, fromAlbumNamed: "Saved")
            refreshCard(at: currentIndex, with: asset)
            photoManager.unmarkForDeletion(asset)
        }

        Task { await moveToNext() }
    }

    private func handleRightSwipe() {
        Task { await moveToNext() }
    }

    private func refreshCard(at index: Int, with asset: PHAsset) {
        if index < preloadedImages.count {
            preloadedImages[index] = nil
        } else {
            preloadedImages.insert(nil, at: index)
        }

        loadedCount = preloadedImages.count

        Task {
            await preloadSingleImage(at: index)
        }

        if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    private func moveToNext() async {
        let nextIndex = currentIndex + 1
        let threshold = 5
        let shouldPreload = loadedCount < group.assets.count &&
            preloadedImages.count - nextIndex <= threshold &&
            !isLoading

        if shouldPreload {
            isLoading = true
            await preloadImages(from: loadedCount)
            isLoading = false
        }

        if nextIndex < group.assets.count {
            currentIndex = nextIndex
        }
    }

    private func preloadImages(from startIndex: Int, count: Int = 10) async {
        guard startIndex < group.assets.count else { return }

        let endIndex = min(startIndex + count, group.assets.count)
        var newImages: [UIImage?] = []

        for i in startIndex..<endIndex {
            let asset = group.assets[i]
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            let image = await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: PHImageManagerMaximumSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, _ in
                    continuation.resume(returning: image)
                }
            }

            newImages.append(image)
        }

        preloadedImages += newImages
        loadedCount = preloadedImages.count
    }

    private func preloadSingleImage(at index: Int) async {
        await loadImageForAsset(group.assets[index], at: index)
    }
    
    private func loadImageForAsset(_ asset: PHAsset, at index: Int) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        // Add resource options to prefetch metadata and avoid warnings
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false        
        // Calculate appropriate image size based on screen
        let scale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(
            width: min(screenSize.width * scale, 1200),  // Cap at 1200px width
            height: min(screenSize.height * scale, 1200) // Cap at 1200px height
        )
        
        // First load thumbnail
        let thumbnailSize = CGSize(width: 300, height: 300)
        let thumbnail = await loadImage(for: asset, targetSize: thumbnailSize, options: options)
        
        // Update UI with thumbnail
        await MainActor.run {
            if index < preloadedImages.count {
                preloadedImages[index] = thumbnail
            }
        }
        
        // Then load screen-sized image (not full resolution) if needed
        if index >= currentIndex && index < currentIndex + 2 {
            let screenImage = await loadImage(for: asset, targetSize: targetSize, options: options)
            await MainActor.run {
                if index < preloadedImages.count {
                    preloadedImages[index] = screenImage
                }
            }
        }
    }
    
    private func loadImage(for asset: PHAsset, targetSize: CGSize, options: PHImageRequestOptions) async -> UIImage? {
        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    private func cleanupOldImages() {
        guard currentIndex > maxBufferSize else { return }
        
        // Remove processed images
        if currentIndex > maxBufferSize {
            preloadedImages.removeSubrange(0..<(currentIndex - maxBufferSize))
            
            // Force a memory cleanup
            autoreleasepool {
                // This helps release memory immediately
            }
        }
    }
    
    private func clearMemory() {
        // Keep only the current image, clear everything else
        if !preloadedImages.isEmpty && currentIndex < preloadedImages.count {
            let currentImage = preloadedImages[currentIndex]
            preloadedImages = Array(repeating: nil, count: preloadedImages.count)
            if currentIndex < preloadedImages.count {
                preloadedImages[currentIndex] = currentImage
            }
        }
    }
    
    private func checkAndPreloadMore() {
        let remainingItems = group.assets.count - (currentIndex + loadedCount)
        if remainingItems <= preloadThreshold {
            Task {
                await preloadNextBatch()
            }
        }
    }
    
    private func preloadNextBatch() async {
        let batchSize = 5
        let startIndex = loadedCount
        let endIndex = min(startIndex + batchSize, group.assets.count)
        
        for index in startIndex..<endIndex {
            await loadImageForAsset(group.assets[index], at: index)
        }
        loadedCount = endIndex
    }

    private func prepareDeletePreview() {
        var newEntries: [DeletePreviewEntry] = []

        for (index, asset) in group.assets.enumerated() {
            guard photoManager.isMarkedForDeletion(asset) else { continue }

            if let optionalImage = preloadedImages[safe: index],
               let loadedImage = optionalImage {
                let size = asset.estimatedAssetSize
                let entry = DeletePreviewEntry(asset: asset, image: loadedImage, fileSize: size)
                newEntries.append(entry)
            }
        }

        deletePreviewEntries = newEntries
        showDeletePreview = true
    }
    private func skeletonStack(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach((0..<2).reversed(), id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color(white: 0.9))
                        .frame(width: width, height: height)
                        .offset(x: CGFloat(index * 6), y: CGFloat(index * 6))
                        .shadow(radius: 6)
                        .shimmering()

                    if index == 0 {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                    }
                }
            }
        }
    }

}

struct CircleButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 60, height: 60)
                .background(Circle().strokeBorder(tint, lineWidth: 2))
        }
    }
}

extension View {
    func shimmering(active: Bool = true, duration: Double = 1.25) -> some View {
        modifier(ShimmerModifier(active: active, duration: duration))
    }
}

struct ShimmerModifier: ViewModifier {
    let active: Bool
    let duration: Double

    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        if !active {
            return AnyView(content)
        }

        return AnyView(
            content
                .redacted(reason: .placeholder)
                .overlay(
                    GeometryReader { geometry in
                        let gradient = LinearGradient(
                            gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.6), Color.clear]),
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        Rectangle()
                            .fill(gradient)
                            .rotationEffect(.degrees(30))
                            .offset(x: geometry.size.width * phase)
                            .frame(width: geometry.size.width * 1.5)
                            .blendMode(.plusLighter)
                            .animation(.linear(duration: duration).repeatForever(autoreverses: false), value: phase)
                    }
                    .mask(content)
                )
                .onAppear {
                    phase = 1.5
                }
        )
    }
}
