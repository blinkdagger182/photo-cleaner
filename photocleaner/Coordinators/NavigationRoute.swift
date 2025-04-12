import Foundation

/// Enum representing all possible navigation routes in the app
enum NavigationRoute: Equatable {
    // Main app flow routes
    case onboarding
    case splash
    case main
    
    // Photo screen routes
    case photoGroup
    case swipeCard(photoGroupId: String)
    
    // Modal routes
    case deletePreview(photos: [DeletePreviewEntry])
    case optionalUpdate(version: AppVersion)
    
    // Static comparison for Equatable conformance
    static func == (lhs: NavigationRoute, rhs: NavigationRoute) -> Bool {
        switch (lhs, rhs) {
        case (.onboarding, .onboarding),
             (.splash, .splash),
             (.main, .main),
             (.photoGroup, .photoGroup):
            return true
        case (.swipeCard(let lhsId), .swipeCard(let rhsId)):
            return lhsId == rhsId
        case (.deletePreview(let lhsPhotos), .deletePreview(let rhsPhotos)):
            return lhsPhotos.count == rhsPhotos.count
        case (.optionalUpdate(let lhsVersion), .optionalUpdate(let rhsVersion)):
            return lhsVersion == rhsVersion
        default:
            return false
        }
    }
} 