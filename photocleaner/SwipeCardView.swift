import Photos
import SwiftUI
import UIKit

struct SwipeCardView: View {
    let group: PhotoGroup
    @Binding var forceRefresh: Bool

    @EnvironmentObject var photoManager: PhotoManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var toast: ToastService
    
    // Use StateObject for the ViewModel
    @StateObject private var viewModel: SwipeCardViewModel
    
    // Initialize the view with the group and photoManager
    init(group: PhotoGroup, forceRefresh: Binding<Bool>) {
        self.group = group
        self._forceRefresh = forceRefresh
        
        // Create viewModel with default PhotoManager (will be replaced by environment)
        self._viewModel = StateObject(wrappedValue: SwipeCardViewModel(
            group: group,
            photoManager: PhotoManager(),
            forceRefresh: forceRefresh
        ))
    }
    
    // Access to environment objects for the view model
    private var environmentViewModel: SwipeCardViewModel {
        // This ensures we're always using the environment's photoManager
        let vm = viewModel
        vm.photoManager = photoManager
        return vm
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        if group.assets.isEmpty {
                            Text("No photos available")
                                .foregroundColor(.gray)
                        } else if viewModel.isLoading && viewModel.preloadedImages.isEmpty {
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
                                (0..<min(2, max(group.assets.count - viewModel.currentIndex, 0))).reversed(),
                                id: \.self
                            ) { index in
                                let actualIndex = viewModel.currentIndex + index

                                ZStack {
                                    if actualIndex < viewModel.preloadedImages.count,
                                        let image = viewModel.preloadedImages[actualIndex]
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
                                        if index == 0, let prevImage = viewModel.previousImage {
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
                                    if index == 0, let swipeLabel = viewModel.swipeLabel {
                                        Text(swipeLabel.uppercased())
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(viewModel.swipeLabelColor)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.white.opacity(0.8))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(viewModel.swipeLabelColor, lineWidth: 3)
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
                                    x: index == 0 ? viewModel.offset.width : CGFloat(index * 6),
                                    y: index == 0 ? viewModel.offset.width / 10 : CGFloat(index * 6)
                                )
                                .rotationEffect(
                                    index == 0 ? .degrees(Double(viewModel.offset.width / 15)) : .zero,
                                    anchor: .bottomTrailing
                                )
                                .animation(
                                    index == 0
                                        ? .interactiveSpring(response: 0.3, dampingFraction: 0.7)
                                        : .none, value: viewModel.offset
                                )
                                .zIndex(Double(-index))
                                .gesture(
                                    index == 0
                                        ? DragGesture()
                                            .onChanged { value in
                                                viewModel.handleDrag(value: value)
                                            }
                                            .onEnded { value in
                                                viewModel.handleSwipeGesture(value)
                                            }
                                        : nil
                                )
                            }

                            // Show a loading indicator when actively loading more images
                            if viewModel.isLoading {
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

                    Text("\(viewModel.currentIndex + 1)/\(group.assets.count)")
                        .font(.caption)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)

                    HStack(spacing: 40) {
                        CircleButton(icon: "trash", tint: .red) {
                            viewModel.handleLeftSwipe()
                            toast.show(
                                "Marked for deletion. Press Next to permanently delete from storage.", action: "Undo"
                            ) {
                                if viewModel.currentIndex < group.assets.count {
                                    viewModel.restorePhoto(asset: group.assets[viewModel.currentIndex - 1])
                                }
                            }
                        }
                        CircleButton(icon: "bookmark", tint: .yellow) {
                            viewModel.handleBookmark()
                            toast.show("Photo saved", action: "Undo") {
                                if viewModel.currentIndex < group.assets.count {
                                    viewModel.removeFromSaved(asset: group.assets[viewModel.currentIndex - 1])
                                }
                            }
                        }
                        CircleButton(icon: "checkmark", tint: .green) {
                            viewModel.handleRightSwipe()
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
                        viewModel.prepareDeletePreview()
                    }
                    .disabled(group.assets.isEmpty)
                }
            }
        }
        .onAppear {
            // Use the photoManager from the environment
            viewModel.photoManager = photoManager
            viewModel.onAppear()
        }
        .id(forceRefresh)
        .onDisappear {
            viewModel.onDisappear()
        }
        .overlay(toast.overlayView, alignment: .bottom)
        .fullScreenCover(isPresented: $viewModel.showDeletePreview) {
            DeletePreviewView(
                entries: $viewModel.deletePreviewEntries,
                forceRefresh: $forceRefresh
            )
            .environmentObject(photoManager)
            .environmentObject(toast)
        }
    }
    
    // MARK: - Private helpers
    
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
