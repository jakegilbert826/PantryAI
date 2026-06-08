import Foundation

/// Singleton household configuration (v3 §6.4). Stored as Codable JSON in
/// UserDefaults — it's tiny and not relational. Replaces the ad-hoc
/// `UserPreferences` wrapper going forward; a remote mirror lands once auth
/// exists. The personalisation that reads this (cold-start consumption priors)
/// is phase 5, so it's reserved now and not yet wired into the decay reads.
struct UserProfile: Codable, Equatable {
    var householdAdults: Int
    var householdChildren: Int
    var cuisines: [String]
    var dietary: [String]
    var dislikedCanonicalNames: [String]

    static let `default` = UserProfile(
        householdAdults: 2,
        householdChildren: 0,
        cuisines: [],
        dietary: [],
        dislikedCanonicalNames: []
    )

    /// Total mouths to feed, floored at 1. Used by the household consumption factor.
    var householdSize: Int { max(1, householdAdults + householdChildren) }
}

extension UserProfile {
    private static let storeKey = "UserProfile.v1"

    /// Current profile (loads the stored JSON, falling back to the default).
    static var current: UserProfile {
        get {
            guard let data = UserDefaults.standard.data(forKey: storeKey),
                  let decoded = try? JSONDecoder().decode(UserProfile.self, from: data)
            else { return .default }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
