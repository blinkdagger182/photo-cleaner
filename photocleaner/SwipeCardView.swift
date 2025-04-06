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
    @State private var showDeletePreview = false
    @State private var deletePreviewEntries: [DeletePreviewEntry] = []

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
                            ProgressView("Loading...")
                        } else {
                            ForEach((0..<min(3, group.assets.count - currentIndex)).reversed(), id: \.self) { index in
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
            tryStartPreloading()
        }
        .id(forceRefresh)
        .onDisappear {
            saveProgress()
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
        offset = .zero
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
            offset = .zero
        }
    }

    private func handleLeftSwipe() {
        let asset = group.assets[currentIndex]
        photoManager.removeAsset(asset, fromGroupWithDate: group.monthDate)
        photoManager.addAsset(asset, toAlbumNamed: "Deleted")
        photoManager.markForDeletion(asset)
        Task {
            await photoManager.refreshSystemAlbum(named: "Deleted")
        }

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
