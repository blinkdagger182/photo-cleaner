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
                VStack {
                    Spacer()

                    if let image = currentImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: geometry.size.width * 0.9)
                            .cornerRadius(20)
                            .shadow(radius: 5)
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

                    Spacer()

                    HStack {
                        Button(action: handleLeftSwipe) {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.red)

                        Button(action: handleRightSwipe) {
                            Label("Keep", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.green)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
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
