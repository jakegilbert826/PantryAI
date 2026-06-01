import Foundation

/// Stub for the future "learned" model. Once enough quantity log entries exist
/// for an item, fits an empirical half-life from the usage cadence. Falls back
/// to linear until data justifies it — threshold is intentionally high.
final class LearnedDecayModel: DecayModel {
    let category: FoodCategory
    private let fallback: LinearDecayModel
    var modelIdentifier: String { "learned" }

    init(category: FoodCategory) {
        self.category = category
        self.fallback = LinearDecayModel(category: category)
    }

    func confidence(
        lastScanConfidence: Double,
        lastScanDate: Date,
        householdSize: Int,
        usageHistory: [ItemQuantityLog]
    ) -> Double {
        guard usageHistory.count >= 6 else {
            return fallback.confidence(
                lastScanConfidence: lastScanConfidence,
                lastScanDate: lastScanDate,
                householdSize: householdSize,
                usageHistory: usageHistory
            )
        }

        let sorted = usageHistory.sorted { $0.recordedAt < $1.recordedAt }
        let deltas: [Double] = zip(sorted, sorted.dropFirst()).map { a, b in
            b.recordedAt.timeIntervalSince(a.recordedAt) / 86_400
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
