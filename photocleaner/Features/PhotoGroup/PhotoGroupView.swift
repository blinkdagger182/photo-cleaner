import SwiftUI
import Photos
import UIKit

struct PhotoGroupView: View {
    @StateObject private var viewModel: PhotoGroupViewModel
    @EnvironmentObject var toast: ToastService
    @EnvironmentObject var photoManager: PhotoManager
    
    init(photoManager: PhotoManager) {
        _viewModel = StateObject(wrappedValue: PhotoGroupViewModel(photoManager: photoManager))
    }

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        // 🟨 Left: Banner text + buttons
                        if viewModel.authorizationStatus == .limited {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("You're viewing only selected photos.")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                Button("Add More Photos") {
                                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let root = scene.windows.first?.rootViewController {
                                        viewModel.openPhotoLibraryPicker(from: root)
                                    }
                                }
                                .buttonStyle(.bordered)

                                Button("Go to Settings to Allow Full Access") {
                                    viewModel.openSettings()
                                }
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(12)
                        }

                        Spacer()

                        // 🟧 Right: cln. logo, vertically centered
                        VStack {
                            Spacer(minLength: 0)
                            Image("CLN")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 50)
                                .opacity(viewModel.fadeIn ? 1 : 0)
                                .onAppear {
                                    viewModel.triggerFadeInAnimation()
                                }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 100) // Match left VStack's approximate height
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // 🔄 Top Row: Picker and cln. logo
                    HStack(alignment: .bottom) {
                        Picker("View Mode", selection: $viewModel.viewByYear) {
                            Text("By Year").tag(true)
                            Text("My Albums").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)

                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    // 📅 Main content
                    VStack(alignment: .leading, spacing: 20) {
                        if viewModel.viewByYear {
                            ForEach(viewModel.yearGroups) { yearGroup in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("\(yearGroup.year)")
                                        .font(.title)
                                        .bold()
                                        .padding(.horizontal)

                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(yearGroup.months, id: \.id) { group in
                                            Button {
                                                viewModel.updateSelectedGroup(group)
                                            } label: {
                                                AlbumCell(group: group)
                                            }
                                            .buttonStyle(ScaleButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                sectionHeader(title: "My Albums")
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(viewModel.photoGroups.filter { $0.title == "Saved"}, id: \.id) { group in
                                        Button {
                                            viewModel.updateSelectedGroup(group)
                                        } label: {
                                            AlbumCell(group: group)
                                        }
                                        .buttonStyle(ScaleButtonStyle())
                                    }
                                }
                                .padding(.horizontal)

                                Spacer(minLength: 40)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $viewModel.selectedGroup) { group in
            SwipeCardView(group: group, forceRefresh: $viewModel.shouldForceRefresh)
                .onAppear {
                    print("\u{1F4E4} Showing SwipeCardView for:", group.title, "Asset count:", group.count)
                }
                .environmentObject(photoManager)
                .environmentObject(toast)
        }
    }

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.title2)
                .bold()
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct AlbumCell: View {
    let group: PhotoGroup
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.1)
                    ProgressView()
                }
            }
            .frame(width: UIScreen.main.bounds.width / 2 - 30, height: 120)
            .clipped()
            .cornerRadius(8)

            Text(group.title)
                .font(.subheadline)
                .lineLimit(1)

            Text("\(group.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: UIScreen.main.bounds.width / 2 - 30, alignment: .leading)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard group.count > 0 else { return }

        let key = "LastViewedIndex_\(group.id.uuidString)"
        let savedIndex = UserDefaults.standard.integer(forKey: key)
        let safeIndex = min(savedIndex, group.count - 1)
        guard let asset = group.asset(at: safeIndex) else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let size = CGSize(width: 600, height: 600)

        thumbnail = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
