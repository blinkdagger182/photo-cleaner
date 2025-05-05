import SwiftUI
import Photos
import AVFoundation
import StoreKit

// Define a completion handler to pass data back to parent view
struct DeletionResult {
    let success: Bool
    let memorySavedMB: Double
    let totalMemoryMB: Double
}

/// A custom ViewModifier to add swipe to unmark functionality
struct SwipeToUnmark: ViewModifier {
    var entry: DeletePreviewEntry
    var action: (DeletePreviewEntry) -> Void
    @State private var offset: CGSize = .zero
    @State private var isSwiping = false
    
    func body(content: Content) -> some View {
        content
            .offset(offset)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        // Only allow horizontal swiping, and primarily left to right
                        let horizontalAmount = gesture.translation.width
                        if horizontalAmount > 0 {
                            // Right swipe (unmark)
                            isSwiping = true
                            offset = CGSize(width: min(horizontalAmount, 100), height: 0)
                        }
                    }
                    .onEnded { _ in
                        if offset.width > 50 {
                            // Swipe far enough to trigger unmark
                            action(entry)
                        }
                        
                        // Animate back to start position
                        withAnimation(.spring()) {
                            offset = .zero
                            isSwiping = false
                        }
                    }
            )
            .overlay(
                HStack {
                    Text("Unmark")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(8)
                        .opacity(isSwiping ? min(offset.width / 50, 1.0) : 0)
                    
                    Spacer()
                }
                .padding(.leading, 8)
            )
    }
}

extension View {
    func swipeToUnmark(entry: DeletePreviewEntry, action: @escaping (DeletePreviewEntry) -> Void) -> some View {
        self.modifier(SwipeToUnmark(entry: entry, action: action))
    }
}

