import SwiftUI
import Photos
import UIKit

struct SwipeCardView: View {
    let group: PhotoGroup

    @EnvironmentObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var toast: ToastService

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
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await preloadImages(from: 0)
        }
        .overlay(toast.overlayView, alignment: .bottom)
    }

    private func handleSwipeGesture(_ value: DragGesture.Value) {
        let threshold: CGFloat = 100
        if value.translation.width < -threshold {
            handleLeftSwipe()
        } else if value.translation.width > threshold {
            handleRightSwipe()
        }
        withAnimation(.spring()) { offset = .zero }
    }

    private func handleLeftSwipe() {
        let asset = group.assets[currentIndex]

        // Remove from the main group
        photoManager.removeAsset(asset, fromGroupWithDate: group.monthDate)
        photoManager.addAsset(asset, toAlbumNamed: "Deleted")

        Task {
            await photoManager.refreshSystemAlbum(named: "Deleted")
        }

        toast.show("Photo deleted", action: "Undo") {
            photoManager.restoreToPhotoGroups(asset, inMonth: group.monthDate)
            refreshCard(at: currentIndex, with: asset)
        }

        Task { await moveToNext() }
    }

    private func handleBookmark() {
        let asset = group.assets[currentIndex]
        photoManager.bookmarkAsset(asset)

        toast.show("Photo saved", action: "Undo") {
            photoManager.removeAsset(asset, fromAlbumNamed: "Saved")
            refreshCard(at: currentIndex, with: asset)
        }

        Task { await moveToNext() }
    }

    private func handleRightSwipe() {
        Task { await moveToNext() }
    }

    private func refreshCard(at index: Int, with asset: PHAsset) {
        // Just reinsert locally to visual stack, not to original group
        preloadedImages.insert(nil, at: index)
        loadedCount = preloadedImages.count

        Task {
            await preloadSingleImage(at: index)
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

        if nextIndex < preloadedImages.count {
            currentIndex = nextIndex
        } else {
            dismiss()
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
        guard index < group.assets.count else { return }

        let asset = group.assets[index]
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

        if index < preloadedImages.count {
            preloadedImages[index] = image
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
                .background(
                    Circle()
                        .strokeBorder(tint, lineWidth: 2)
                )
        }
    }
}
