import Foundation

/// Half-life decay: confidence halves every `halfLifeDays`. Steeper early, then
/// plateaus — natural fit for fresh produce, condiments, and snacks where
/// "still in the fridge" doesn't mean "still fresh."
final class ExponentialDecayModel: DecayModel {
    let category: InventoryCategory
    let halfLifeDays: Double
    var modelIdentifier: String { "exponential" }

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
        let adjustedHalfLife = halfLifeDays / householdMultiplier(householdSize)
        let raw = lastScanConfidence * pow(0.5, daysElapsed / adjustedHalfLife)
        let bounded = max(0, min(1, raw))
        return applyingUsage(bounded, usageHistory: usageHistory, since: lastScanDate)
    }
}
