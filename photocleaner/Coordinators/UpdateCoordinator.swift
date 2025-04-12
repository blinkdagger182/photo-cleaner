import SwiftUI
import Combine

class UpdateCoordinator: ObservableObject {
    // Reference to parent coordinator
    weak var parent: AppCoordinator?
    
    // Modal presentation states
    @Published var showingOptionalUpdate = false
    @Published var currentAppVersion: AppVersion?
    
    // Services
    private let updateService = UpdateService.shared
    
    init(parent: AppCoordinator) {
        self.parent = parent
    }
    
    // Check for app updates
    func checkForUpdates() {
        Task {
            do {
                let (needsForceUpdate, hasOptionalUpdate, version) = try await updateService.checkForUpdates()
                
                await MainActor.run {
                    if let version = version {
                        self.currentAppVersion = version
                    }
                    
                    if needsForceUpdate {
                        parent?.appState.forceUpdateRequired = true
                    } else if hasOptionalUpdate {
                        self.showOptionalUpdateSheet()
                    }
                }
            } catch {
                print("Failed to check for updates: \(error)")
            }
        }
    }
    
    // Show optional update sheet
    func showOptionalUpdateSheet() {
        guard let version = currentAppVersion else { return }
        self.showingOptionalUpdate = true
    }
    
    // Hide optional update sheet
    func hideOptionalUpdateSheet() {
        self.showingOptionalUpdate = false
    }
    
    // Open App Store to update
    func openAppStore() {
        if let url = updateService.appStoreURL {
            UIApplication.shared.open(url)
        }
    }
} 