import SwiftUI
import UIKit
import Photos

/// A memory-efficient UIKit-based carousel for featured albums
struct OptimizedFeaturedCarousel: UIViewRepresentable {
    // Albums to display
    var albums: [SmartAlbumGroup]
    
    // Photo cache for optimized loading
    var photoCache: OptimizedPhotoCache = OptimizedPhotoCache.shared
    
    // Callback when an album is selected
    var onAlbumSelected: (SmartAlbumGroup) -> Void
    
    // Create coordinator to handle collection view data source and delegate
    func makeCoordinator() -> Coordinator {
        Coordinator(albums: albums, photoCache: photoCache, onAlbumSelected: onAlbumSelected)
    }
    
    // Create the UIKit view
    func makeUIView(context: Context) -> UICollectionView {
        // Create a compositional layout for the carousel
        let layout = createCarouselLayout()
        
        // Create the collection view
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delegate = context.coordinator
        collectionView.dataSource = context.coordinator
        
        // Register cell
        collectionView.register(OptimizedFeaturedAlbumCell.self, forCellWithReuseIdentifier: "OptimizedFeaturedAlbumCell")
        
        // Enable prefetching
        collectionView.prefetchDataSource = context.coordinator
        
        return collectionView
    }
    
    // Update the UIKit view when SwiftUI state changes
    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.albums = albums
        collectionView.reloadData()
    }
    
    // Create a compositional layout for the carousel
    private func createCarouselLayout() -> UICollectionViewLayout {
        // Item
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.8),
            heightDimension: .fractionalHeight(1.0)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        
        // Group
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.8),
            heightDimension: .fractionalHeight(1.0)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        
        // Section
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPaging
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        
        return UICollectionViewCompositionalLayout(section: section)
    }
    
    // Coordinator class to handle collection view data source and delegate
    class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
        var albums: [SmartAlbumGroup]
        var photoCache: OptimizedPhotoCache
        var onAlbumSelected: (SmartAlbumGroup) -> Void
        
        // Track visible assets for caching
        private var visibleAssets: [PHAsset] = []
        
        init(albums: [SmartAlbumGroup], photoCache: OptimizedPhotoCache, onAlbumSelected: @escaping (SmartAlbumGroup) -> Void) {
            self.albums = albums
            self.photoCache = photoCache
            self.onAlbumSelected = onAlbumSelected
            super.init()
        }
        
        // MARK: - UICollectionViewDataSource
        
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            return albums.count
        }
        
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "OptimizedFeaturedAlbumCell", for: indexPath) as! OptimizedFeaturedAlbumCell
            
            if indexPath.item < albums.count {
                let album = albums[indexPath.item]
                cell.configure(with: album, photoCache: photoCache)
            }
            
            return cell
        }
        
        // MARK: - UICollectionViewDelegate
        
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            if indexPath.item < albums.count {
                let album = albums[indexPath.item]
                onAlbumSelected(album)
            }
        }
        
        // MARK: - UICollectionViewDataSourcePrefetching
        
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            // Prepare cache for upcoming cells
            let upcomingAlbums = indexPaths.compactMap { indexPath -> SmartAlbumGroup? in
                guard indexPath.item < albums.count else { return nil }
                return albums[indexPath.item]
            }
            
            // Get first asset from each album for prefetching
            let assetsToCache = upcomingAlbums.compactMap { album -> PHAsset? in
                let assets = album.fetchAssets()
                return assets.first
            }
            
            // Start caching these assets
            let targetSize = CGSize(width: 300, height: 200)
            photoCache.prefetchThumbnails(for: assetsToCache, size: targetSize)
        }
        
        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            // Cancel prefetching for items that won't be displayed
            let cancelledAlbums = indexPaths.compactMap { indexPath -> SmartAlbumGroup? in
                guard indexPath.item < albums.count else { return nil }
                return albums[indexPath.item]
            }
            
            // Get assets to stop caching
            let assetsToStopCaching = cancelledAlbums.compactMap { album -> PHAsset? in
                let assets = album.fetchAssets()
                return assets.first
            }
            
            // Stop caching these assets
            let targetSize = CGSize(width: 300, height: 200)
            photoCache.stopPrefetchingThumbnails(for: assetsToStopCaching, size: targetSize)
        }
        
        // MARK: - Scroll View Delegate
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateVisibleAssets(in: scrollView as! UICollectionView)
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                updateVisibleAssets(in: scrollView as! UICollectionView)
            }
        }
        
        // Update which assets are visible for caching
        private func updateVisibleAssets(in collectionView: UICollectionView) {
            // Get visible cells
            let visibleCells = collectionView.visibleCells.compactMap { $0 as? OptimizedFeaturedAlbumCell }
            
            // Get assets from visible cells
            let currentVisibleAssets = visibleCells.compactMap { cell -> PHAsset? in
                return cell.coverAsset
            }
            
            // Stop caching assets that are no longer visible
            let assetsToStopCaching = visibleAssets.filter { asset in
                !currentVisibleAssets.contains(where: { $0.localIdentifier == asset.localIdentifier })
            }
            
            if !assetsToStopCaching.isEmpty {
                let targetSize = CGSize(width: 150, height: 150)
                photoCache.stopPrefetchingThumbnails(for: assetsToStopCaching, size: targetSize)
            }
            
            // Update visible assets
            visibleAssets = currentVisibleAssets
        }
    }
}

/// Cell for featured albums with optimized image loading
class OptimizedFeaturedAlbumCell: UICollectionViewCell {
    // UI elements
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let gradientLayer = CAGradientLayer()
    
    // Track the asset being displayed for caching
    var coverAsset: PHAsset?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Reset UI
        imageView.image = nil
        titleLabel.text = nil
        countLabel.text = nil
        coverAsset = nil
    }
    
    private func setupUI() {
        // Cell appearance
        contentView.layer.cornerRadius = 16
        contentView.clipsToBounds = true
        contentView.backgroundColor = UIColor.systemGray6
        
        // Image view
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        // Gradient overlay
        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.7).cgColor
        ]
        gradientLayer.locations = [0.5, 1.0]
        contentView.layer.addSublayer(gradientLayer)
        
        // Title label
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Count label
        countLabel.textColor = .white
        countLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        contentView.addSubview(countLabel)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Layout labels
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -4),
            
            countLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            countLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
        
        // Add shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.2
        layer.masksToBounds = false
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
    }
    
    func configure(with album: SmartAlbumGroup, photoCache: OptimizedPhotoCache? = nil, thumbnailSize: CGSize? = nil) {
        // Set title and count
        titleLabel.text = album.title
        
        let assets = album.fetchAssets()
        countLabel.text = "\(assets.count) photos"
        
        // Load cover image with memory-efficient approach
        if let firstAsset = assets.first {
            coverAsset = firstAsset
            
            // Use very small image size to prevent CoreAnimation errors
            let targetSize = thumbnailSize ?? CGSize(width: 150, height: 150)
            let cache = photoCache ?? OptimizedPhotoCache.shared
            
            // Load thumbnail with optimized cache
            cache.loadThumbnail(for: firstAsset, targetSize: targetSize) { [weak self] image in
                guard let self = self else { return }
                
                // Only update if this cell hasn't been reused
                if self.coverAsset?.localIdentifier == firstAsset.localIdentifier {
                    DispatchQueue.main.async {
                        self.imageView.image = image
                    }
                }
            }
        }
    }
}
