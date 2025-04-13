import SwiftUI

extension View {
    func withUpdateAlerts(coordinator: UpdateCoordinator) -> some View {
        self.modifier(UpdateAlertsModifier(coordinator: coordinator))
    }
}

struct UpdateAlertsModifier: ViewModifier {
    @ObservedObject var coordinator: UpdateCoordinator
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $coordinator.showingOptionalUpdate) {
                if let version = coordinator.currentAppVersion {
                    OptionalUpdateSheet(version: version, coordinator: coordinator)
                        .presentationDetents([.medium, .large])
                }
            }
    }
} 