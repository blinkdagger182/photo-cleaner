import Photos
import SwiftUI
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
    @State private var previousImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        if group.assets.isEmpty {
                            Text("No photos available")
                                .foregroundColor(.gray)
                        } else if isLoading && preloadedImages.isEmpty {
                            // Show loading indicator only on initial load
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
                            // Show images with proper fallbacks
                            ForEach(
                                (0..<min(2, max(group.assets.count - currentIndex, 0))).reversed(),
                                id: \.self
                            ) { index in
                                let actualIndex = currentIndex + index

                                ZStack {
                                    if actualIndex < preloadedImages.count,
                                        let image = preloadedImages[actualIndex]
                                    {
                                        // We have the image, display it
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: geometry.size.width * 0.85)
                                            .padding()
                                            .background(Color.white)
                                            .clipShape(
                                                RoundedRectangle(
                                                    cornerRadius: 30, style: .continuous)
                                            )
                                            .shadow(radius: 8)
                                    } else if actualIndex < group.assets.count {
                                        // If no image is available yet but we have a previous image, show it with overlay
                                        if index == 0, let prevImage = previousImage {
                                            Image(uiImage: prevImage)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: geometry.size.width * 0.85)
                                                .padding()
                                                .background(Color.white)
                                                .clipShape(
                                                    RoundedRectangle(
                                                        cornerRadius: 30, style: .continuous)
                                                )
                                                .shadow(radius: 8)
                                                .overlay(
                                                    ZStack {
                                                        Color.black.opacity(0.2)
                                                        ProgressView()
                                                            .scaleEffect(1.5)
                                                            .tint(.white)
                                                    }
                                                )
                                        } else {
                                            // No previous image available, show skeleton with less white
                                            RoundedRectangle(cornerRadius: 30)
                                                .fill(Color(white: 0.95))
                                                .frame(width: geometry.size.width * 0.85)
                                                .shadow(radius: 8)
                                                .overlay(
                                                    VStack {
                                                        ProgressView()
                                                            .padding(.bottom, 8)
                                                        Text("Loading image...")
                                                            .font(.caption)
                                                            .foregroundColor(.gray)
                                                    }
                                                )
                                                .padding()
                                        }
                                    }

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
                                            .offset(
                                                x: swipeLabel == "Keep" ? -40 : 40,
                                                y: -geometry.size.height / 4
                                            )
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                            .animation(.easeInOut(duration: 0.2), value: swipeLabel)
                                    }
                                }
                                .offset(
                                    x: index == 0 ? offset.width : CGFloat(index * 6),
                                    y: index == 0 ? offset.width / 10 : CGFloat(index * 6)
                                )
                                .rotationEffect(
                                    index == 0 ? .degrees(Double(offset.width / 15)) : .zero,
                                    anchor: .bottomTrailing
                                )
                                .animation(
                                    hasAppeared && index == 0
                                        ? .interactiveSpring(response: 0.3, dampingFraction: 0.7)
                                        : .none, value: offset
                                )
                                .zIndex(Double(-index))
                                .gesture(
                                    index == 0
                                        ? DragGesture()
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
                            }

                            // Show a loading indicator when actively loading more images
                            if isLoading {
                                HStack {
                                    Spacer()
                                    VStack {
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(1.5)
                                        Text("Loading more...")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .padding(.top, 8)
                                        Spacer()
                                    }
                                    Spacer()
                                }
                                .frame(width: 150, height: 100)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(12)
                                .shadow(radius: 8)
                                .padding(.bottom, 50)
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
                queue: .main
            ) { [self] _ in
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
            !hasStartedLoading
        else {
            return
        }

        hasStartedLoading = true
        isLoading = true

        Task {
            resetViewState()

            // First, quickly load thumbnails for the first few images
            await preloadThumbnails(
                from: currentIndex, count: min(5, group.assets.count - currentIndex))

            // Then load higher quality for current card
            if currentIndex < group.assets.count {
                await loadHighQualityImage(at: currentIndex)

                // Preload next card high quality if available
                if currentIndex + 1 < group.assets.count {
                    await loadHighQualityImage(at: currentIndex + 1)
                }
            }

            isLoading = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                forceRefresh.toggle()
            }
        }
    }
    
    private func preloadThumbnails(from startIndex: Int, count: Int) async {
        guard startIndex < group.assets.count else { return }

        let endIndex = min(startIndex + count, group.assets.count)

        // Make sure preloadedImages array has enough slots
        while preloadedImages.count < endIndex {
            preloadedImages.append(nil)
        }

        // Load thumbnails quickly
        for i in startIndex..<endIndex {
            if i >= preloadedImages.count { continue }

            let asset = group.assets[i]
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat  // Use fast format for thumbnails
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            // Use a reasonable thumbnail size
            let thumbnailSize = CGSize(width: 300, height: 300)

            let image = await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: thumbnailSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, _ in
                    continuation.resume(returning: image)
                }
            }

            // Update UI with thumbnail
            await MainActor.run {
                if i < preloadedImages.count {
                    preloadedImages[i] = image
                }
            }
        }

        loadedCount = max(loadedCount, endIndex)
    }
    
    private func loadHighQualityImage(at index: Int) async {
        guard index < group.assets.count else { return }

        // Make sure preloadedImages array has enough slots
        while preloadedImages.count <= index {
            preloadedImages.append(nil)
        }

        let asset = group.assets[index]
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        // Calculate appropriate image size based on screen
        let scale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(
            width: min(screenSize.width * scale, 1200),  // Cap at 1200px width
            height: min(screenSize.height * scale, 1200)  // Cap at 1200px height
        )

        let image = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,  // Use appropriate size, not max size
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }

        // Update UI with high quality image
        await MainActor.run {
            if index < preloadedImages.count {
                preloadedImages[index] = image
            }
        }
    }

    private func resetViewState() {
        currentIndex = UserDefaults.standard.integer(
            forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
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
        UserDefaults.standard.set(
            currentIndex, forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
    }

    private func spinnerCard(width: CGFloat, index: Int) -> some View {
        RoundedRectangle(cornerRadius: 30)
            .fill(Color(white: 0.95))
            .frame(width: width)
            .shadow(radius: 8)
            .overlay(ProgressView())
            .padding()
            .offset(
                x: index == 0 ? offset.width : CGFloat(index * 6),
                y: CGFloat(index * 6)
            )
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

        toast.show(
            "Marked for deletion. Press Next to permanently delete from storage.", action: "Undo"
        ) {
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
        
        if nextIndex < group.assets.count {
            // Store the current image as previous before moving to next
            if currentIndex < preloadedImages.count, let currentImage = preloadedImages[currentIndex] {
                previousImage = currentImage
            }
            
            // Update the index to maintain UI responsiveness
            await MainActor.run {
                currentIndex = nextIndex
            }
            
            // Clean up old images to free memory (keeping a few behind for backtracking)
            await cleanupOldImages()
            
            // Check if we need to preload more thumbnails
            let thumbnailPreloadThreshold = 3
            if nextIndex + thumbnailPreloadThreshold >= loadedCount && loadedCount < group.assets.count {
                await preloadThumbnails(from: loadedCount, count: 5)
            }
            
            // Load high quality for current and next image
            await loadHighQualityImage(at: nextIndex)
            
            if nextIndex + 1 < group.assets.count {
                await loadHighQualityImage(at: nextIndex + 1)
            }
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
            height: min(screenSize.height * scale, 1200)  // Cap at 1200px height
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

    private func loadImage(for asset: PHAsset, targetSize: CGSize, options: PHImageRequestOptions)
        async -> UIImage?
    {
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

    private func cleanupOldImages() async {
        await MainActor.run {
            // Keep current and next few images, remove everything before that
            if currentIndex > maxBufferSize {
                // Create a new array with nil for old images to free memory
                var newImages = Array(
                    repeating: nil as UIImage?, count: currentIndex - maxBufferSize)

                // Append the images we want to keep
                if currentIndex < preloadedImages.count {
                    newImages.append(contentsOf: preloadedImages[currentIndex...])
                }

                preloadedImages = newImages

                // Force a memory cleanup
                autoreleasepool {}
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
                let loadedImage = optionalImage
            {
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
                            gradient: Gradient(colors: [
                                Color.clear, Color.white.opacity(0.6), Color.clear,
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        Rectangle()
                            .fill(gradient)
                            .rotationEffect(.degrees(30))
                            .offset(x: geometry.size.width * phase)
                            .frame(width: geometry.size.width * 1.5)
                            .blendMode(.plusLighter)
                            .animation(
                                .linear(duration: duration).repeatForever(autoreverses: false),
                                value: phase)
                    }
                    .mask(content)
                )
                .onAppear {
                    phase = 1.5
                }
        )
    }
}
