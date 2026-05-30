import Foundation

/// Stub for the future "learned" model. Once we have enough usage events for an
/// item, we'll fit an empirical half-life. For now, fall back to linear
/// behaviour so the rest of the app sees a sensible curve. Threshold for
/// "enough history" is set deliberately high — we want this to silently turn
/// itself on when the data justifies it, not when it's noisy.
final class LearnedDecayModel: DecayModel {
    let category: InventoryCategory
    private let fallback: LinearDecayModel
    var modelIdentifier: String { "learned" }

    init(category: InventoryCategory) {
        self.category = category
        self.fallback = LinearDecayModel(category: category)
    }

    func confidence(
        lastScanConfidence: Double,
        lastScanDate: Date,
        householdSize: Int,
        usageHistory: [UsageEvent]
    ) -> Double {
        guard usageHistory.count >= 6 else {
            return fallback.confidence(
                lastScanConfidence: lastScanConfidence,
                lastScanDate: lastScanDate,
                householdSize: householdSize,
                usageHistory: usageHistory
            )
        }

        // Empirical half-life: average days between non-trivial usage events,
        // weighted by quantity consumed. Clamp to a sane bound.
        let sorted = usageHistory.sorted { $0.date < $1.date }
        let deltas: [Double] = zip(sorted, sorted.dropFirst()).map { a, b in
            b.date.timeIntervalSince(a.date) / 86_400
        }
        let avg = deltas.reduce(0, +) / Double(max(1, deltas.count))
        let empiricalHalfLife = max(0.5, min(180, avg))

        let learned = LinearDecayModel(category: category, halfLifeDays: empiricalHalfLife)
        return learned.confidence(
            lastScanConfidence: lastScanConfidence,
            lastScanDate: lastScanDate,
            householdSize: householdSize,
            usageHistory: usageHistory
        )
    }
}
