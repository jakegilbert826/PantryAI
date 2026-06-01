import Foundation

/// Confidence falls linearly toward zero across one full half-life × 2 window.
/// Good baseline for stable categories (dry goods, frozen, beverages).
final class LinearDecayModel: DecayModel {
    let category: FoodCategory
    let halfLifeDays: Double
    var modelIdentifier: String { "linear" }

    init(category: FoodCategory, halfLifeDays: Double? = nil) {
        self.category = category
        self.halfLifeDays = halfLifeDays ?? DecayDefaults.halfLifeDays(for: category)
    }

    func confidence(
        lastScanConfidence: Double,
        lastScanDate: Date,
        householdSize: Int,
        usageHistory: [ItemQuantityLog]
    ) -> Double {
        let daysElapsed = max(0, Date.now.timeIntervalSince(lastScanDate) / 86_400)
        let totalLife = halfLifeDays * 2 / householdMultiplier(householdSize)
        let raw = lastScanConfidence * (1.0 - daysElapsed / totalLife)
        let bounded = max(0, min(1, raw))
        return applyingUsage(bounded, usageHistory: usageHistory, since: lastScanDate)
    }
}
