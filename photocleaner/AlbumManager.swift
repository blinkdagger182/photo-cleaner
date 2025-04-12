import Foundation
import Photos
import SwiftUI

class AlbumManager: NSObject {
    // MARK: - Album Operations
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
        let collection = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: fetchOptions)
        
        if let album = collection.firstObject {
            completion(album)
        } else {
            var placeholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges(
                {
                    placeholder =
                    PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                        withTitle: title
                    ).placeholderForCreatedAssetCollection
                },
                completionHandler: { success, error in
                    guard success, let placeholder = placeholder else {
                        completion(nil)
                        return
                    }
                    let newCollection = PHAssetCollection.fetchAssetCollections(
                        withLocalIdentifiers: [placeholder.localIdentifier], options: nil
                    ).firstObject
                    completion(newCollection)
                })
        }
    }
    
    func restoreToPhotoGroups(_ asset: PHAsset, inMonth: Date?) -> PhotoGroup? {
        guard let inMonth else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let title = formatter.string(from: inMonth)
        
        return PhotoGroup(assets: [asset], title: title, monthDate: inMonth)
    }
    
    func hardDeleteAssets(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }
    
    // MARK: - Asset Mutation
    func updateGroup(_ photoGroup: PhotoGroup, withAssets newAssets: [PHAsset]) -> PhotoGroup {
        return photoGroup.copy(withAssets: newAssets)
    }
    
    func bookmarkAsset(_ asset: PHAsset) {
        addAsset(asset, toAlbumNamed: "Saved")
    }
} 