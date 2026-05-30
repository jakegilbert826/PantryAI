import Foundation

/// Tiny wrapper around UserDefaults for prefs that influence the decay model.
/// Kept as a class with a shared instance so the decay code can read it
/// without dependency-injecting it everywhere.
final class UserPreferences {
    static let shared = UserPreferences()

    private let defaults = UserDefaults.standard

    var householdSize: Int {
        get { max(1, defaults.integer(forKey: AppConfig.Keys.householdSize).nonZeroOr(2)) }
        set { defaults.set(newValue, forKey: AppConfig.Keys.householdSize) }
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
