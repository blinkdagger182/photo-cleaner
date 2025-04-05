import SwiftUI
import Photos
import UIKit

struct SwipeCardView: View {
    let group: PhotoGroup

    @EnvironmentObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var toast: ToastService

    @State private var currentIndex: Int = 0
    @State private var offset = CGSize.zero
    @State private var preloadedImages: [UIImage?] = []
    @State private var loadedCount = 0
    @State private var isLoading = false

    private let lastViewedIndexKeyPrefix = "LastViewedIndex_"

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        if group.assets.isEmpty {
                            VStack {
                                Text("No photos available")
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                        } else {
                            ForEach((0..<min(3, group.assets.count - currentIndex)).reversed(), id: \.self) { index in
                                let actualIndex = currentIndex + index
                                if actualIndex < preloadedImages.count {
                                    if let image = preloadedImages[actualIndex] {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: geometry.size.width * 0.85)
                                            .padding()
                                            .background(Color.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                                            .shadow(radius: 8)
                                            .offset(x: index == 0 ? offset.width : CGFloat(index * 6),
                                                    y: CGFloat(index * 6))
                                            .rotationEffect(index == 0 ? .degrees(Double(offset.width / 20)) : .zero)
                                            .zIndex(Double(-index))
                                            .gesture(
                                                index == 0 ? DragGesture()
                                                    .onChanged { offset = $0.translation }
                                                    .onEnded { handleSwipeGesture($0) }
                                                : nil
                                            )
                                    } else {
                                        spinnerCard(width: geometry.size.width * 0.85, index: index)
                                    }
                                } else {
                                    spinnerCard(width: geometry.size.width * 0.85, index: index)
                                }
                            }
                        }
                    }

                    Spacer()

                    if isLoading && currentIndex >= preloadedImages.count {
                        ProgressView("Loading...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding(.bottom, 20)
                    } else {
                        Text("\(currentIndex + 1)/\(group.assets.count)")
                            .font(.caption)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

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
            currentIndex = UserDefaults.standard.integer(forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
            await preloadImages(from: 0)
        }
        .onDisappear {
            photoManager.updateLastViewedIndex(for: group.id, index: currentIndex)
            UserDefaults.standard.set(currentIndex, forKey: lastViewedIndexKeyPrefix + group.id.uuidString)
        }
        .overlay(toast.overlayView, alignment: .bottom)
    }

    private func spinnerCard(width: CGFloat, index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(white: 0.95))
                .frame(width: width)
                .shadow(radius: 8)

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
        }
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
        withAnimation(.spring()) { offset = .zero }
    }

    private func handleLeftSwipe() {
        let asset = group.assets[currentIndex]

        photoManager.removeAsset(asset, fromGroupWithDate: group.monthDate)
        photoManager.addAsset(asset, toAlbumNamed: "Deleted")

        Task {
            await photoManager.refreshSystemAlbum(named: "Deleted")
        }

        toast.show("Photo deleted", action: "Undo") {
            photoManager.restoreToPhotoGroups(asset, inMonth: group.monthDate)
            refreshCard(at: currentIndex, with: asset)
            photoManager.updateLastViewedIndex(for: group.id, index: currentIndex)
        }

        photoManager.updateLastViewedIndex(for: group.id, index: currentIndex)

        Task { await moveToNext() }
    }

    private func handleBookmark() {
        let asset = group.assets[currentIndex]
        photoManager.bookmarkAsset(asset)

        toast.show("Photo saved", action: "Undo") {
            photoManager.removeAsset(asset, fromAlbumNamed: "Saved")
            refreshCard(at: currentIndex, with: asset)
            photoManager.updateLastViewedIndex(for: group.id, index: currentIndex)
        }

        photoManager.updateLastViewedIndex(for: group.id, index: currentIndex)

        Task { await moveToNext() }
    }

    private func handleRightSwipe() {
        photoManager.updateLastViewedIndex(for: group.id, index: currentIndex)
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
