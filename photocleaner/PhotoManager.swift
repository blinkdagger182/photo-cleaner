import Foundation
import Photos
import SwiftUI

@MainActor
class PhotoManager: ObservableObject {
    @Published var allPhotos: [PHAsset] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var photoGroups: [PhotoGroup] = []
    @Published var yearGroups: [YearGroup] = []

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status

        if status == .authorized || status == .limited {
            async let months = fetchPhotoGroupsByMonth()
            async let years = fetchPhotoGroupsByYearAndMonth()
            async let systemAlbums = fetchSystemAlbums()

            self.photoGroups = await months + systemAlbums
            self.yearGroups = await years
        }
    }

  func fetchPhotoGroupsByMonth() async -> [PhotoGroup] {
      let fetchOptions = PHFetchOptions()
      fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

      let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

      var groupedAssets: [Date: [PHAsset]] = [:]
      let calendar = Calendar.current

      allPhotos.enumerateObjects { asset, _, _ in
          guard let date = asset.creationDate else { return }

          // Start of the month
          let components = calendar.dateComponents([.year, .month], from: date)
          if let monthDate = calendar.date(from: components) {
              groupedAssets[monthDate, default: []].append(asset)
          }
      }

      let dateFormatter = DateFormatter()
      dateFormatter.dateFormat = "MMMM yyyy"

      let groups = groupedAssets.map { (monthDate, assets) in
          let title = dateFormatter.string(from: monthDate)
          return PhotoGroup(assets: assets, title: title, monthDate: monthDate)
      }

      // ✅ Sort by actual month date
      return groups.sorted { $0.monthDate > $1.monthDate }
  }
    func fetchPhotoGroupsByYearAndMonth() async -> [YearGroup] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var monthGroups: [Date: [PHAsset]] = [:]
        let calendar = Calendar.current

        allPhotos.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }

            // Group by start of month
            let components = calendar.dateComponents([.year, .month], from: date)
            if let monthDate = calendar.date(from: components) {
                monthGroups[monthDate, default: []].append(asset)
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"

        // Step 1: Build PhotoGroups (month-based)
        let photoGroups: [PhotoGroup] = monthGroups.map { (monthDate, assets) in
            let title = dateFormatter.string(from: monthDate)
            return PhotoGroup(assets: assets, title: title, monthDate: monthDate)
        }

        // Step 2: Group PhotoGroups by year
        let groupedByYear = Dictionary(grouping: photoGroups) { group in
            Calendar.current.component(.year, from: group.monthDate)
        }

        // Step 3: Build YearGroups and sort
        let yearGroups: [YearGroup] = groupedByYear.map { (year, groups) in
            let sortedGroups = groups.sorted { $0.monthDate > $1.monthDate }
            return YearGroup(id: year, year: year, months: sortedGroups)
        }

        return yearGroups.sorted { $0.year > $1.year }
    }


 


    func groupPhotos(thresholdSeconds: Int = 10) {
        var groups: [[PHAsset]] = []
        var currentGroup: [PHAsset] = []

        for (index, asset) in allPhotos.enumerated() {
            guard let currentDate = asset.creationDate else { continue }

            if currentGroup.isEmpty {
                currentGroup.append(asset)
            } else if let lastDate = currentGroup.last?.creationDate,
                      abs(currentDate.timeIntervalSince(lastDate)) <= Double(thresholdSeconds) {
                currentGroup.append(asset)
            } else {
                groups.append(currentGroup)
                currentGroup = [asset]
            }

            if index == allPhotos.count - 1 {
                groups.append(currentGroup)
            }
        }

        self.photoGroups = groups.map { assets in
            let firstDate = assets.first?.creationDate ?? Date()
            return PhotoGroup(assets: assets, title: "Group Succeeded", monthDate: firstDate)
        }
    }
    func fetchPhotoGroupsFromAlbums(albumNames: [String]) async -> [PhotoGroup] {
        var result: [PhotoGroup] = []

        for name in albumNames {
            let fetchOptions = PHFetchOptions()
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)

            collections.enumerateObjects { collection, _, _ in
                if collection.localizedTitle == name {
                    let assets = PHAsset.fetchAssets(in: collection, options: nil)
                    var assetArray: [PHAsset] = []
                    assets.enumerateObjects { asset, _, _ in
                        assetArray.append(asset)
                    }
                    if !assetArray.isEmpty {
                        result.append(PhotoGroup(assets: assetArray, title: name, monthDate: assetArray.first?.creationDate ?? Date()))
                    }
                }
            }
        }

        return result
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
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                placeholder = request.placeholderForCreatedAssetCollection
            }) { success, error in
                if success, let placeholder = placeholder {
                    let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
                    completion(collection.firstObject)
                } else {
                    completion(nil)
                }
            }
        }
    }

    func addAsset(_ asset: PHAsset, toAlbumNamed name: String) {
        fetchOrCreateAlbum(named: name) { collection in
            guard let collection = collection else { return }

            PHPhotoLibrary.shared().performChanges {
                if let changeRequest = PHAssetCollectionChangeRequest(for: collection) {
                    changeRequest.addAssets([asset] as NSArray)
                }
            }
        }
    }

    func softDeleteAsset(_ asset: PHAsset) {
        addAsset(asset, toAlbumNamed: "Deleted")
        DispatchQueue.main.async {
            self.photoGroups = self.photoGroups.map { group in
                let filtered = group.assets.filter { $0.localIdentifier != asset.localIdentifier }
                return PhotoGroup(assets: filtered, title: group.title, monthDate: group.monthDate)
            }.filter { !$0.assets.isEmpty }
        }
    }

    func bookmarkAsset(_ asset: PHAsset) {
        addAsset(asset, toAlbumNamed: "Saved")
    }

    func removeAsset(_ asset: PHAsset, fromAlbumNamed name: String) {
        fetchOrCreateAlbum(named: name) { collection in
            guard let collection = collection else { return }

            PHPhotoLibrary.shared().performChanges {
                if let changeRequest = PHAssetCollectionChangeRequest(for: collection) {
                    changeRequest.removeAssets([asset] as NSArray)
                }
            }
        }
    }
    func restoreToPhotoGroups(_ asset: PHAsset) {
        guard let date = asset.creationDate else { return }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let monthDate = calendar.date(from: components) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let title = formatter.string(from: monthDate)

        DispatchQueue.main.async {
            if let index = self.photoGroups.firstIndex(where: { $0.monthDate == monthDate }) {
                var existingGroup = self.photoGroups[index]
                let updatedAssets = [asset] + existingGroup.assets
                let updatedGroup = PhotoGroup(assets: updatedAssets, title: title, monthDate: monthDate)
                self.photoGroups[index] = updatedGroup
            } else {
                self.photoGroups.insert(
                    PhotoGroup(assets: [asset], title: title, monthDate: monthDate),
                    at: 0
                )
            }
        }
    }
    func fetchSystemAlbums() async -> [PhotoGroup] {
        let albums = await fetchPhotoGroupsFromAlbums(albumNames: ["Deleted", "Saved"])
        return albums
    }
}
