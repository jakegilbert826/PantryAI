import Foundation

protocol DecayModel {
    var category: FoodCategory { get }

    /// Returns a 0.0–1.0 confidence value representing estimated remaining
    /// quantity right now, given the last observation and any logged usage.
    func confidence(
        lastScanConfidence: Double,
        lastScanDate: Date,
        householdSize: Int,
        usageHistory: [ItemQuantityLog]
    ) -> Double

    /// Stable identifier surfaced in the debug overlay and used by `DecayModelFactory`.
    var modelIdentifier: String { get }
}

/// Default half-life lookup. Centralised so models can share the table.
enum DecayDefaults {
    static func halfLifeDays(for category: FoodCategory) -> Double {
        switch category {
        case .freshProduce: return 5
        case .dairy:        return 7
        case .meat:         return 2
        case .fish:         return 1.5
        case .frozenGoods:  return 60
        case .dryGoods:     return 180
        case .condiments:   return 90
        case .beverages:    return 14
        case .snacks:       return 10
        }
    }
}

extension DecayModel {
    /// Subtracts logged manual/cooking usage events since the last scan.
    func applyingUsage(_ base: Double, usageHistory: [ItemQuantityLog], since lastScanDate: Date) -> Double {
        let consumptionSources: Set<LogSource> = [.manual, .usageLog]
        let used = usageHistory
            .filter { consumptionSources.contains($0.source) && $0.recordedAt >= lastScanDate }
            .reduce(0.0) { $0 + ($1.measureValue ?? 0) }
        return max(0, base - used)
    }

    /// Household consumption multiplier: 1 person = 1.0, scales sub-linearly.
    func householdMultiplier(_ size: Int) -> Double {
        let s = Double(max(1, size))
        return 1.0 + log(s) * 0.6
    }
}
