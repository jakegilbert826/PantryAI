import Foundation

/// "Present until expired, then gone." Used where partial-consumption estimation
/// is meaningless — raw meat and fresh fish are either there or they aren't.
final class StepDecayModel: DecayModel {
    let category: FoodCategory
    let halfLifeDays: Double
    var modelIdentifier: String { "step" }

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
        let depletion = halfLifeDays * 2 / householdMultiplier(householdSize)
        let base = daysElapsed < depletion ? lastScanConfidence : 0
        return applyingUsage(base, usageHistory: usageHistory, since: lastScanDate)
    }
}
