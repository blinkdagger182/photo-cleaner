import Foundation
import SwiftUI

@MainActor
class ImageViewTracker: ObservableObject {
    // MARK: - Singleton
    static let shared = ImageViewTracker()
    
    // MARK: - Published Properties
    @Published var dailyViewCount: Int = 0
    @Published var shouldShowPaywall: Bool = false
    
    // MARK: - Constants
    private let dailyThreshold = 30
    private let dailyViewCountKey = "dailyImageViewCount"
    private let lastResetDateKey = "lastImageViewCountResetDate"
    
    // MARK: - Initialization
    private init() {
        loadSavedData()
        checkAndResetCounterIfNeeded()
    }
    
    // MARK: - Public Methods
    func incrementViewCount() {
        checkAndResetCounterIfNeeded()
        
        dailyViewCount += 1
        UserDefaults.standard.set(dailyViewCount, forKey: dailyViewCountKey)
        
        // Check if we've reached the threshold
        shouldShowPaywall = dailyViewCount >= dailyThreshold
    }
    
    func resetCounter() {
        dailyViewCount = 0
        let today = Date()
        UserDefaults.standard.set(dailyViewCount, forKey: dailyViewCountKey)
        UserDefaults.standard.set(today, forKey: lastResetDateKey)
        shouldShowPaywall = false
    }
    
    // MARK: - Private Methods
    private func loadSavedData() {
        dailyViewCount = UserDefaults.standard.integer(forKey: dailyViewCountKey)
    }
    
    private func checkAndResetCounterIfNeeded() {
        let today = Date()
        
        // If we have a last reset date
        if let lastResetDate = UserDefaults.standard.object(forKey: lastResetDateKey) as? Date {
            // Check if it's a new day (midnight reset)
            if !Calendar.current.isDate(lastResetDate, inSameDayAs: today) {
                resetCounter()
            }
        } else {
            // First time using the app, set the last reset date to today
            UserDefaults.standard.set(today, forKey: lastResetDateKey)
        }
    }
    
    // MARK: - Testing Helpers
    #if DEBUG
    func simulateThresholdReached() {
        dailyViewCount = dailyThreshold
        UserDefaults.standard.set(dailyViewCount, forKey: dailyViewCountKey)
        shouldShowPaywall = true
    }
    #endif
}
