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
    private let lastResetDateKey = "lastSwipeCountResetDate"
    
    // MARK: - Initialization
    private init() {
        loadSavedData()
        checkAndResetForNewDay()
    }
    
    // MARK: - Public Methods
    func incrementSwipeCount() {
        // Check if we need to reset for a new day
        checkAndResetForNewDay()
        
        swipeCount += 1
        saveState()
        
        // Check if we've reached the threshold
        if swipeCount >= swipeThreshold && !showRCPaywall {
            showRCPaywall = true
        }
    }
    
    func resetCounter() {
        swipeCount = 0
        saveState()
        showRCPaywall = false
    }
    
    // MARK: - Private Methods
    private func loadSavedData() {
        swipeCount = UserDefaults.standard.integer(forKey: swipeCountKey)
        // Check if we've already reached the threshold
        showRCPaywall = swipeCount >= swipeThreshold
    }
    
    private func saveState() {
        UserDefaults.standard.set(swipeCount, forKey: swipeCountKey)
        UserDefaults.standard.set(Date(), forKey: lastResetDateKey)
    }
    
    private func checkAndResetForNewDay() {
        // Get the last reset date
        if let lastResetDate = UserDefaults.standard.object(forKey: lastResetDateKey) as? Date {
            // Check if it's a new day
            if !Calendar.current.isDate(lastResetDate, inSameDayAs: Date()) {
                // Reset counter for the new day
                resetCounter()
            }
        } else {
            // No last reset date, save the current one
            UserDefaults.standard.set(Date(), forKey: lastResetDateKey)
        }
    }
    
    // MARK: - Testing Helpers
    #if DEBUG
    func simulateThresholdReached() {
        swipeCount = swipeThreshold
        saveState()
        showRCPaywall = true
    }
    #endif
}
