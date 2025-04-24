import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var toast: ToastService
    
    var body: some View {
        TabView {
            // Photo Library Tab
            PhotoGroupView(photoManager: photoManager)
                .environmentObject(photoManager)
                .environmentObject(toast)
                .tabItem {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
            
            // Discover Tab
            DiscoverView(photoManager: photoManager)
                .environmentObject(photoManager)
                .environmentObject(toast)
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }
        }
    }
} 