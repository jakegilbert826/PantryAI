import Foundation
import SwiftData

// MARK: - Pre-confirmation scan output (not yet persisted)

struct ScannedItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var canonicalName: String
    var foodCategory: FoodCategory
    var brandName: String?
    var measureValue: Double
    var measureUnit: MeasureUnit
    var confidence: Double
    var include: Bool = true
}

// MARK: - v3 read-time decay model
//
// Two decay processes, kept separate and combined only at read time (design §3):
//   • spoilage (physical, from half-lives) → `presenceConfidence`
//   • consumption (behavioural, learned rate) → `quantityMean*`
// Everything here is computed from the stored anchors and `now`; nothing
// time-varying is persisted, so nothing goes stale.

extension InventoryItem {

    /// Days elapsed since the last hard observation.
    private func elapsedDays(to now: Date) -> Double {
        max(0, now.timeIntervalSince(lastObservedAt) / 86_400)
    }

    /// Learned consumption parameters for this item's canonical name (v3 §3.1 +
    /// §4.2). `.none` (rate 0, multiplier 1) when there is no context or no
    /// `ConsumptionProfile` yet — identical to the pre-learning read path.
    /// Served from `ConsumptionRateCache` (a dictionary lookup, not a fetch), kept
    /// warm by `ObservationEngine.record(...)`.
    var consumptionParameters: ConsumptionParameters {
        guard let modelContext else { return .none }
        return ConsumptionRateCache.shared.parameters(for: canonicalName, in: modelContext)
    }

    /// Effective half-life in days, picking sealed vs opened and applying the
    /// personal multiplier. `nil` = infinite (no spoilage).
    func effectiveHalfLife(multiplier: Double = 1.0) -> Double? {
        let base = isOpened ? openHalfLifeDays : halfLifeDays
        guard let base else { return nil }
        return base * multiplier
    }

    /// Spoilage-driven presence in [0, 1]. Infinite half-life → never decays.
    func presenceConfidence(at now: Date = .now, multiplier: Double = 1.0) -> Double {
        guard let halfLife = effectiveHalfLife(multiplier: multiplier), halfLife > 0 else {
            return presenceAnchor
        }
        return presenceAnchor * pow(0.5, elapsedDays(to: now) / halfLife)
    }

    /// Consumption-driven mean quantity, **unclamped** (may go negative so the
    /// availability CDF keeps falling past expected exhaustion). `nil` when the
    /// amount was never observed.
    func quantityMeanRaw(rate: Double = 0, at now: Date = .now) -> Double? {
        guard let q0 = lastObservedQuantity else { return nil }
        return q0 - rate * elapsedDays(to: now)
    }

    /// Clamped mean for display. `nil` when the amount is unknown.
    func quantityMeanDisplay(rate: Double = 0, at now: Date = .now) -> Double? {
        quantityMeanRaw(rate: rate, at: now).map { max(0, $0) }
    }

    /// Displayed mean using this item's learned consumption rate (§4.2).
    var quantityMeanDisplay: Double? {
        quantityMeanDisplay(rate: consumptionParameters.rate)
    }

    /// Quantity variance, growing with rate uncertainty over time.
    func quantityVariance(rateVar: Double = 0, at now: Date = .now) -> Double {
        let dt = elapsedDays(to: now)
        return observationVariance + rateVar * dt * dt
    }

    /// P(at least `threshold` remains). When the amount is unknown we don't
    /// penalise quantity — presence alone carries the signal.
    func availabilityQuantity(threshold: Double = 0, rate: Double = 0, rateVar: Double = 0, at now: Date = .now) -> Double {
        guard let mean = quantityMeanRaw(rate: rate, at: now) else { return 1.0 }
        let sd = quantityVariance(rateVar: rateVar, at: now).squareRoot()
        return GaussianMath.availability(value: mean, threshold: threshold, sd: sd)
    }

    /// Combined read-time availability = presence × P(quantity ≥ threshold).
    func availabilityConfidence(
        threshold: Double = 0,
        rate: Double = 0,
        rateVar: Double = 0,
        multiplier: Double = 1.0,
        at now: Date = .now
    ) -> Double {
        presenceConfidence(at: now, multiplier: multiplier)
            * availabilityQuantity(threshold: threshold, rate: rate, rateVar: rateVar, at: now)
    }

    /// Read-time availability using this item's learned consumption parameters
    /// (§3.2 + §4.2). The fully-parameterised `availabilityConfidence(...)` above
    /// stays the testable/engine entry point; this resolves the rate for callers.
    func resolvedAvailabilityConfidence(threshold: Double = 0, at now: Date = .now) -> Double {
        let p = consumptionParameters
        return availabilityConfidence(threshold: threshold, rate: p.rate,
                                      rateVar: p.rateVar, multiplier: p.multiplier, at: now)
    }

    /// Single 0–1 number the UI shows (ring, freshness bar), now driven by the
    /// learned consumption rate where one exists.
    var currentConfidence: Double { resolvedAvailabilityConfidence() }

    var isLow: Bool { currentConfidence < 0.25 }
    var isExpiring: Bool { currentConfidence < 0.40 }
}
