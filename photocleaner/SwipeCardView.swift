import SwiftUI
import Photos

struct SwipeCardView: View {
    let group: PhotoGroup

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var offset = CGSize.zero
    @State private var preloadedImages: [UIImage?] = Array(repeating: nil, count: 10)

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        ForEach((0..<min(3, preloadedImages.count - currentIndex)).reversed(), id: \.self) { index in
                            let actualIndex = currentIndex + index
                            if let image = preloadedImages[actualIndex] {
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
            await preloadImages()
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
                moveToNext()
            }
        }
        withAnimation(.spring()) {
            offset = .zero
        }
    }

    private func handleRightSwipe() {
        moveToNext()
        withAnimation(.spring()) {
            offset = .zero
        }
    }

    private func moveToNext() {
        if currentIndex < preloadedImages.count - 1 {
            currentIndex += 1
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

    // MARK: - Preload Images

    private func preloadImages() async {
        let maxImages = min(10, group.assets.count)
        var loadedImages: [UIImage?] = []

        for i in 0..<maxImages {
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

            loadedImages.append(image)
        }

        preloadedImages = loadedImages
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
