import SwiftUI
import Photos

class DeletePreviewViewModel: ObservableObject {
    @Published var entries: [DeletePreviewEntry]
    
    private let coordinator: MainFlowCoordinator
    private let photoManager = PhotoManager.shared
    private let toastService = ToastService.shared
    
    init(entries: [DeletePreviewEntry], coordinator: MainFlowCoordinator) {
        self.entries = entries
        self.coordinator = coordinator
    }
    
    func confirmDeletion() {
        Task {
            await photoManager.deletePhotos(from: entries)
            await MainActor.run {
                coordinator.hideDeletePreview()
                toastService.show(message: "\(entries.count) photos deleted", type: .success)
            }
        }
    }
} 