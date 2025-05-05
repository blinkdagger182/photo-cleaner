import SwiftUI
import RevenueCat

struct MainTabView: View {
    // Environment objects
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var toast: ToastService
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    
    // Track the current tab index (0 = Library, 1 = Discover)
    @State private var currentTab = 0
    @State private var showMarketingBanner = true
    
    // Track if Discover tab has been loaded already
    @State private var discoverTabInitialized = false
    
    // Paywall state
    @State private var showPaywall = false
    @State private var currentOffering: Offering?
    @State private var isLoadingOffering = false
    
    // UserDefaults key for banner visibility
    private let marketingBannerKey = "hasHiddenMarketingBanner"
    @State private var showPremiumAlertBanner = false

    private let premiumAlertDismissKey = "lastDismissedPremiumAlert"
    
    // For swipe gesture navigation
    @State private var dragOffset: CGFloat = 0
    @State private var previousDragOffset: CGFloat = 0
    
    // Tab titles
    private let tabs = ["Library", "Discover"]

    // State for header visibility
    @State private var headerVisible = true
    @State private var scrollOffset: CGFloat = 0
    @State private var lastScrollOffset: CGFloat = 0
    @State private var lastHeaderToggleTime = Date()
    @State private var scrollDirection: ScrollDirection = .none

    // For matched geometry effect
    @Namespace private var namespace

    // Scroll direction enum
    private enum ScrollDirection {
        case up, down, none
    }

    var body: some View {
        // Check if user has previously dismissed the banner
        let hasHiddenBanner = UserDefaults.standard.bool(forKey: marketingBannerKey)
        
        VStack(spacing: 0) {
            // CLN Logo at the top
            HStack (spacing: -4) {
                Spacer()
                
                // Display CLN logo or CLN+ logo based on the selected tab
                Image("CLN")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 50)
                    .transition(.opacity)
                if currentTab == 1 {
                    Image("+")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 35)
                        .transition(.opacity)
                }
                
                Spacer()
            }
            .padding(.vertical, 10)
            .animation(.easeInOut, value: currentTab)
            .offset(y: headerVisible ? 0 : -70) // Hide above screen when not visible
            .opacity(headerVisible ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: headerVisible)
            
