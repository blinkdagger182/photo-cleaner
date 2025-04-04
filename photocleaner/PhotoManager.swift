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
            self.yearGroups = await fetchPhotoGroupsByYearAndMonth()
            self.photoGroups = await fetchPhotoGroupsByMonth()
               self.yearGroups = await fetchPhotoGroupsByYearAndMonth()
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
        }    }

}
