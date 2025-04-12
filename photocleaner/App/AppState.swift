import SwiftUI
import Combine

class AppState: ObservableObject {
    // Published properties for app-wide state
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false
    
    // Update related flags
    @Published var forceUpdateRequired = false
    @Published var optionalUpdateAvailable = false
    
    // Singleton instance
    static let shared = AppState()
    
    private init() {}
    
    // Method to complete onboarding
    func completeOnboarding() {
        hasSeenOnboarding = true
    }
} 