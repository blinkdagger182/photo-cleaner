import Foundation
import Photos
import SwiftUI

class PhotoLibraryService: NSObject {
    // MARK: - Properties
    private let lastViewedIndexKey = "LastViewedIndex"
    static let shared = PhotoLibraryService()
    
    // MARK: - Authorization
    func requestAuthorization() async -> PHAuthorizationStatus {
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
    
    // MARK: - Fetch Methods
    func fetchPhotoGroupsByYearAndMonth(markedForDeletion: Set<String>) async -> [YearGroup] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var groupedByMonth: [Date: [PHAsset]] = [:]
        let calendar = Calendar.current
        
        allPhotos.enumerateObjects { asset, _, _ in
            if !markedForDeletion.contains(asset.localIdentifier),
               let date = asset.creationDate,
               let monthDate = calendar.date(
                from: calendar.dateComponents([.year, .month], from: date))
            {
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
                months: photoGroups.sorted {
                    ($0.monthDate ?? .distantPast) > ($1.monthDate ?? .distantPast)
                }
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
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .any, options: nil)
            collections.enumerateObjects { collection, _, _ in
                if collection.localizedTitle == name {
                    let assets = PHAsset.fetchAssets(in: collection, options: nil)
                    var assetArray: [PHAsset] = []
                    assets.enumerateObjects { asset, _, _ in
                        assetArray.append(asset)
                    }
                    if !assetArray.isEmpty {
                        result.append(
                            PhotoGroup(
                                assets: assetArray, title: name,
                                monthDate: assetArray.first?.creationDate))
                    }
                }
            }
        }
        
        return result
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
    
    // MARK: - User Defaults Management
    func saveLastViewedIndex(_ index: Int, for groupID: UUID) {
        UserDefaults.standard.set(index, forKey: "\(lastViewedIndexKey)_\(groupID.uuidString)")
    }
    
    func loadLastViewedIndex(for groupID: UUID) -> Int {
        UserDefaults.standard.integer(forKey: "\(lastViewedIndexKey)_\(groupID.uuidString)")
    }
} 