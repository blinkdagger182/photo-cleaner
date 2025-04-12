import Foundation
import Photos
import SwiftUI

class PhotoManager: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    // MARK: - Published Properties
    @Published var allPhotos: [PHAsset] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allAssets: [PHAsset] = []
    @Published var photoGroups: [PhotoGroup] = []
    @Published var yearGroups: [YearGroup] = []
    @Published var markedForDeletion: Set<String> = []  // asset.localIdentifier
    @Published var markedForBookmark: Set<String> = []

    // MARK: - Dependencies
    private let photoLibraryService = PhotoLibraryService.shared
    private let albumManager = AlbumManager.shared
    
    // MARK: - Singleton
    static let shared = PhotoManager()
    
    // MARK: - Initialization
    private override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    @objc func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            print("🔄 Library changed, reloading photos...")
            await self.loadAssets()
        }
    }

    // MARK: - Public API
    func requestAuthorization() async {
        let status = await photoLibraryService.requestAuthorization()

        await MainActor.run {
            self.authorizationStatus = status
        }

        if status == .authorized || status == .limited {
            async let years = fetchPhotoGroupsByYearAndMonth()
            async let systemAlbums = fetchSystemAlbums()

            let fetchedYears = await years
            let fetchedSystemAlbums = await systemAlbums

            await MainActor.run {
                self.yearGroups = fetchedYears
                self.photoGroups = fetchedYears.flatMap { $0.months } + fetchedSystemAlbums
            }
        }
    }

    func fetchPhotoGroupsByYearAndMonth() async -> [YearGroup] {
        return await photoLibraryService.fetchPhotoGroupsByYearAndMonth(markedForDeletion: markedForDeletion)
    }

    func fetchSystemAlbums() async -> [PhotoGroup] {
        return await photoLibraryService.fetchSystemAlbums()
    }

    func fetchPhotoGroupsFromAlbums(albumNames: [String]) async -> [PhotoGroup] {
        return await photoLibraryService.fetchPhotoGroupsFromAlbums(albumNames: albumNames)
    }

    func addAsset(_ asset: PHAsset, toAlbumNamed name: String) {
        albumManager.addAsset(asset, toAlbumNamed: name)
    }

    func removeAsset(_ asset: PHAsset, fromAlbumNamed name: String) {
        albumManager.removeAsset(asset, fromAlbumNamed: name)
    }

    func restoreToPhotoGroups(_ asset: PHAsset, inMonth: Date?) {
        guard let inMonth else { return }

        if let newGroup = albumManager.restoreToPhotoGroups(asset, inMonth: inMonth) {
            if let index = self.photoGroups.firstIndex(where: { $0.monthDate == inMonth }) {
                let updated = [asset] + self.photoGroups[index].assets
                self.photoGroups[index] = self.photoGroups[index].copy(withAssets: updated)
            } else {
                self.photoGroups.insert(newGroup, at: 0)
            }
        }

        removeAsset(asset, fromAlbumNamed: "Deleted")
    }

    func updateGroup(_ id: UUID, withAssets newAssets: [PHAsset]) {
        if let index = photoGroups.firstIndex(where: { $0.id == id }) {
            photoGroups[index] = albumManager.updateGroup(photoGroups[index], withAssets: newAssets)
        }
    }

    func bookmarkAsset(_ asset: PHAsset) {
        albumManager.bookmarkAsset(asset)
    }

    func refreshAllPhotoGroups() async {
        async let system = fetchSystemAlbums()
        async let yearGroups = fetchPhotoGroupsByYearAndMonth()

        let systemResult = await system
        let yearResult = await yearGroups

        await MainActor.run {
            self.photoGroups = yearResult.flatMap { $0.months } + systemResult
            self.yearGroups = yearResult
        }
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
        photoLibraryService.saveLastViewedIndex(index, for: groupID)
    }

    func loadLastViewedIndex(for groupID: UUID) -> Int {
        return photoLibraryService.loadLastViewedIndex(for: groupID)
    }
    
    func markForDeletion(_ asset: PHAsset) {
        markedForDeletion.insert(asset.localIdentifier)
    }

    func unmarkForDeletion(_ asset: PHAsset) {
        Task { @MainActor in
            self.markedForDeletion.remove(asset.localIdentifier)
        }
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
        photoLibraryService.fetchAlbumCoverImage(for: group, completion: completion)
    }
    
    func handleLeftSwipe(asset: PHAsset, monthDate: Date?) async {
        self.markForDeletion(asset)
        await self.refreshAllPhotoGroups()
    }
    
    func deletePhotos(from entries: [DeletePreviewEntry]) async {
        let assets = entries.map { $0.asset }
        await hardDeleteAssets(assets)
    }
    
    func hardDeleteAssets(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }

        do {
            try await albumManager.hardDeleteAssets(assets)
            
            for asset in assets {
                self.unmarkForDeletion(asset)
            }
            
            await self.refreshAllPhotoGroups()
        } catch {
            print("Error deleting assets: \(error)")
        }
    }
    
    func loadAssets() async {
        async let years = fetchPhotoGroupsByYearAndMonth()
        async let systemAlbums = fetchSystemAlbums()

        let fetchedYears = await years
        let fetchedSystemAlbums = await systemAlbums

        await MainActor.run {
            self.yearGroups = fetchedYears
            self.photoGroups = fetchedYears.flatMap { $0.months } + fetchedSystemAlbums
        }
    }
} 