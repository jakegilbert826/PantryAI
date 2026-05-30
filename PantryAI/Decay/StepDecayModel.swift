import Foundation

/// "Present until expired, then gone." Used for items where partial-consumption
/// estimation is meaningless — raw meat, fresh fish: it's either there or it
/// got cooked/discarded.
final class StepDecayModel: DecayModel {
    let category: InventoryCategory
    let halfLifeDays: Double
    var modelIdentifier: String { "step" }

    init(category: InventoryCategory, halfLifeDays: Double? = nil) {
        self.category = category
        self.halfLifeDays = halfLifeDays ?? DecayDefaults.halfLifeDays(for: category)
    }

    func confidence(
        lastScanConfidence: Double,
        lastScanDate: Date,
        householdSize: Int,
        usageHistory: [UsageEvent]
    ) -> Double {
        let daysElapsed = max(0, Date.now.timeIntervalSince(lastScanDate) / 86_400)
        let depletion = halfLifeDays * 2 / householdMultiplier(householdSize)
        let base = daysElapsed < depletion ? lastScanConfidence : 0
        return applyingUsage(base, usageHistory: usageHistory, since: lastScanDate)
    }
}