            // Tab indicator
            HStack(spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            currentTab = index
                            
                            // If switching to Discover tab, mark it as initialized
                            if index == 1 {
                                discoverTabInitialized = true
                            }
                        }
                    }) {
                        VStack(spacing: 8) {
                            Text(tabs[index])
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(currentTab == index ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal)
            .offset(y: headerVisible ? 0 : -60) // Move up when header is hidden
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: headerVisible)
            
            // Indicator line with matched geometry effect
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 2)
                
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: UIScreen.main.bounds.width / 2, height: 2)
                    .offset(x: currentTab == 0 ? 0 : UIScreen.main.bounds.width / 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentTab)
            }
            .offset(y: headerVisible ? 0 : -60) // Move up when header is hidden
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: headerVisible)
            
            // Main content with swipe gesture
            let screenWidth = UIScreen.main.bounds.width
            
            ZStack {
                // Library view (at index 0)
                PhotoGroupView(photoManager: photoManager, onScroll: { delta in
                    // When scrolling down (delta < 0), hide the marketing banner
                    if delta < -10 && showMarketingBanner && !subscriptionManager.isPremium && !hasHiddenBanner { 
                        // Hide banner with animation
                        withAnimation(.easeOut(duration: 0.3)) {
                            showMarketingBanner = false
                        }
                        // Save preference
                        UserDefaults.standard.set(true, forKey: marketingBannerKey)
                    }
                    
                    // Track scroll direction with debounce
                    let now = Date()
                    let timeSinceLastToggle = now.timeIntervalSince(lastHeaderToggleTime)
                    
                    // Only update scroll direction if we've moved significantly
                    if abs(delta) > 15 {
                        // Set scroll direction
                        let newDirection: ScrollDirection = delta < 0 ? .down : .up
                        
                        // Check if direction changed and apply debounce
                        if newDirection != scrollDirection && timeSinceLastToggle > 0.3 {
                            scrollDirection = newDirection
                            
                            // Update header visibility based on sustained direction
                            withAnimation(.easeOut(duration: 0.3)) {
                                // Only hide header when scrolling down, show when scrolling up
                                if scrollDirection == .down && headerVisible {
                                    headerVisible = false
                                    lastHeaderToggleTime = now
                                } else if scrollDirection == .up && !headerVisible {
                                    headerVisible = true
                                    lastHeaderToggleTime = now
                                }
                            }
                        }
                    }
                })
                    .environmentObject(photoManager)
                    .environmentObject(toast)
                    .offset(x: currentTab == 0 ? dragOffset : -screenWidth + dragOffset)
                    .padding(.top, headerVisible ? 0 : -60) // Expand content when header is hidden
                
                // Discover view (at index 1) - only initialize when selected
                if currentTab == 1 || discoverTabInitialized {
                    DiscoverView(photoManager: photoManager, onScroll: { delta in
                        // When scrolling down (delta < 0), hide the marketing banner
                        if delta < -10 && showMarketingBanner && !subscriptionManager.isPremium && !hasHiddenBanner { 
                            // Hide banner with animation
                            withAnimation(.easeOut(duration: 0.3)) {
                                showMarketingBanner = false
                            }
                            // Save preference
                            UserDefaults.standard.set(true, forKey: marketingBannerKey)
                        }
                        
                        // Track scroll direction with debounce
                        let now = Date()
                        let timeSinceLastToggle = now.timeIntervalSince(lastHeaderToggleTime)
                        
                        // Only update scroll direction if we've moved significantly
                        if abs(delta) > 15 {
                            // Set scroll direction
                            let newDirection: ScrollDirection = delta < 0 ? .down : .up
                            
                            // Check if direction changed and apply debounce
                            if newDirection != scrollDirection && timeSinceLastToggle > 0.3 {
                                scrollDirection = newDirection
                                
                                // Update header visibility based on sustained direction
                                withAnimation(.easeOut(duration: 0.3)) {
                                    // Only hide header when scrolling down, show when scrolling up
                                    if scrollDirection == .down && headerVisible {
                                        headerVisible = false
                                        lastHeaderToggleTime = now
                                    } else if scrollDirection == .up && !headerVisible {
                                        headerVisible = true
                                        lastHeaderToggleTime = now
                                    }
                                }
                            }
                        }
                    })
                        .environmentObject(photoManager)
                        .environmentObject(toast)
                        .environmentObject(subscriptionManager)
                        .offset(x: currentTab == 0 ? screenWidth + dragOffset : dragOffset)
                        .padding(.top, headerVisible ? 0 : -60) // Expand content when header is hidden
                        .onAppear {
                            // Mark Discover tab as initialized when it appears
                            if !discoverTabInitialized {
                                discoverTabInitialized = true
                            }
                        }
                }
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
                                // Mark Discover tab as initialized
                                discoverTabInitialized = true
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
            if currentTab == 0 && showMarketingBanner && !subscriptionManager.isPremium && !hasHiddenBanner && !showPremiumAlertBanner{ 
                MarketingBanner {
                    // Switch to Discover tab when banner is tapped
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        currentTab = 1
                        // Mark Discover tab as initialized when switching to it
                        discoverTabInitialized = true
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
        .onAppear {
            showPremiumAlertBanner = shouldShowPremiumAlert()
        }
        .sheet(isPresented: $showPaywall) {
            // Reset offering if the sheet is dismissed
            if currentOffering == nil {
                isLoadingOffering = false
            }
        } content: {
            Group {
                if let offering = currentOffering {
                    // Show paywall with the loaded offering
                    PaywallView()
                        .environmentObject(subscriptionManager)
                } else {
                    // Show loading view while fetching offering
                    VStack {
                        ProgressView("Loading subscription options...")
                            .padding()
                        
                        Button("Cancel") {
                            showPaywall = false
                        }
                        .padding()
                    }
                    .onAppear {
                        loadOffering()
                    }
                }
            }
        }

        if showPremiumAlertBanner && !subscriptionManager.isPremium {
            Color.black.opacity(0.6)
            .ignoresSafeArea()
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: showPremiumAlertBanner)
            PremiumAlertBanner(
                onTap: {
                    // onTap - Go to discover tab
                    currentTab = 1
                    // Mark Discover tab as initialized
                    discoverTabInitialized = true
                },
                onDismiss: {
                    // Dismiss the banner
                    withAnimation {
                        showPremiumAlertBanner = false
                    }
                    UserDefaults.standard.set(Date(), forKey: premiumAlertDismissKey)
                },
                showPaywall: $showPaywall
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(2)
        }
    }
    
    private func loadOffering() {
        guard !isLoadingOffering else { return }
        
        isLoadingOffering = true
        
        Task {
            do {
                let offerings = try await Purchases.shared.offerings()
                currentOffering = offerings.current
            } catch {
                // Handle error
                print("Failed to load offerings: \(error)")
                
                // Dismiss the sheet if offerings can't be loaded
                showPaywall = false
            }
            
            isLoadingOffering = false
        }
    }
    
    func shouldShowPremiumAlert() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: premiumAlertDismissKey) as? Date else {
            return true
        }
//        return Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 4 > 3
        return true
    }
}
