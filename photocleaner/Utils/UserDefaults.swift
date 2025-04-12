import Foundation

extension UserDefaults {
    var hasSeenOnboarding: Bool {
        get { bool(forKey: "hasSeenOnboarding") }
        set { set(newValue, forKey: "hasSeenOnboarding") }
    }

    static let groupContainerURL = UserDefaults(suiteName: "group.com.photogroup.cleaner")
}
