import Foundation

extension UserDefaults {
    var hasSeenOnboarding: Bool {
        get { bool(forKey: "hasSeenOnboarding") }
        set { set(newValue, forKey: "hasSeenOnboarding") }
    }
}
