import SwiftUI
import Photos

struct PhotoGroupView: View {
    let photoGroups: [PhotoGroup]
    let yearGroups: [YearGroup]

    @State private var selectedGroup: PhotoGroup?
    @State private var showingPhotoReview = false
    @State private var viewByYear = true

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("View Mode", selection: $viewByYear) {
                        Text("By Year").tag(true)
                        Text("My Albums").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if viewByYear {
                        ForEach(yearGroups) { yearGroup in
                            VStack(alignment: .leading, spacing: 12) {
                                Text("\(yearGroup.year)")
                                    .font(.title)
                                    .bold()
                                    .padding(.horizontal)

                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(yearGroup.months, id: \..id) { group in
                                        AlbumCell(group: group)
                                            .onTapGesture {
                                                selectedGroup = group
                                                showingPhotoReview = true
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {

                            // MARK: - My Albums
                            Section(header: sectionHeader(title: "My Albums")) {
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(photoGroups.prefix(6), id: \..id) { group in
                                        AlbumCell(group: group)
                                            .onTapGesture {
                                                selectedGroup = group
                                                showingPhotoReview = true
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }

                            // MARK: - Shared Albums
                            Section(header: sectionHeader(title: "Shared Albums")) {
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(photoGroups.suffix(from: 6).prefix(4), id: \..id) { group in
                                        AlbumCell(group: group)
                                            .onTapGesture {
                                                selectedGroup = group
                                                showingPhotoReview = true
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }

                            Spacer(minLength: 40)
                        }
                    }
                }
            }
            .navigationTitle("Albums")
            .sheet(isPresented: $showingPhotoReview) {
                if let group = selectedGroup {
                    SwipeCardView(group: group)
                }
            }
        }
    }

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.title2)
                .bold()
            Spacer()
            Button("See All") {
                // TODO: Implement see all logic
            }
            .font(.subheadline)
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
        guard let asset = group.thumbnailAsset else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true

        let size = CGSize(width: 200, height: 200)

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
