import Foundation
import SwiftUI
import Combine

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
    
    // Publicly expose the threshold
    var threshold: Int {
        return swipeThreshold
    }
    
    // MARK: - Initialization
    private init() {
        loadSavedData()
        checkAndResetForNewDay()
    }
    
    // MARK: - Public Methods
    func incrementSwipeCount() -> Bool {
        // Check if we need to reset for a new day
        checkAndResetForNewDay()
        
        // Check if we're about to exceed the threshold
        if swipeCount >= swipeThreshold && !SubscriptionManager.shared.isPremium {
            // We should show the paywall and undo the swipe
            showRCPaywall = true
            return true
        }
        
        // If we're under the threshold, increment the counter normally
        swipeCount += 1
        saveState()
        
        return false
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
