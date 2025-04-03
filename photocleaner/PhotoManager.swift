import Foundation
import Photos
import SwiftUI

@MainActor
class PhotoManager: ObservableObject {
    @Published var allPhotos: [PHAsset] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var photoGroups: [PhotoGroup] = []

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        if status == .authorized || status == .limited {
            self.photoGroups = await fetchPhotoGroupsByMonth()
        }
    }

//    func loadPhotos() async {
//        let fetchOptions = PHFetchOptions()
//        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
//        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
//        var assets: [PHAsset] = []
//
//        result.enumerateObjects { asset, _, _ in
//            assets.append(asset)
//        }
//        
//        self.fetchPhotoGroupsByMonth()
//        self.allPhotos = assets
//        self.groupPhotos()
//    }
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
