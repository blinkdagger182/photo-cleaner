import Foundation
import SwiftUI

@MainActor
class DiscoverSwipeTracker: ObservableObject {
    // MARK: - Singleton
    static let shared = DiscoverSwipeTracker()
    
    // MARK: - Published Properties
    @Published var swipeCount: Int = 0
    @Published var showRCPaywall: Bool = false
    
    // MARK: - Constants
    private let swipeThreshold = 5
    private let swipeCountKey = "discoverSwipeCount"
    
    // MARK: - Initialization
    private init() {
        loadSavedData()
    }
    
    // MARK: - Public Methods
    func incrementSwipeCount() {
        swipeCount += 1
        UserDefaults.standard.set(swipeCount, forKey: swipeCountKey)
        
        // Check if we've reached the threshold
        if swipeCount >= swipeThreshold && !showRCPaywall {
            showRCPaywall = true
        }
    }
    
    func resetCounter() {
        swipeCount = 0
        UserDefaults.standard.set(swipeCount, forKey: swipeCountKey)
        showRCPaywall = false
    }
    
    // MARK: - Private Methods
    private func loadSavedData() {
        swipeCount = UserDefaults.standard.integer(forKey: swipeCountKey)
        // Check if we've already reached the threshold
        showRCPaywall = swipeCount >= swipeThreshold
    }
    
    // MARK: - Testing Helpers
    #if DEBUG
    func simulateThresholdReached() {
        swipeCount = swipeThreshold
        UserDefaults.standard.set(swipeCount, forKey: swipeCountKey)
        showRCPaywall = true
    }
    #endif
}
