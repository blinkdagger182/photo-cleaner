import SwiftUI
import Photos

class DeletePreviewViewModel: ObservableObject {
    @Published var entries: [DeletePreviewEntry]
    
    private let photoManager: PhotoManager
    private let toastService: ToastService
    private let onDismiss: (() -> Void)?
    
    init(entries: [DeletePreviewEntry], photoManager: PhotoManager, toastService: ToastService, onDismiss: (() -> Void)? = nil) {
        self.entries = entries
        self.photoManager = photoManager
        self.toastService = toastService
        self.onDismiss = onDismiss
    }
    
    // Convenience initializer that doesn't rely on shared instances directly in default parameters
    static func create(entries: [DeletePreviewEntry], onDismiss: (() -> Void)? = nil) -> DeletePreviewViewModel {
        return DeletePreviewViewModel(
            entries: entries,
            photoManager: PhotoManager.shared,
            toastService: ToastService.shared,
            onDismiss: onDismiss
        )
    }
    
    func confirmDeletion() {
        Task {
            await photoManager.deletePhotos(from: entries)
            await MainActor.run {
                toastService.show(message: "\(entries.count) photos deleted", type: .success)
                if let onDismiss = onDismiss {
                    onDismiss()
                }
            }
        }
    }
    
    func dismiss() {
        if let onDismiss = onDismiss {
            onDismiss()
        }
    }
} 