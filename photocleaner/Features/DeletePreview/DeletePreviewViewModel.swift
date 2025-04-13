import SwiftUI
import Photos

class DeletePreviewViewModel: ObservableObject {
    @Published var entries: [DeletePreviewEntry]
    
    private let photoManager = PhotoManager.shared
    private let toastService = ToastService.shared
    
    init(entries: [DeletePreviewEntry]) {
        self.entries = entries
    }
    
    func confirmDeletion() {
        Task {
            await photoManager.deletePhotos(from: entries)
            await MainActor.run {
                toastService.show(message: "\(entries.count) photos deleted", type: .success)
            }
        }
    }
} 