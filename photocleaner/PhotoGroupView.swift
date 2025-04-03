import SwiftUI
import Photos

struct PhotoGroupView: View {
    let photoGroups: [PhotoGroup]
    @State private var selectedGroup: [PhotoGroup] = []
    @State private var showingPhotoReview = false

    struct MonthGroup: Identifiable {
        let id = UUID()
        let title: String
        let groups: [PhotoGroup]
        let totalCount: Int
    }

    var monthGroups: [MonthGroup] {
        let grouped = Dictionary(grouping: photoGroups) { group -> DateComponents in
            let date = group.creationDate ?? .distantPast
            let components = Calendar.current.dateComponents([.year, .month], from: date)
            return components
        }

        return grouped
            .compactMap { (components, groups) -> (date: Date, group: MonthGroup)? in
                guard let year = components.year, let month = components.month else { return nil }
                var dateComponents = DateComponents()
                dateComponents.year = year
                dateComponents.month = month
                let calendar = Calendar.current
                guard let date = calendar.date(from: dateComponents) else { return nil }

                let title = date.formatted(.dateTime.year().month(.wide)).uppercased()
                let totalCount = groups.reduce(0) { $0 + $1.assets.count }

                return (date, MonthGroup(title: title, groups: groups, totalCount: totalCount))
            }
            .sorted(by: { $0.date > $1.date }) // descending by full date
            .map { $0.group }
    }


    var body: some View {
        NavigationStack {
            List(monthGroups) { monthGroup in
                Button {
                    selectedGroup = monthGroup.groups
                    showingPhotoReview = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monthGroup.title.capitalized)
                            .font(.headline)
                            .foregroundColor(.black)
                        Text("\(monthGroup.totalCount) Photos")
                            .font(.subheadline)
                            .foregroundStyle(.black)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Photo Groups")
            .sheet(isPresented: $showingPhotoReview) {
                if !selectedGroup.isEmpty {
                    SwipeCardView(group: mergedGroup(from: selectedGroup))
                }
            }
        }
    }

    // Optional: Merge multiple PhotoGroups into one for SwipeCardView
    func mergedGroup(from groups: [PhotoGroup]) -> PhotoGroup {
        let allAssets = groups.flatMap { $0.assets }
        return PhotoGroup(assets: allAssets)
    }

}


struct PhotoGroupCell: View {
    let group: PhotoGroup
    @State private var thumbnail: UIImage?
    
    var body: some View {
        HStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                ProgressView()
                    .frame(width: 60, height: 60)
            }
            
            VStack(alignment: .leading) {
                Text("\(group.assets.count) Photos")
                    .font(.headline)
                if let date = group.creationDate {
                    Text(date.formatted())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard let asset = group.thumbnailAsset else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        
        let size = CGSize(width: 120, height: 120)
        
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
