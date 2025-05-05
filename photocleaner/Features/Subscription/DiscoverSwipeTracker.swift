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
    
    // Computed property to check if limit is reached
    var isLimitReached: Bool {
        return swipeCount >= threshold
    }
    
    // MARK: - Constants
    private let initialDaysCount = 3
    private let initialDailyLimit = 100
    private let standardDailyLimit = 30
    
    // UserDefaults keys
    private let swipeCountKey = "discoverSwipeCount"
    private let lastResetDateKey = "lastSwipeCountResetDate"
    private let firstUseDateKey = "DiscoverSwipeTracker.firstUseDate"
    
    // Publicly expose the threshold
    var threshold: Int {
        // Check if we're within the initial period
        if let firstUseDate = UserDefaults.standard.object(forKey: firstUseDateKey) as? Date {
            let daysSinceFirstUse = Calendar.current.dateComponents([.day], from: firstUseDate, to: Date()).day ?? 0
            
            // Higher limit for initial days
            if daysSinceFirstUse < initialDaysCount {
                return initialDailyLimit
            }
        } else {
            // First time use - set the first use date
            UserDefaults.standard.set(Date(), forKey: firstUseDateKey)
            return initialDailyLimit
        }
        
        // Standard limit after initial period
        return standardDailyLimit
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
        if swipeCount >= threshold && !SubscriptionManager.shared.isPremium {
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
        showRCPaywall = swipeCount >= threshold
    }
    
    private func saveState() {
        UserDefaults.standard.set(swipeCount, forKey: swipeCountKey)
        UserDefaults.standard.set(Date(), forKey: lastResetDateKey)
    }
    
    private func checkAndResetForNewDay() {
        guard let lastResetDate = UserDefaults.standard.object(forKey: lastResetDateKey) as? Date else {
            // No previous reset, no need to check
            return
        }
        
        let calendar = Calendar.current
        if !calendar.isDate(lastResetDate, inSameDayAs: Date()) {
            // It's a new day, reset the counter
            swipeCount = 0
            saveState()
            showRCPaywall = false
        }
    }
    
    // MARK: - Testing Helpers
    #if DEBUG
    func simulateThresholdReached() {
        swipeCount = threshold
        saveState()
        showRCPaywall = true
    }
    #endif
}
