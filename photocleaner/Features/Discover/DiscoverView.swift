import SwiftUI
import Photos
import UIKit
import RevenueCat

struct DiscoverView: View {
    @StateObject private var viewModel: DiscoverViewModel
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    // Add loading state
    @State private var isInitializing = true
    
    init(photoManager: PhotoManager) {
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(photoManager: photoManager))
    }
    
    // Connect toast service when view appears
    private func connectToastService() {
        viewModel.toast = toast
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    contentView
                }
                .overlay(processingOverlay)
                
                // Show initializing overlay until first data load is complete
                if isInitializing {
                    Color.systemBackground
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Loading Discover tab...")
                                    .font(.headline)
                            }
                        )
                }
            }
            .onAppear {
                connectToastService()
                
                // Only load data when view appears for the first time
                if isInitializing {
                    viewModel.loadAlbums()
                    
                    // Mark initialization as complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation {
                            isInitializing = false
                        }
                    }
                }
            }
        }
        .sheet(item: $viewModel.selectedGroup) { group in
            SwipeCardView(group: group, forceRefresh: $viewModel.forceRefresh, isDiscoverTab: true)
                .environmentObject(photoManager)
                .environmentObject(toast)
                .environmentObject(SubscriptionManager.shared)
        }
        .sheet(isPresented: $viewModel.showRCPaywall) {
            // Show RevenueCat Paywall
            PaywallView()
                .environmentObject(SubscriptionManager.shared)
        }
    }
    
    // Main content view
    private var contentView: some View {
        VStack(spacing: 8) {
            // Header
            headerView
            
            // Premium banner for non-premium users
            if !viewModel.showEmptyState && !SubscriptionManager.shared.isPremium {
                DiscoverPromoBanner {
                    // Show paywall when banner is tapped
                    viewModel.showRCPaywall = true
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            
            if !viewModel.showEmptyState {
                // Featured albums
                if !viewModel.featuredAlbums.isEmpty {
                    featuredAlbumsView
                }
                
                // Category sections
                ForEach(Array(viewModel.categorizedAlbums.keys.sorted()), id: \.self) { category in
                    if let albums = viewModel.categorizedAlbums[category], !albums.isEmpty, category != "All" {
                        categoryView(title: category, albums: albums)
                    }
                }
                
                // Load more button
                loadMoreButton
            } else {
                emptyStateView
            }
        }
    }
    
    // Header view with logo and photo count
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Discover")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Advanced clustering button - refresh the clustering
                Button(action: {
                    Task {
                        await viewModel.processEntireLibrary()
                    }
                }) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title2)
                }
                .disabled(viewModel.isClusteringInProgress)
                .padding(.trailing, 8)
            }
            .padding(.horizontal)
            
            // Photo count statistics
            if viewModel.isClusteringInProgress {
                HStack {
                    Text("Processing \(viewModel.totalPhotoCount) photos...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                
                // Clustering progress indicator
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.clusteringProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                    
                    Text("Processing entire photo library... \(Int(viewModel.clusteringProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            
            // Photo count indicator
            if viewModel.totalPhotoCount > 0 {
                HStack {
                    Text("\(viewModel.discoveredPhotoCount) of \(viewModel.totalPhotoCount) photos in albums")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Progress bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .frame(width: 100, height: 6)
                            .foregroundColor(Color(.systemGray5))
                        
                        RoundedRectangle(cornerRadius: 3)
                            .frame(width: max(0, 100 * CGFloat(viewModel.discoveredPhotoCount) / CGFloat(max(1, viewModel.totalPhotoCount))), height: 6)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }
    
    // Featured albums carousel
    private var featuredAlbumsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section title
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Featured Albums")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Sort button
                Button(action: {
                    viewModel.toggleFeaturedSortOrder()
                }) {
                    HStack(spacing: 4) {
                        if viewModel.isSortingFeatured {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.7)
                                .padding(.trailing, 4)
                        }
                        
                        Text(viewModel.featuredSortByMostPhotos ? "Most Photos" : "Most Relevant")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
                .disabled(viewModel.isSortingFeatured)
            }
            .padding(.horizontal)
            
            // Featured albums content
            ZStack {
                if viewModel.isSortingFeatured && viewModel.featuredAlbums.isEmpty {
                    // Show skeleton loader when sorting/loading
                    featuredSkeletonView
                } else {
                    // Regular carousel
                    FallbackFeaturedCarousel(albums: viewModel.featuredAlbums) { album in
                        viewModel.selectAlbum(album)
                    }
                    .frame(height: 300)
                    .padding(.horizontal, 6) // Add additional horizontal padding to prevent clipping
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 2)
        }
    }
    
    // Skeleton loader for featured albums
    private var featuredSkeletonView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        // Album photo placeholder
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: UIScreen.main.bounds.width * 0.8, height: 240)
                            .cornerRadius(8)
                        
                        // Title and count placeholders
                        VStack(alignment: .leading, spacing: 4) {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(width: UIScreen.main.bounds.width * 0.5, height: 18)
                                .cornerRadius(4)
                            
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(width: UIScreen.main.bounds.width * 0.3, height: 14)
                                .cornerRadius(4)
                        }
                        .padding(.horizontal, 5)
                    }
                }
                .padding(.leading)
            }
        }
        .frame(height: 300)
    }
    
    // Category view with album grid
    private func categoryView(title: String, albums: [SmartAlbumGroup]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header with collapsible button
            Button(action: {
                viewModel.toggleCategoryCollapse(title)
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Image(systemName: viewModel.isCategoryCollapsed(title) ? "chevron.right" : "chevron.down")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .animation(.easeInOut, value: viewModel.isCategoryCollapsed(title))
                                .padding(.leading, 2)
                        }
                        
                        // Simplified description for Events category
                        if title == "Events" {
                            Text("Smart clustering based on time and location")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Add sort button only for Events category
                    if title == "Events" {
                        Menu {
                            ForEach(DiscoverViewModel.EventSortOption.allCases) { option in
                                Button(action: {
                                    viewModel.setEventSortOption(option)
                                }) {
                                    HStack {
                                        Text(option.rawValue)
                                        if viewModel.eventsSortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if viewModel.isSortingEvents {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.7)
                                        .padding(.trailing, 4)
                                }
                                
                                Text(viewModel.eventsSortOption.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                        }
                        .disabled(viewModel.isSortingEvents)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(Color(.systemBackground).opacity(0.01)) // Make entire area tappable
            
            // Divider line
            if !viewModel.isCategoryCollapsed(title) {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal)
            }
            
            // Album grid content - only shown if category is not collapsed
            if !viewModel.isCategoryCollapsed(title) {
                ZStack {
                    if title == "Events" && viewModel.isSortingEvents && albums.isEmpty {
                        // Show skeleton grid when sorting/loading
                        eventsSkeletonGrid
                    } else {
                        // Regular album grid
                        FallbackAlbumGrid(albums: albums) { album in
                            viewModel.selectAlbum(album)
                        }
                    }
                }
                .padding(.top, 6) // Add small top padding to separate from divider
            }
        }
        .padding(.vertical, 6) // Add consistent vertical padding
        .animation(.easeInOut(duration: 0.25), value: viewModel.isCategoryCollapsed(title))
    }
    
    // Skeleton grid for events when loading
    private var eventsSkeletonGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 15),
            GridItem(.flexible(), spacing: 15),
        ], spacing: 15) {
            ForEach(0..<4, id: \.self) { _ in
                // Event item skeleton
                VStack(alignment: .leading, spacing: 6) {
                    // Photo placeholder
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: (UIScreen.main.bounds.width - 50) / 2)
                        .cornerRadius(8)
                    
                    // Title placeholder
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: (UIScreen.main.bounds.width - 50) / 3, height: 16)
                        .cornerRadius(4)
                    
                    // Photo count placeholder
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: (UIScreen.main.bounds.width - 50) / 4, height: 12)
                        .cornerRadius(4)
                        .opacity(0.7)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // Empty state view
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Smart Albums Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Generate smart albums to organize your photos automatically")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
            
            Button(action: {
                Task {
                    await viewModel.processEntireLibrary()
                }
            }) {
                Text("Generate Smart Albums")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(Color(UIColor.systemBackground))
                    .cornerRadius(10)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
        }
        .padding(.vertical, 60)
    }
    
    // Load more button
    private var loadMoreButton: some View {
        VStack {
            if viewModel.hasMoreAlbums {
                Button(action: {
                    Task {
                        viewModel.loadMoreAlbums()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 16))
                        
                        Text("Reprocess Photo Library")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .foregroundColor(.white)
                    .background(Color.black)
                    .cornerRadius(22)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .overlay(
                        Group {
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                            }
                        }
                    )
                }
                .disabled(viewModel.isLoadingMore)
                .padding(.vertical, 16)
            } else if !viewModel.categorizedAlbums.isEmpty {
                Text("All photos processed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
            }
            
            // Add some bottom padding to ensure the button is visible
            Color.clear.frame(height: 40)
        }
    }
    
    // Processing overlay
    private var processingOverlay: some View {
        Group {
            if viewModel.isGenerating || viewModel.isBatchProcessing {
                overlayBackground
            } else if viewModel.isClusteringInProgress {
                // Use our beautiful skeleton loader when clustering is in progress
                SkeletonLoaderView(
                    progress: viewModel.clusteringProgress,
                    totalPhotoCount: viewModel.totalPhotoCount,
                    processedAlbumCount: viewModel.processedAlbumCount
                )
                .edgesIgnoringSafeArea(.all)
                .transition(.opacity)
            }
        }
    }
    
    // Overlay background with content
    private var overlayBackground: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            
            // Content container
            overlayContentContainer
        }
    }
    
    // Content container with styling
    private var overlayContentContainer: some View {
        VStack(spacing: 16) {
            if viewModel.isBatchProcessing {
                batchProcessingContent
            } else {
                albumGenerationContent
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }
    
    // Batch processing specific content
    private var batchProcessingContent: some View {
        VStack(spacing: 12) {
            Text("Processing Large Photo Library")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("\(Int(viewModel.batchProcessingProgress * 100))% Complete")
                .foregroundColor(.white)
            
            ProgressView(value: viewModel.batchProcessingProgress)
                .frame(width: 200)
            
            cancelButton
        }
    }
    
    // Album generation content
    private var albumGenerationContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Generating Albums...")
                .font(.headline)
                .foregroundColor(.white)
        }
    }
    
    // Cancel button
    private var cancelButton: some View {
        Button("Cancel") {
            viewModel.cancelBatchProcessing()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.red.opacity(0.8))
        .foregroundColor(.white)
        .cornerRadius(8)
    }
}

#Preview{
    
    SkeletonLoaderView(
        progress: 50, totalPhotoCount: 33000, processedAlbumCount: 16)
}



#Preview {
    OnboardingView()
        .environmentObject(PhotoManager.preview)
        .environmentObject(ToastService.preview)
}
