import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var toast: ToastService
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    
    // Track the selected tab
    @State private var selectedTab = 0
    @State private var showMarketingBanner = true
    
    // UserDefaults key for banner visibility
    private let marketingBannerKey = "hasHiddenMarketingBanner"
    
    var body: some View {
        // Check if user has previously dismissed the banner
        let hasHiddenBanner = UserDefaults.standard.bool(forKey: marketingBannerKey)
        
        ZStack(alignment: .bottom) {
            // Main TabView content
            TabView(selection: $selectedTab) {
            // Photo Library Tab
            PhotoGroupView(photoManager: photoManager)
                .environmentObject(photoManager)
                .environmentObject(toast)
                .tabItem {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                .tag(0)
            
            // Discover Tab
            DiscoverView(photoManager: photoManager)
                .environmentObject(photoManager)
                .environmentObject(toast)
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }
                .tag(1)
            }
            
            // Marketing banner that appears only on the Library tab
            // and only for non-subscribed users who haven't dismissed it
            if selectedTab == 0 && showMarketingBanner && !subscriptionManager.isPremium && !hasHiddenBanner {
                VStack {
                    Spacer()
                    
                    MarketingBanner {
                        // Switch to Discover tab when banner is tapped
                        selectedTab = 1
                    } onDismiss: {
                        // Hide banner and save preference
                        withAnimation {
                            showMarketingBanner = false
                        }
                        UserDefaults.standard.set(true, forKey: marketingBannerKey)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, UIApplication.shared.windows.first?.safeAreaInsets.bottom == 0 ? 70 : 100) // Adaptive padding based on device type
                }
                .animation(.easeInOut, value: selectedTab)
                .zIndex(1) // Ensure banner appears above tab content
                .ignoresSafeArea(edges: .bottom) // Allow banner to extend into safe area
            }
        }
    }
} 