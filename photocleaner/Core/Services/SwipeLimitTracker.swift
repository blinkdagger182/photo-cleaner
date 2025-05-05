import Foundation

class SwipeLimitTracker {
    // MARK: - Constants
    private enum Constants {
        static let initialDaysCount = 3
        static let initialDailyLimit = 100
        static let standardDailyLimit = 30
        
        // UserDefaults keys
        static let firstUseDateKey = "SwipeLimitTracker.firstUseDate"
        static let dailySwipeCountKey = "SwipeLimitTracker.dailySwipeCount"
        static let lastSwipeDateKey = "SwipeLimitTracker.lastSwipeDate"
    }
    
    // MARK: - Properties
    private let userDefaults: UserDefaults
    
    // Computed properties
    var swipesUsedToday: Int {
        ensureDailyReset()
        return userDefaults.integer(forKey: Constants.dailySwipeCountKey)
    }
    
    var dailySwipeLimit: Int {
        // Check if we're within the initial period
        if let firstUseDate = userDefaults.object(forKey: Constants.firstUseDateKey) as? Date {
            let daysSinceFirstUse = Calendar.current.dateComponents([.day], from: firstUseDate, to: Date()).day ?? 0
            
            // Higher limit for initial days
            if daysSinceFirstUse < Constants.initialDaysCount {
                return Constants.initialDailyLimit
            }
        } else {
            // First time use - set the first use date
            userDefaults.set(Date(), forKey: Constants.firstUseDateKey)
            return Constants.initialDailyLimit
        }
        
        // Standard limit after initial period
        return Constants.standardDailyLimit
    }
    
    var swipesRemainingToday: Int {
        return dailySwipeLimit - swipesUsedToday
    }
    
    var isLimitReached: Bool {
        return swipesUsedToday >= dailySwipeLimit
    }
    
    // MARK: - Initialization
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        ensureDailyReset()
    }
    
    // MARK: - Public Methods
    func incrementSwipeCount() {
        ensureDailyReset()
        
        let currentCount = userDefaults.integer(forKey: Constants.dailySwipeCountKey)
        userDefaults.set(currentCount + 1, forKey: Constants.dailySwipeCountKey)
        userDefaults.set(Date(), forKey: Constants.lastSwipeDateKey)
    }
    
    func resetSwipeCount() {
        userDefaults.set(0, forKey: Constants.dailySwipeCountKey)
        userDefaults.set(Date(), forKey: Constants.lastSwipeDateKey)
    }
    
    // MARK: - Private Methods
    private func ensureDailyReset() {
        guard let lastSwipeDate = userDefaults.object(forKey: Constants.lastSwipeDateKey) as? Date else {
            // No previous swipe, no need to reset
            return
        }
        
        let calendar = Calendar.current
        if !calendar.isDate(lastSwipeDate, inSameDayAs: Date()) {
            // It's a new day, reset the counter
            resetSwipeCount()
        }
    }
} 