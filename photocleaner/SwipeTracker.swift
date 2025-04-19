import Foundation
import SwiftUI

class SwipeTracker: ObservableObject {
    static let shared = SwipeTracker()
    
    // Constants
    private let swipeCountKey = "SwipeCount"
    private let lastResetDateKey = "LastResetDate"
    private let swipeThreshold = 30
    
    // Published properties
    @Published var swipeCount: Int = 0
    
    // Check if user has reached the threshold
    var hasReachedLimit: Bool {
        return swipeCount >= swipeThreshold
    }
    
    private init() {
        // Load saved state and check for reset
        loadState()
        checkAndResetIfNeeded()
    }
    
    // Load the current state from UserDefaults
    private func loadState() {
        swipeCount = UserDefaults.standard.integer(forKey: swipeCountKey)
    }
    
    // Save the current state to UserDefaults
    private func saveState() {
        UserDefaults.standard.set(swipeCount, forKey: swipeCountKey)
        
        // Save the current date as the last reset date if it doesn't exist
        if UserDefaults.standard.object(forKey: lastResetDateKey) == nil {
            UserDefaults.standard.set(Date(), forKey: lastResetDateKey)
        }
    }
    
    // Check if we need to reset the counter based on date
    func checkAndResetIfNeeded() {
        guard let lastResetDate = UserDefaults.standard.object(forKey: lastResetDateKey) as? Date else {
            // If no reset date exists, set today as the reset date
            UserDefaults.standard.set(Date(), forKey: lastResetDateKey)
            return
        }
        
        // Check if the last reset was on a different day
        if !Calendar.current.isDate(lastResetDate, inSameDayAs: Date()) {
            // Reset swipe count to 0
            swipeCount = 0
            UserDefaults.standard.set(swipeCount, forKey: swipeCountKey)
            
            // Update the last reset date to today
            UserDefaults.standard.set(Date(), forKey: lastResetDateKey)
        }
    }
    
    // Increment the swipe count by 1
    func incrementSwipeCount() {
        // First check if we need to reset based on date
        checkAndResetIfNeeded()
        
        // Increment the count
        swipeCount += 1
        saveState()
        
        // Note: We no longer need to set a flag to show the paywall
        // RevenueCat will handle that via the presentPaywallIfNeeded modifier
    }
    
    // Reset counter (usually after a successful purchase)
    func resetSwipeCount() {
        swipeCount = 0
        saveState()
    }
    
    // For debugging/development - get the number of swipes remaining before paywall
    func swipesRemainingUntilPaywall() -> Int {
        return max(0, swipeThreshold - swipeCount)
    }
} 