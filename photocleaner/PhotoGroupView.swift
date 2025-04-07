import SwiftUI
import Photos
import UIKit

struct PhotoGroupView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService

    @State private var selectedGroup: PhotoGroup?
    @State private var viewByYear = true
    @State private var shouldForceRefresh = false
    @State private var fadeIn = false

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    
                    HStack {
                        Spacer() // Pushes content to the right
                        Image("CLN")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 50) // You can use width or height depending on layout
                            .opacity(fadeIn ? 1 : 0)
                            .onAppear {
                                withAnimation(.easeIn(duration: 0.5)) {
                                    fadeIn = true
                                }
                            }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    // 🔄 Top Row: Picker and cln. logo
                    HStack(alignment: .bottom) {
                        Picker("View Mode", selection: $viewByYear) {
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
                        if viewByYear {
                            ForEach(photoManager.yearGroups) { yearGroup in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("\(yearGroup.year)")
                                        .font(.title)
                                        .bold()
                                        .padding(.horizontal)

                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(yearGroup.months, id: \.id) { group in
                                            AlbumCell(group: group)
                                                .onTapGesture {
                                                    selectedGroup = group
                                                }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                sectionHeader(title: "My Albums")
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(photoManager.photoGroups.filter { $0.title == "Saved" || $0.title == "Deleted" }, id: \.id) { group in
                                        AlbumCell(group: group)
                                            .onTapGesture {
                                                selectedGroup = group
                                            }
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
        .sheet(item: $selectedGroup) { group in
            SwipeCardView(group: group, forceRefresh: $shouldForceRefresh)
                .onAppear {
                    print("\u{1F4E4} Showing SwipeCardView for:", group.title, "Asset count:", group.assets.count)
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

            Text("\(group.assets.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: UIScreen.main.bounds.width / 2 - 30, alignment: .leading)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard !group.assets.isEmpty else { return }

        let key = "LastViewedIndex_\(group.id.uuidString)"
        let savedIndex = UserDefaults.standard.integer(forKey: key)
        let safeIndex = min(savedIndex, group.assets.count - 1)
        let asset = group.assets[safeIndex]

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
