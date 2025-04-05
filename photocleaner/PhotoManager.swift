import Foundation
import Photos
import SwiftUI

@MainActor
class PhotoManager: ObservableObject {
    @Published var allPhotos: [PHAsset] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var photoGroups: [PhotoGroup] = []
    @Published var yearGroups: [YearGroup] = []
    
    private let lastViewedIndexKey = "LastViewedIndex"
    
    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status

        if status == .authorized || status == .limited {
            async let months = fetchPhotoGroupsByMonth()
            async let years = fetchPhotoGroupsByYearAndMonth()
            async let systemAlbums = fetchSystemAlbums()

            self.photoGroups = await months + systemAlbums
            self.yearGroups = await years
            print("years:", await years)
            print("systemAlbums:", await systemAlbums)
            print("months:", await months)
            print("photoGroups:", photoGroups)
        }
    }

    func fetchPhotoGroupsByMonth() async -> [PhotoGroup] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var groupedAssets: [Date: [PHAsset]] = [:]
        let calendar = Calendar.current

        allPhotos.enumerateObjects { asset, _, _ in
            if let date = asset.creationDate,
               let monthDate = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) {
                groupedAssets[monthDate, default: []].append(asset)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let groups = groupedAssets.map { (monthDate, assets) in
            PhotoGroup(assets: assets, title: formatter.string(from: monthDate), monthDate: monthDate)
        }

        return groups.sorted { ($0.monthDate ?? .distantPast) > ($1.monthDate ?? .distantPast) }
    }

    func fetchPhotoGroupsByYearAndMonth() async -> [YearGroup] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var monthGroups: [Date: [PHAsset]] = [:]
        let calendar = Calendar.current

        allPhotos.enumerateObjects { asset, _, _ in
            if let date = asset.creationDate,
               let monthDate = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) {
                monthGroups[monthDate, default: []].append(asset)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let photoGroups = monthGroups.map { (monthDate, assets) in
            PhotoGroup(assets: assets, title: formatter.string(from: monthDate), monthDate: monthDate)
        }

        let groupedByYear = Dictionary(grouping: photoGroups) {
            Calendar.current.component(.year, from: $0.monthDate ?? .distantPast)
        }

        return groupedByYear.map { (year, groups) in
            YearGroup(id: year, year: year, months: groups.sorted { ($0.monthDate ?? .distantPast) > ($1.monthDate ?? .distantPast) })
        }.sorted { $0.year > $1.year }
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
        async let months = fetchPhotoGroupsByMonth()
        async let system = fetchSystemAlbums()
        self.photoGroups = await months + system
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
}
