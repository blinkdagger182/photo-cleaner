import SwiftUI
import Photos

struct SwipeCardView: View {
    let group: PhotoGroup

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var offset = CGSize.zero
    @State private var preloadedImages: [UIImage?] = []
    @State private var loadedCount = 0
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        ForEach((0..<min(3, preloadedImages.count - currentIndex)).reversed(), id: \.self) { index in
                            let actualIndex = currentIndex + index
                            if actualIndex < preloadedImages.count, let image = preloadedImages[actualIndex] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geometry.size.width * 0.85)
                                    .padding()
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                                    .shadow(radius: 8)
                                    .offset(x: index == 0 ? offset.width : CGFloat(index * 6), y: CGFloat(index * 6))
                                    .rotationEffect(index == 0 ? .degrees(Double(offset.width / 20)) : .zero)
                                    .zIndex(Double(-index))
                                    .gesture(
                                        index == 0 ? DragGesture()
                                            .onChanged { offset = $0.translation }
                                            .onEnded { handleSwipeGesture($0) }
                                        : nil
                                    )
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 40) {
                        CircleButton(icon: "trash", tint: .red) {
                            handleLeftSwipe()
                        }
                        CircleButton(icon: "bookmark", tint: .yellow) {
                            // TODO: Implement bookmark logic
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
            .navigationTitle("Review Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await preloadImages(from: 0)
        }
    }

    // MARK: - Swipe Handlers

    private func handleSwipeGesture(_ value: DragGesture.Value) {
        let threshold: CGFloat = 100
        if value.translation.width < -threshold {
            handleLeftSwipe()
        } else if value.translation.width > threshold {
            handleRightSwipe()
        }
        withAnimation(.spring()) {
            offset = .zero
        }
    }

    private func handleLeftSwipe() {
        Task {
            if await deleteCurrentAsset() {
                await moveToNext()
            }
        }
        withAnimation(.spring()) {
            offset = .zero
        }
    }

    private func handleRightSwipe() {
        Task {
            await moveToNext()
        }
        withAnimation(.spring()) {
            offset = .zero
        }
    }

    // MARK: - Next Logic with Safe Preload

    private func moveToNext() async {
        let nextIndex = currentIndex + 1

        // Preload if within last 5 images
        let threshold = 5
        let shouldPreload = loadedCount < group.assets.count &&
                            preloadedImages.count - nextIndex <= threshold &&
                            !isLoading

        if shouldPreload {
            isLoading = true
            await preloadImages(from: loadedCount)
            isLoading = false
        }

        // Move forward if image exists
        if nextIndex < preloadedImages.count {
            currentIndex = nextIndex
        } else {
            dismiss()
        }
    }

    // MARK: - Photo Deletion

    private func deleteCurrentAsset() async -> Bool {
        let asset = group.assets[currentIndex]
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Lazy Preload Images

    private func preloadImages(from startIndex: Int, count: Int = 10) async {
        guard startIndex < group.assets.count else { return }

        let endIndex = min(startIndex + count, group.assets.count)
        var newImages: [UIImage?] = []

        print("Preloading images from \(startIndex) to \(endIndex)")

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
}

// MARK: - Reusable Circular Icon Button

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
                .background(
                    Circle()
                        .strokeBorder(tint, lineWidth: 2)
                )
        }
    }
}
