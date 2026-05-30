import Foundation

/// Polymorphic surface for decay estimation. Designed for heavy iteration —
/// every concrete implementation lives behind this single protocol so the rest
/// of the app never sees the math directly.
protocol DecayModel {
    var category: InventoryCategory { get }

    /// Returns a 0.0–1.0 confidence value representing estimated remaining
    /// quantity right now, given the last observation and any usage events.
    func confidence(
        lastScanConfidence: Double,
        lastScanDate: Date,
        householdSize: Int,
        usageHistory: [UsageEvent]
    ) -> Double

    /// Stable identifier — surfaced in the debug overlay and persisted as an
    /// override on `InventoryItem.decayModelOverride`.
    var modelIdentifier: String { get }
}

/// Default half-life lookup. Kept centralised so models can borrow each
/// other's defaults instead of duplicating the table.
enum DecayDefaults {
    static func halfLifeDays(for category: InventoryCategory) -> Double {
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
    /// Shared helper: subtract logged manual usage from the post-decay value.
    func applyingUsage(_ base: Double, usageHistory: [UsageEvent], since lastScanDate: Date) -> Double {
        let used = usageHistory
            .filter { $0.date >= lastScanDate }
            .reduce(0.0) { $0 + $1.quantityUsed }
        return max(0, base - used)
    }

    /// Household consumption multiplier: 1 person = 1.0, scales sub-linearly.
    /// Caps so a 6-person household isn't 6x faster — sharing pantry items
    /// has diminishing per-capita impact.
    func householdMultiplier(_ size: Int) -> Double {
        let s = Double(max(1, size))
        return 1.0 + log(s) * 0.6
    }
}
