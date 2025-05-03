import SwiftUI

/// A modern skeleton loader for displaying loading states with animated shimmer effect
/// that matches the visual style of the app's discover screen.
struct SkeletonLoaderView: View {
    // MARK: - Properties
    
    var progress: Double
    var totalPhotoCount: Int
    var processedAlbumCount: Int
    
    @State private var isShimmering = false
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color - match system background
                Color(UIColor.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 8) {
                    // Album statistics
                    albumStatisticsView(geometry: geometry)
                    
                    // Featured Albums section
                    featuredAlbumsSection(geometry: geometry)
                    
                    // Events section
                    eventsSection(geometry: geometry)
                    
                    // Load more button
                    loadMoreButtonPlaceholder(geometry: geometry)
                    
                    Spacer(minLength: 30)
                    
                    // Progress section
                    progressSection(geometry: geometry)
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Subviews
    
    private func albumStatisticsView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            HStack {
                // Title
                Text("Discover")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Icon
                Image(systemName: "square.stack.3d.up")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal)
            
            // Statistics text
            HStack {
                Text("Processing \(totalPhotoCount) photos...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            
            // Clustering progress indicator
            VStack(spacing: 4) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal)
                
                Text("Processing entire photo library... \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .padding(.top, 8)
            
            // Photo count indicator
            HStack {
                Text("\(Int(Double(totalPhotoCount) * 0.75)) of \(totalPhotoCount) photos in albums")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Progress bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .frame(width: 100, height: 6)
                        .foregroundColor(Color(UIColor.systemGray5))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .frame(width: 75, height: 6)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }
    
    private func featuredAlbumsSection(geometry: GeometryProxy) -> some View {
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
                HStack(spacing: 4) {
                    Text("Most Photos")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            
            // Albums scroll view
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(0..<2) { _ in
                        featuredAlbumItem(width: geometry.size.width * 0.8, height: 300)
                    }
                    .padding(.leading)
                }
            }
            .frame(height: 300)
            .padding(.top, 10)
            .padding(.bottom, 2)
        }
    }
    
    private func eventsSection(geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header with collapsible button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Events")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Image(systemName: "chevron.down")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)
                    }
                    
                    // Description
                    Text("Smart clustering based on time and location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Sort button
                HStack(spacing: 4) {
                    Text("Newest First")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground).opacity(0.01)) // Make entire area tappable
            
            // Divider line
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal)
            
            // Events grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 15),
                GridItem(.flexible(), spacing: 15),
            ], spacing: 15) {
                ForEach(0..<4) { _ in
                    eventAlbumItem(width: (geometry.size.width - 50) / 2)
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
        .padding(.vertical, 6)
    }
    
    private func loadMoreButtonPlaceholder(geometry: GeometryProxy) -> some View {
        VStack {
            shimmerPlaceholder(width: 200, height: 44)
                .cornerRadius(22)
                .padding(.vertical, 16)
            
            // Add some bottom padding
            Color.clear.frame(height: 40)
        }
    }
    
    private func featuredAlbumItem(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Album photo
            shimmerPlaceholder(width: width, height: height * 0.8)
                .cornerRadius(8)
            
            // Album title and photo count
            VStack(alignment: .leading, spacing: 2) {
                // Title placeholder
                shimmerPlaceholder(width: width * 0.6, height: 18)
                    .cornerRadius(4)
                
                // Photo count placeholder
                shimmerPlaceholder(width: width * 0.3, height: 14)
                    .cornerRadius(4)
                    .opacity(0.7)
            }
            .padding(.horizontal, 5)
            .padding(.top, 5)
        }
        .frame(width: width)
    }
    
    private func eventAlbumItem(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Album photo
            shimmerPlaceholder(width: width, height: width)
                .cornerRadius(8)
            
            // Album title and photo count
            VStack(alignment: .leading, spacing: 3) {
                // Title placeholder
                shimmerPlaceholder(width: width * 0.8, height: 16)
                    .cornerRadius(4)
                
                // Photo count placeholder
                shimmerPlaceholder(width: width * 0.4, height: 12)
                    .cornerRadius(4)
                    .opacity(0.7)
            }
            .padding(.horizontal, 5)
            .padding(.top, 3)
        }
    }
    
    private func shimmerPlaceholder(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color(UIColor.systemGray5))
            .frame(width: width, height: height)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(
                                colors: [
                                    Color(UIColor.systemGray5),
                                    Color(UIColor.systemBackground).opacity(0.6),
                                    Color(UIColor.systemGray5)
                                ]
                            ),
                            startPoint: isShimmering ? .topLeading : .bottomTrailing,
                            endPoint: isShimmering ? .bottomTrailing : .topLeading
                        )
                    )
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    isShimmering.toggle()
                }
            }
    }
    
    private func progressSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 15) {
            // Progress text
            Text("Processing \(totalPhotoCount) photos")
                .font(.headline)
            
            // Progress bar
            ProgressBar(progress: progress, width: geometry.size.width * 0.8)
            
            // Percentage and album count
            HStack {
                Text("\(Int(progress * 100))%")
                    .font(.headline)
                
                Spacer()
                
                if processedAlbumCount > 0 {
                    Text("\(processedAlbumCount) albums created")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: geometry.size.width * 0.8)
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.9))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10)
    }
    
    // MARK: - Components
    
    /// Customized progress bar with gradient
    private struct ProgressBar: View {
        var progress: Double
        var width: CGFloat
        
        var body: some View {
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.systemGray5))
                    .frame(height: 12)
                
                // Progress indicator
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, CGFloat(progress) * width), height: 12)
                    .animation(.linear(duration: 0.5), value: progress)
            }
            .frame(width: width)
        }
    }
}

// MARK: - Preview

struct SkeletonLoaderView_Previews: PreviewProvider {
    static var previews: some View {
        SkeletonLoaderView(
            progress: 0.65,
            totalPhotoCount: 32495,
            processedAlbumCount: 12
        )
    }
} 

