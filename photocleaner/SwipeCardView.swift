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
//    @GestureState private var dragOffset: CGSize = .zero
    @State private var cardOffset: CGSize = .zero
    @State private var swipeDirection: SwipeDirection? = nil

    @State private var preloadedImages: [UIImage?] = []
    @State private var loadedCount = 0
    @State private var isLoading = false
    @State private var viewHasAppeared = false
    @State private var hasStartedLoading = false
    @State private var showDeletePreview = false
    @State private var deletePreviewEntries: [DeletePreviewEntry] = []
    @State private var swipeLabel: String? = nil
    @State private var swipeLabelColor: Color = .green
    @State private var isTopCardVisible = true
    @State private var animatedIndex: Int? = nil
    @State private var isSwipingCard: Bool = false
    @State private var swipingImage: UIImage? = nil
    
    enum SwipeDirection {
        case left, right
    }

    private let lastViewedIndexKeyPrefix = "LastViewedIndex_"

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()

                    contentBody(for: geometry)

                    Spacer()

                    progressIndicator

                    swipeControls
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

    @ViewBuilder
    private func contentBody(for geometry: GeometryProxy) -> some View {
        if group.assets.isEmpty {
            Text("No photos available")
                .foregroundColor(.gray)
        } else if isLoading || preloadedImages.isEmpty {
            VStack(spacing: 16) {
                skeletonStack(width: geometry.size.width * 0.85, height: geometry.size.height * 0.4)
                Text("We are fetching images...")
                    .font(.headline)
                    .foregroundColor(.gray)
                Text("🧘‍♂️ Patience, young padawan...")
                    .font(.subheadline)
                    .italic()
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 60)
        } else {
            ZStack {
                // Stack of cards AFTER the one being swiped
                CardStackView(
                    geometry: geometry,
                    currentIndex: currentIndex + (isSwipingCard ? 1 : 0),
                    preloadedImages: preloadedImages,
                    cardOffset: .constant(.zero),
                    swipeLabel: .constant(nil),
                    swipeLabelColor: .constant(.clear),
                    swipeDirection: .constant(nil),
                    animateCardOffScreen: {},
                    isSwipingCard: false // irrelevant here
                )

                // Actively swiped top card
                if let img = swipingImage {
                    SwipeCard(
                        image: img,
                        index: 0,
                        geometry: geometry,
                        cardOffset: $cardOffset,
                        swipeLabel: $swipeLabel,
                        swipeLabelColor: $swipeLabelColor,
                        swipeDirection: $swipeDirection,
                        animateCardOffScreen: animateCardOffScreen
                    )
                    .zIndex(100)
                }
            }
        }
    }


    private var progressIndicator: some View {
        Text("\(currentIndex + 1)/\(group.assets.count)")
            .font(.caption)
            .padding(8)
            .background(Color.black.opacity(0.6))
            .foregroundColor(.white)
            .cornerRadius(8)
    }

    private var swipeControls: some View {
        HStack(spacing: 40) {
            CircleButton(icon: "trash", tint: .red) {
                swipeDirection = .left
                animateCardOffScreen()
            }
            CircleButton(icon: "bookmark", tint: .yellow) {
                handleBookmark()
            }
            CircleButton(icon: "checkmark", tint: .green) {
                swipeDirection = .right
                animateCardOffScreen()
            }
        }
        .padding(.bottom, 32)
    }

    private func animateCardOffScreen() {
        // Set the image being swiped
        if let image = preloadedImages[safe: currentIndex] {
            swipingImage = image
        }
        isSwipingCard = true

        withAnimation(.easeOut(duration: 0.3)) {
            switch swipeDirection {
            case .left: cardOffset.width = -1000
            case .right: cardOffset.width = 1000
            default: break
            }
            swipeLabel = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch swipeDirection {
            case .left: handleLeftSwipe()
            case .right: handleRightSwipe()
            default: break
            }

            currentIndex += 1
            cardOffset = .zero
            swipeDirection = nil
            isSwipingCard = false
            swipingImage = nil
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
        cardOffset = .zero
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
//            .offset(x: index == 0 ? (cardOffset.width + dragOffset.width) : CGFloat(index * 6),
//                    y: CGFloat(index * 6))
//            .rotationEffect(index == 0 ? .degrees(Double(cardOffset.width + dragOffset.width) / 20) : .zero)
            .zIndex(Double(-index))
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

        DispatchQueue.main.async {
            preloadedImages.append(contentsOf: newImages)
        }
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
struct SwipeCard: View {
    let image: UIImage
    let index: Int
    let geometry: GeometryProxy
    @GestureState private var dragOffset: CGSize = .zero // ✅ defined internally

    @Binding var cardOffset: CGSize
    @Binding var swipeLabel: String?
    @Binding var swipeLabelColor: Color
    @Binding var swipeDirection: SwipeCardView.SwipeDirection?

    let animateCardOffScreen: () -> Void

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width * 0.85)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(radius: 8)

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
                    .offset(x: swipeLabel == "Keep" ? -40 : 40, y: -geometry.size.height / 4)
                    .opacity(1)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.2), value: swipeLabel)
            }
        }
        .offset(x: index == 0 ? (cardOffset.width + dragOffset.width) : CGFloat(index * 6),
                y: CGFloat(index * 6))
        .rotationEffect(index == 0 ? .degrees(Double(cardOffset.width + dragOffset.width) / 20) : .zero)
        .gesture(
            index == 0 ? DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                    if value.translation.width > 50 {
                        swipeLabel = "Keep"
                        swipeLabelColor = .green
                    } else if value.translation.width < -50 {
                        swipeLabel = "Delete"
                        swipeLabelColor = .red
                    } else {
                        swipeLabel = nil
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 100
                    if value.translation.width > threshold {
                        swipeDirection = .right
                        animateCardOffScreen()
                    } else if value.translation.width < -threshold {
                        swipeDirection = .left
                        animateCardOffScreen()
                    } else {
                        withAnimation(.spring()) {
                            cardOffset = .zero
                            swipeLabel = nil
                        }
                    }
                }
            : nil
        )
    }
}

struct CardStackView: View {
    let geometry: GeometryProxy
    let currentIndex: Int
    let preloadedImages: [UIImage?]
    @Binding var cardOffset: CGSize
    @Binding var swipeLabel: String?
    @Binding var swipeLabelColor: Color
    @Binding var swipeDirection: SwipeCardView.SwipeDirection?
    let animateCardOffScreen: () -> Void
    let isSwipingCard: Bool // safe to ignore now

    var body: some View {
        let cardCount = min(2, max(0, preloadedImages.count - currentIndex))
        let safeRange = Array(0..<cardCount)

        ZStack {
            ForEach(safeRange, id: \.self) { index in
                let actualIndex = currentIndex + index
                if actualIndex < preloadedImages.count, let image = preloadedImages[actualIndex] {
                    SwipeCard(
                        image: image,
                        index: index,
                        geometry: geometry,
                        cardOffset: $cardOffset,
                        swipeLabel: $swipeLabel,
                        swipeLabelColor: $swipeLabelColor,
                        swipeDirection: $swipeDirection,
                        animateCardOffScreen: animateCardOffScreen
                    )
                    .zIndex(Double(-index))
                }
            }
        }
    }
}
