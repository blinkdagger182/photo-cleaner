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
            await loadPhotos()
        }
    }

    func loadPhotos() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var assets: [PHAsset] = []

        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        self.allPhotos = assets
        self.groupPhotos()
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

        self.photoGroups = groups.map { PhotoGroup(assets: $0) }
    }

}
