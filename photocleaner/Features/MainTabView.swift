import SwiftUI

struct MainTabView: View {
    // Environment objects
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var toast: ToastService
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    
    // Track the current tab index (0 = Library, 1 = Discover)
    @State private var currentTab = 0
    @State private var showMarketingBanner = true
    
    // UserDefaults key for banner visibility
    private let marketingBannerKey = "hasHiddenMarketingBanner"
    
    // For swipe gesture navigation
    @State private var dragOffset: CGFloat = 0
    @State private var previousDragOffset: CGFloat = 0
    
    // Tab titles
    private let tabs = ["Library", "Discover"]
    
    // For matched geometry effect
    @Namespace private var namespace
    
    var body: some View {
        // Check if user has previously dismissed the banner
        let hasHiddenBanner = UserDefaults.standard.bool(forKey: marketingBannerKey)
        
        VStack(spacing: 0) {
            // Tab indicator at the top
            HStack(spacing: 20) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            currentTab = index
                        }
                    }) {
                        VStack(spacing: 8) {
                            Text(tabs[index])
                                .font(.system(size: 16, weight: currentTab == index ? .semibold : .medium))
                                .foregroundColor(currentTab == index ? .primary : .secondary)
                            
                            // Indicator line
                            Rectangle()
                                .fill(currentTab == index ? Color.accentColor : Color.clear)
                                .frame(height: 2)
                                .matchedGeometryEffect(id: "tab_indicator", in: namespace, isSource: currentTab == index)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Main content with swipe gesture
            let screenWidth = UIScreen.main.bounds.width
            
            ZStack {
                // Library view (at index 0)
                PhotoGroupView(photoManager: photoManager)
                    .environmentObject(photoManager)
                    .environmentObject(toast)
                    .offset(x: currentTab == 0 ? dragOffset : -screenWidth + dragOffset)
                
                // Discover view (at index 1)
                DiscoverView(photoManager: photoManager)
                    .environmentObject(photoManager)
                    .environmentObject(toast)
                    .offset(x: currentTab == 0 ? screenWidth + dragOffset : dragOffset)
            }
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        // Direct tracking of finger position
                        let translation = gesture.translation.width
                        
                        // Apply resistance at the edges
                        if (currentTab == 0 && translation > 0) || (currentTab == 1 && translation < 0) {
                            // Apply resistance when trying to swipe beyond the first or last tab
                            dragOffset = translation / 3
                        } else {
                            // Normal drag within the valid range
                            dragOffset = translation
                        }
                    }
                    .onEnded { gesture in
                        let translation = gesture.translation.width
                        let velocity = gesture.velocity.width
                        let predictedEndTranslation = gesture.predictedEndTranslation.width
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            // Determine if we should change tabs based on drag distance or velocity
                            if (currentTab == 0 && translation < -screenWidth/4) || 
                               (currentTab == 0 && velocity < -500) ||
                               (currentTab == 0 && predictedEndTranslation < -screenWidth/3) {
                                // Swiped left with enough force/distance, go to Discover
                                currentTab = 1
                            } else if (currentTab == 1 && translation > screenWidth/4) || 
                                      (currentTab == 1 && velocity > 500) ||
                                      (currentTab == 1 && predictedEndTranslation > screenWidth/3) {
                                // Swiped right with enough force/distance, go to Library
                                currentTab = 0
                            }
                            
                            // Reset drag offset
                            dragOffset = 0
                        }
                    }
            )
            
            // Marketing banner that appears only on the Library tab
            // and only for non-subscribed users who haven't dismissed it
            if currentTab == 0 && showMarketingBanner && !subscriptionManager.isPremium && !hasHiddenBanner {
                MarketingBanner {
                    // Switch to Discover tab when banner is tapped
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        currentTab = 1
                    }
                } onDismiss: {
                    // Hide banner and save preference
                    withAnimation {
                        showMarketingBanner = false
                    }
                    UserDefaults.standard.set(true, forKey: marketingBannerKey)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 10)
                .animation(.easeInOut, value: currentTab)
                .zIndex(1) // Ensure banner appears above tab content
            }
        }
    }
}