struct DeletePreviewView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @Binding var forceRefresh: Bool
    var onDeletionComplete: ((DeletionResult) -> Void)? = nil
    
    // Remove the entries binding and use a @State variable instead
    @State private var previewEntries: [DeletePreviewEntry] = []
    @State private var isLoading = false
    @State private var selectedEntries: Set<UUID> = []
    @State private var isDeleting = false
    @State private var deletionComplete = false

    var selectedCount: Int {
        selectedEntries.count
    }

    var totalSize: Int {
        previewEntries.filter { selectedEntries.contains($0.id) }.map { $0.fileSize }.reduce(0, +)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.primary)
                }
                .padding([.top, .trailing], 16)
            }

            Text("Ready to Clean Up?").font(.title).bold()
            Text("You're about to delete \(selectedCount) photos\nFree up to \(formattedSize) of storage.")
                .multilineTextAlignment(.center)
                .font(.subheadline)

            if isLoading {
                // Show a loading state
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading deleted photos...")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if previewEntries.isEmpty {
                // Show an empty state when no photos are marked for deletion
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No Photos Marked for Deletion")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Go back and mark some photos to delete them")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20)
                    ], spacing: 20) {
                        ForEach(previewEntries) { entry in
                            let isSelected = selectedEntries.contains(entry.id)
                            ZStack {
                                Image(uiImage: entry.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: UIScreen.main.bounds.width / 4.0, height: UIScreen.main.bounds.width / 4.0)
                                    .clipped()
                                    .cornerRadius(8)
                                    .overlay(
                                        isSelected ? Color.black.opacity(0.25) : Color.clear
                                    )
                                    .overlay(
                                        isSelected ? Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                            .padding(6) : nil,
                                        alignment: .topTrailing
                                    )
                                    .contentShape(Rectangle()) // Use precise content shape for hit testing
                                
                                // Unmark button overlay in a separate layer with its own tap area
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Button(action: {
                                            unmarkPhotoForDeletion(entry)
                                        }) {
                                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(.white)
                                                .shadow(radius: 2)
                                                .padding(6)
                                                .background(Color.black.opacity(0.001)) // Invisible background to increase hit area
                                                .contentShape(Circle()) // Clear hit testing boundary
                                        }
                                        .padding(4) // Add padding to the button itself
                                    }
                                }
                            }
                            .aspectRatio(1, contentMode: .fit) // Maintain square aspect ratio
                            .background(Color.clear) // Ensure background is clear
                            // Add a separate tap gesture to handle selection
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if isSelected {
                                        selectedEntries.remove(entry.id)
                                    } else {
                                        selectedEntries.insert(entry.id)
                                    }
                                }
                            }
                            .padding(8) // Increase padding between cells
                            // .swipeToUnmark(entry: entry, action: unmarkPhotoForDeletion)
                        }
                    }
                    .padding()
                    .background(Color.clear) // Ensure GridView background is clear
                }
                .background(Color.clear) // Ensure ScrollView background is clear
            }

            if deletionComplete {
                Label("Deleted", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)
            } else if isDeleting {
                ProgressView("Deleting…")
            } else {
                Button(action: deleteSelectedPhotos) {
                    Text("Delete")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .disabled(previewEntries.isEmpty || selectedEntries.isEmpty)
                .opacity(previewEntries.isEmpty || selectedEntries.isEmpty ? 0.5 : 1)
            }
        }
        .padding()
        .onAppear {
            // Load preview entries directly from PhotoManager
            Task {
                await loadPreviewEntries()
            }
        }
    }

    /// Load preview entries directly from PhotoManager.markedForDeletion
    private func loadPreviewEntries() async {
        // Begin loading
        await MainActor.run { isLoading = true }
        
        // Get the unique set of identifiers directly from PhotoManager
        let identifiers = Array(photoManager.markedForDeletion)
        
        // Exit early if no identifiers
        if identifiers.isEmpty {
            await MainActor.run { 
                isLoading = false 
                previewEntries = []
            }
            return
        }
        
        print("Loading \(identifiers.count) asset(s) for deletion preview")
        
        // Fetch assets for these identifiers
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        let fetchedCount = fetchResult.count
        
        // Check if any identifiers couldn't be found (assets deleted externally)
        if fetchedCount < identifiers.count {
            print("⚠️ Some assets marked for deletion no longer exist (\(identifiers.count - fetchedCount) missing)")
            
            // Collect the identifiers of successfully fetched assets
            var foundIdentifiers: [String] = []
            fetchResult.enumerateObjects { asset, _, _ in
                foundIdentifiers.append(asset.localIdentifier)
            }
            
            // Find missing identifiers by comparing with the full list
            let missingIdentifiers = identifiers.filter { !foundIdentifiers.contains($0) }
            
            // Remove invalid identifiers from tracking in PhotoManager
            photoManager.removeInvalidDeletionIdentifiers(missingIdentifiers)
        }
        
        // Only proceed if we have assets to display
        if fetchedCount > 0 {
            var newEntries: [DeletePreviewEntry] = []
            
            // Create an array of assets first
            var assets: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            
            // Create a group for concurrent image loading
            await withTaskGroup(of: (PHAsset, UIImage)?.self) { group in
                // Add image loading tasks for each asset
                for asset in assets {
                    let localAsset = asset
                    group.addTask {
                        // Load thumbnail for asset
                        if let image = await self.loadThumbnailImage(for: localAsset) {
                            return (localAsset, image)
                        }
                        return nil
                    }
                }
                
                // Process results as they complete
                for await result in group {
                    if let (asset, image) = result {
                        let size = asset.estimatedAssetSize
                        let entry = DeletePreviewEntry(asset: asset, image: image, fileSize: size)
                        newEntries.append(entry)
                    }
                }
            }
            
            // Update state with new entries
            await MainActor.run {
                self.previewEntries = newEntries
                self.selectedEntries = Set(newEntries.map { $0.id }) // Select all by default
                self.isLoading = false
            }
        } else {
            // No assets found - clear entries and end loading
            await MainActor.run {
                self.previewEntries = []
                self.isLoading = false
            }
        }
    }

    /// Helper to load a thumbnail image for an asset
    private func loadThumbnailImage(for asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            // Track if we've already resumed to prevent multiple resumes
            var hasResumed = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Guard against multiple resume calls
                guard !hasResumed else { return }
                
                // Check for cancellation or errors
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = (info?[PHImageErrorKey] != nil)
                
                if cancelled || hasError {
                    // PHImageManager will call again with the final result
                    return
                }
                
                // Mark as resumed and return the image
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }

    private func deleteSelectedPhotos() {
        isDeleting = true
        let toDelete = previewEntries.filter { selectedEntries.contains($0.id) }
        let assetsToDelete = toDelete.map { $0.asset }

        // Calculate actual memory saved from file sizes
        let savedBytes = toDelete.map { $0.fileSize }.reduce(0, +)
        let memorySavedMB = Double(savedBytes) / (1024 * 1024) // Convert bytes to MB
        
        // Get device total storage
        var totalStorageSpace: Double = 0
        if let deviceSpaceTuple = getDeviceStorage() {
            totalStorageSpace = deviceSpaceTuple.totalSpace
        } else {
            totalStorageSpace = 1024 * 64 // Fallback to 64GB if we can't get the actual value
        }
        
        Task {
            // Wait for the hardDeleteAssets operation and get the success status
            let deletionSucceeded = await photoManager.hardDeleteAssets(assetsToDelete)

            await MainActor.run {
                if deletionSucceeded {
                    // Deletion was successful - update UI accordingly
                    isDeleting = false
                    deletionComplete = true
                    
                    // Play success sound when deletion completes and we show the green tick
                    SoundManager.shared.playSound(named: "air-whoosh")
                    
                    // Delay to allow completion animation to be visible
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        // Create deletion result to pass back to parent
                        let result = DeletionResult(
                            success: true,
                            memorySavedMB: memorySavedMB,
                            totalMemoryMB: totalStorageSpace
                        )
                        
                        // Dismiss this view
                        dismiss()
                        forceRefresh.toggle()
                        
                        // Pass result back to parent view
                        onDeletionComplete?(result)
                    }
                } else {
                    // Deletion failed or was canceled by user - reset UI and inform user
                    isDeleting = false
                    
                    // Show toast message about deletion failure/cancellation
                    toast.showError("Deletion was canceled or failed. Your photos were not deleted.", duration: 2.0)
                }
            }
        }
    }

    // Helper function to get device storage info
    private func getDeviceStorage() -> (totalSpace: Double, freeSpace: Double)? {
        let fileManager = FileManager.default
        
        do {
            let documentDirectoryURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            
            // Get the volume of the current directory
            let resourceValues = try documentDirectoryURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            
            if let totalCapacity = resourceValues.volumeTotalCapacity,
               let availableCapacity = resourceValues.volumeAvailableCapacity {
                // Convert to MB
                let totalSpaceMB = Double(totalCapacity) / (1024 * 1024)
                let freeSpaceMB = Double(availableCapacity) / (1024 * 1024)
                
                return (totalSpaceMB, freeSpaceMB)
            }
        } catch {
            print("Error getting device storage: \(error.localizedDescription)")
        }
        
        return nil
    }

    /// Unmark a photo from deletion and remove it from the current view
    private func unmarkPhotoForDeletion(_ entry: DeletePreviewEntry) {
        // Remove the entry from the local preview entries
        if let index = previewEntries.firstIndex(where: { $0.id == entry.id }) {
            // Remove from selected entries (if selected)
            selectedEntries.remove(entry.id)
            
            // Remove from preview entries
            previewEntries.remove(at: index)
            
            // Unmark from PhotoManager
            photoManager.unmarkForDeletion(entry.asset)
            
            // Show toast notification
            toast.showSuccess("Photo removed from deletion list", duration: 1.5)
        }
    }

    // Function to request app review
    private func requestAppReview() {
        // Check if we're on a physical device (StoreKit review prompts don't work in simulators)
        #if !targetEnvironment(simulator)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            print("No window scene found, skipping review request")
            return
        }
        
        // Request the review
        if #available(iOS 14.0, *) {
            SKStoreReviewController.requestReview(in: windowScene)
        } else {
            // Fallback on earlier versions
            SKStoreReviewController.requestReview()
        }
        #else
        // We're running in the simulator, show a message via toast
        toast.showInfo("App review requested. This only works on physical devices.", duration: 2.0)
        #endif
    }
}
