import SwiftUI
import Foundation

@MainActor
class UpdateService: ObservableObject {
    static let shared = UpdateService()

    private let dismissedVersionKey = "dismissedVersion"
    
    // App Store URL for updates
    let appStoreURL = URL(string: "https://apps.apple.com/app/idXXXXXXXXXX")
    
    // Published properties for update status
    @Published var shouldForceUpdate: Bool = false
    @Published var shouldShowOptionalUpdate: Bool = false
    @Published var updateNotes: String = ""
    
    private init() {}
    
    // Check for updates
    func checkForUpdates() async throws -> (needsForceUpdate: Bool, hasOptionalUpdate: Bool, version: AppVersion?) {
        // Simulate API check for app version
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        
        // Mock app version response
        let version = AppVersion(
            platform: "ios",
            version: "1.1.0",
            is_valid: true,
            is_latest: false,
            notes: "Bug fixes and performance improvements"
        )
        
        let needsForceUpdate = !version.is_valid
        let hasOptionalUpdate = !version.is_latest && version.version != currentVersion
        
        return (needsForceUpdate, hasOptionalUpdate, version)
    }
    
    // Get dismissed version from UserDefaults
    var dismissedVersion: String {
        get {
            UserDefaults.standard.string(forKey: dismissedVersionKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: dismissedVersionKey)
        }
    }
    
    // Dismiss the current version update notification
    func dismissCurrentVersion(_ version: String) {
        dismissedVersion = version
    }
} 