import Foundation
import Photos
import SwiftUI

@MainActor
class PhotoManager: ObservableObject {
    @Published var allPhotos: [PHAsset] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allAssets: [PHAsset] = []
    @Published var photoGroups: [PhotoGroup] = []
    @Published var yearGroups: [YearGroup] = []
    @Published var markedForDeletion: Set<String> = []   // asset.localIdentifier
    @Published var markedForBookmark: Set<String> = []

    private let lastViewedIndexKey = "LastViewedIndex"

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status

        if status == .authorized || status == .limited {
            async let years = fetchPhotoGroupsByYearAndMonth()
            async let systemAlbums = fetchSystemAlbums()

            let fetchedYears = await years
            let fetchedSystemAlbums = await systemAlbums
            self.yearGroups = fetchedYears
            self.photoGroups = fetchedYears.flatMap { $0.months } + fetchedSystemAlbums
        }
    }

//    func fetchPhotoGroupsByMonth() async -> [PhotoGroup] {
//        let fetchOptions = PHFetchOptions()
//        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
//        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
//
//        var groupedAssets: [Date: [PHAsset]] = [:]
//        let calendar = Calendar.current
//
//        allPhotos.enumerateObjects { asset, _, _ in
//            if !self.markedForDeletion.contains(asset.localIdentifier),
//               let date = asset.creationDate,
//               let monthDate = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) {
//                groupedAssets[monthDate, default: []].append(asset)
//            }
//        }
//
//        let formatter = DateFormatter()
//        formatter.dateFormat = "MMMM yyyy"
//
//        let groups = groupedAssets.map { (monthDate, assets) in
//            PhotoGroup(assets: assets, title: formatter.string(from: monthDate), monthDate: monthDate)
//        }
//
//        return groups.sorted { ($0.monthDate ?? .distantPast) > ($1.monthDate ?? .distantPast) }
//    }

    
    func fetchPhotoGroupsByYearAndMonth() async -> [YearGroup] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var groupedByMonth: [Date: [PHAsset]] = [:]
        let calendar = Calendar.current

        allPhotos.enumerateObjects { asset, _, _ in
            if !self.markedForDeletion.contains(asset.localIdentifier),
               let date = asset.creationDate,
               let monthDate = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) {
                groupedByMonth[monthDate, default: []].append(asset)
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"

        var yearMap: [Int: [PhotoGroup]] = [:]
        for (monthDate, assets) in groupedByMonth {
            let components = calendar.dateComponents([.year, .month], from: monthDate)
            let year = components.year ?? 0
            let title = dateFormatter.string(from: monthDate)

            let group = PhotoGroup(assets: assets, title: title, monthDate: monthDate)
            yearMap[year, default: []].append(group)
        }

        let yearGroups = yearMap.map { (year, photoGroups) in
            YearGroup(
                id: year,
                year: year,
                months: photoGroups.sorted { ($0.monthDate ?? .distantPast) > ($1.monthDate ?? .distantPast) }
            )
        }

        return yearGroups.sorted { ($0.year) > ($1.year) }
    }
    
    func fetchSystemAlbums() async -> [PhotoGroup] {
        await fetchPhotoGroupsFromAlbums(albumNames: ["Deleted", "Saved"])
    }

    func fetchPhotoGroupsFromAlbums(albumNames: [String]) async -> [PhotoGroup] {
        var result: [PhotoGroup] = []

        for name in albumNames {
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            collections.enumerateObjects { collection, _, _ in
                if collection.localizedTitle == name {
                    let assets = PHAsset.fetchAssets(in: collection, options: nil)
                    var assetArray: [PHAsset] = []
                    assets.enumerateObjects { asset, _, _ in
                        assetArray.append(asset)
                    }
                    if !assetArray.isEmpty {
                        result.append(PhotoGroup(assets: assetArray, title: name, monthDate: assetArray.first?.creationDate))
                    }
                }
            }
        }

        return result
    }

    func addAsset(_ asset: PHAsset, toAlbumNamed name: String) {
        fetchOrCreateAlbum(named: name) { collection in
            guard let collection = collection else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: collection)?.addAssets([asset] as NSArray)
            }
        }
    }

    func removeAsset(_ asset: PHAsset, fromAlbumNamed name: String) {
        fetchOrCreateAlbum(named: name) { collection in
            guard let collection = collection else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: collection)?.removeAssets([asset] as NSArray)
            }
        }
    }

    func fetchOrCreateAlbum(named title: String, completion: @escaping (PHAssetCollection?) -> Void) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", title)
        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

        if let album = collection.firstObject {
            completion(album)
        } else {
            var placeholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges({
                placeholder = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title).placeholderForCreatedAssetCollection
            }, completionHandler: { success, error in
                guard success, let placeholder = placeholder else {
                    completion(nil)
                    return
                }
                let newCollection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil).firstObject
                completion(newCollection)
            })
        }
    }

    func removeAsset(_ asset: PHAsset, fromGroupWithDate monthDate: Date?) {
        guard let monthDate else { return }
        if let index = self.photoGroups.firstIndex(where: { $0.monthDate == monthDate }) {
            let filteredAssets = self.photoGroups[index].assets.filter { $0.localIdentifier != asset.localIdentifier }
            if filteredAssets.isEmpty {
                self.photoGroups.remove(at: index)
            } else {
                self.photoGroups[index] = self.photoGroups[index].copy(withAssets: filteredAssets)
            }
        }
    }

    func restoreToPhotoGroups(_ asset: PHAsset, inMonth: Date?) {
        guard let inMonth else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let title = formatter.string(from: inMonth)

        if let index = self.photoGroups.firstIndex(where: { $0.monthDate == inMonth }) {
            let updated = [asset] + self.photoGroups[index].assets
            self.photoGroups[index] = self.photoGroups[index].copy(withAssets: updated)
        } else {
            self.photoGroups.insert(PhotoGroup(assets: [asset], title: title, monthDate: inMonth), at: 0)
        }

        removeAsset(asset, fromAlbumNamed: "Deleted")
    }

    func updateGroup(_ id: UUID, withAssets newAssets: [PHAsset]) {
        if let index = photoGroups.firstIndex(where: { $0.id == id }) {
            photoGroups[index] = photoGroups[index].copy(withAssets: newAssets)
        }
    }

    func bookmarkAsset(_ asset: PHAsset) {
        addAsset(asset, toAlbumNamed: "Saved")
    }

    func refreshSystemAlbum(named name: String) async {
        let updated = await fetchPhotoGroupsFromAlbums(albumNames: [name])
        DispatchQueue.main.async {
            for group in updated {
                if let i = self.photoGroups.firstIndex(where: { $0.title == name }) {
                    self.photoGroups[i] = group
                } else {
                    self.photoGroups.append(group)
                }
            }
        }
    }

    func refreshAllPhotoGroups() async {
//        async let months = fetchPhotoGroupsByMonth()
        async let system = fetchSystemAlbums()
        self.photoGroups = await system
        self.yearGroups = await fetchPhotoGroupsByYearAndMonth()
    }
    
    func updateLastViewedIndex(for groupID: UUID, index: Int) {
        if let idx = photoGroups.firstIndex(where: { $0.id == groupID }) {
            var group = photoGroups[idx]
            group.lastViewedIndex = index
            photoGroups[idx] = group

            saveLastViewedIndex(index, for: groupID)
        }
    }

    func saveLastViewedIndex(_ index: Int, for groupID: UUID) {
        UserDefaults.standard.set(index, forKey: "\(lastViewedIndexKey)_\(groupID.uuidString)")
    }

    func loadLastViewedIndex(for groupID: UUID) -> Int {
        UserDefaults.standard.integer(forKey: "\(lastViewedIndexKey)_\(groupID.uuidString)")
    }
    func markForDeletion(_ asset: PHAsset) {
        markedForDeletion.insert(asset.localIdentifier)
    }

    func unmarkForDeletion(_ asset: PHAsset) {
        markedForDeletion.remove(asset.localIdentifier)
    }

    func isMarkedForDeletion(_ asset: PHAsset) -> Bool {
        markedForDeletion.contains(asset.localIdentifier)
    }
    func markForFavourite(_ asset: PHAsset) {
        markedForBookmark.insert(asset.localIdentifier)
    }

    func unmarkForFavourite(_ asset: PHAsset) {
        markedForBookmark.remove(asset.localIdentifier)
    }

    func isMarkedForFavourite(_ asset: PHAsset) -> Bool {
        markedForBookmark.contains(asset.localIdentifier)
    }
    func fetchAlbumCoverImage(for group: PhotoGroup, completion: @escaping (UIImage?) -> Void) {
        guard !group.assets.isEmpty else {
            completion(nil)
            return
        }

        let key = "LastViewedIndex_\(group.id.uuidString)"
        let savedIndex = UserDefaults.standard.integer(forKey: key)
        let safeIndex = min(savedIndex, group.assets.count - 1)

        let asset = group.assets[safeIndex]

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 600, height: 600),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    func handleLeftSwipe(asset: PHAsset, monthDate: Date?) async {
        self.markForDeletion(asset)
        self.removeAsset(asset, fromGroupWithDate: monthDate)
        self.addAsset(asset, toAlbumNamed: "Deleted")
        await self.refreshAllPhotoGroups()
    }
    func hardDeleteAssets(_ assets: [PHAsset]) async {
            guard !assets.isEmpty else { return }

            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }

            for asset in assets {
                self.unmarkForDeletion(asset)
            }

            await self.refreshAllPhotoGroups()
        }
}
