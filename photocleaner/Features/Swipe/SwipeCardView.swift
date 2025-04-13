import Photos
import SwiftUI
import UIKit

struct SwipeCardView: View {
    @ObservedObject var viewModel: SwipeCardViewModel
    @EnvironmentObject var mainFlowCoordinator: MainFlowCoordinator
    @EnvironmentObject var toast: ToastService

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                Spacer()

                // Extract complex ZStack into separate view
                CardStackView(
                    geometry: geometry,
                    viewModel: viewModel
                )

                Spacer()

                Text("\(viewModel.currentIndex + 1)/\(viewModel.assets.count)")
                    .font(.caption)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)

                SwipeActionBar(
                    onDelete: {
                        viewModel.handleLeftSwipe()
                        toast.show(message: "Photo marked for deletion", type: .success)
                    },
                    onBookmark: {
                        viewModel.handleBookmark()
                        toast.show(message: "Photo bookmarked", type: .info)
                    },
                    onKeep: {
                        viewModel.handleRightSwipe()
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Next") {
                        viewModel.prepareDeletePreview()
                    }
                    .disabled(viewModel.assets.isEmpty)
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        mainFlowCoordinator.navigateToPhotoGroups()
                    }
                }
            }
            .onAppear {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
            .overlay(toast.overlayView, alignment: .bottom)
        }
    }
}

// Extract complex ZStack into a separate view
struct CardStackView: View {
    let geometry: GeometryProxy
    @ObservedObject var viewModel: SwipeCardViewModel
    
    var body: some View {
        ZStack {
            if viewModel.assets.isEmpty {
                Text("No photos available")
                    .foregroundColor(.gray)
            } else if viewModel.isLoading && viewModel.preloadedImages.isEmpty {
                // Show loading indicator only on initial load
                VStack(spacing: 16) {
                    ShimmerPlaceholder(
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
                // Show photo cards
                CardsStackContent(geometry: geometry, viewModel: viewModel)

                // Show a loading indicator when actively loading more images
                if viewModel.isLoading {
                    LoadingOverlay()
                }
            }
        }
    }
}

// Further break down the cards content
struct CardsStackContent: View {
    let geometry: GeometryProxy
    @ObservedObject var viewModel: SwipeCardViewModel
    
    var body: some View {
        ForEach(
            (0..<min(2, max(viewModel.assets.count - viewModel.currentIndex, 0))).reversed(),
            id: \.self
        ) { index in
            let actualIndex = viewModel.currentIndex + index
            
            if index == 0 {
                // Main card with drag gesture
                PhotoCardView(
                    image: actualIndex < viewModel.preloadedImages.count ? viewModel.preloadedImages[actualIndex] : nil,
                    swipeLabel: viewModel.swipeLabel,
                    swipeLabelColor: viewModel.swipeLabelColor,
                    offset: viewModel.offset,
                    isLoading: viewModel.isLoading,
                    previousImage: viewModel.previousImage,
                    onDragChanged: { value in
                        viewModel.handleDrag(value: value)
                    },
                    onDragEnded: { value in
                        viewModel.handleSwipeGesture(value)
                    }
                )
            } else {
                // Background card (no gesture)
                BackgroundCardView(
                    actualIndex: actualIndex,
                    preloadedImages: viewModel.preloadedImages,
                    geometry: geometry,
                    index: index
                )
            }
        }
    }
}

// Background card view
struct BackgroundCardView: View {
    let actualIndex: Int
    let preloadedImages: [UIImage?]
    let geometry: GeometryProxy
    let index: Int
    
    var body: some View {
        ZStack {
            if actualIndex < preloadedImages.count,
                let image = preloadedImages[actualIndex]
            {
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
            }
        }
        .offset(x: CGFloat(index * 6), y: CGFloat(index * 6))
        .zIndex(Double(-index))
    }
}

// Loading overlay
struct LoadingOverlay: View {
    var body: some View {
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