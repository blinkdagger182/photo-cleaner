import SwiftUI
import Combine

class UpdateCoordinator: ObservableObject {
    // Reference to parent coordinator
    weak var parent: AppCoordinator?
    
    // Modal presentation states
    @Published var showingOptionalUpdate = false
    @Published var currentAppVersion: AppVersion?
    
    // Services
    private var updateService: UpdateService
    
    init(parent: AppCoordinator, updateService: UpdateService) {
        self.parent = parent
        self.updateService = updateService
    }
    
    // Check for updates
    func checkForUpdates() {
        Task {
            do {
                let (needsForceUpdate, hasOptionalUpdate, latestVersion) = try await updateService.checkForUpdates()
                
                await MainActor.run {
                    if let latestVersion = latestVersion {
                        self.currentAppVersion = latestVersion
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
        // Check if version exists before showing update sheet
        if currentAppVersion != nil {
            self.showingOptionalUpdate = true
        }
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
