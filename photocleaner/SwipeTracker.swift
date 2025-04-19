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
    @Published var shouldShowPaywall = false
    
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
            
            // Reset the paywall flag as well
            shouldShowPaywall = false
        }
    }
    
    // Increment the swipe count by 1
    func incrementSwipeCount() {
        // First check if we need to reset based on date
        checkAndResetIfNeeded()
        
        // Increment the count
        swipeCount += 1
        saveState()
        
        // Check if we've reached the threshold
        if swipeCount >= swipeThreshold {
            shouldShowPaywall = true
        }
    }
    
    // Reset the paywall flag (e.g. after dismissing it)
    func resetPaywallFlag() {
        shouldShowPaywall = false
    }
    
    // Reset counter (usually after a successful purchase)
    func resetSwipeCount() {
        swipeCount = 0
        saveState()
        shouldShowPaywall = false
    }
    
    // For debugging/development - get the number of swipes remaining before paywall
    func swipesRemainingUntilPaywall() -> Int {
        return max(0, swipeThreshold - swipeCount)
    }
} 