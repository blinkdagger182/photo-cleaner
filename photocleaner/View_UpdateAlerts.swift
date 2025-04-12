import SwiftUI

extension View {
    func withUpdateAlerts(using updateService: UpdateService, modalCoordinator: ModalCoordinator) -> some View {
        self
            .task {
                if updateService.shouldForceUpdate {
                    modalCoordinator.showForceUpdate(notes: updateService.updateNotes)
                } else if updateService.shouldShowOptionalUpdate {
                    modalCoordinator.showOptionalUpdate(notes: updateService.updateNotes) {
                        updateService.dismissedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                        updateService.shouldShowOptionalUpdate = false
                    }
                }
            }
    }
}
