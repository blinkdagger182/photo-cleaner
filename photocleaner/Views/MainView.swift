import SwiftUI

struct MainView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        ContentView()
            .environmentObject(coordinator.photoManager)
            .environmentObject(coordinator.toastService)
            .transition(.opacity)
    }
}
