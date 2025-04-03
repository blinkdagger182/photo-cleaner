import SwiftUI
import Photos

struct SwipeCardView: View {
    let group: PhotoGroup

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var offset = CGSize.zero
    @State private var currentImage: UIImage?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        if let image = currentImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width * 0.85)
                                .padding()
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                                .shadow(radius: 8)
                                .offset(x: offset.width)
                                .rotationEffect(.degrees(Double(offset.width / 20)))
                                .gesture(
                                    DragGesture()
                                        .onChanged { offset = $0.translation }
                                        .onEnded { handleSwipeGesture($0) }
                                )
                        } else {
                            ProgressView()
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
            await loadCurrentImage()
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
        if currentIndex < group.assets.count - 1 {
            currentIndex += 1
            Task {
                await loadCurrentImage()
            }
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

    // MARK: - Load Image

    private func loadCurrentImage() async {
        let asset = group.assets[currentIndex]
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        currentImage = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
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
