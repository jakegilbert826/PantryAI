import Foundation

// MARK: - Gaussian helpers

/// Standard-normal math used by the v3 read-time availability calculation.
/// The model treats every quantity as a Gaussian (mean + variance), so
/// "probability there is still at least `threshold` left" is a normal CDF.
enum GaussianMath {

    /// Standard normal CDF Φ(x), implemented via `erfc` (available in Foundation).
    static func standardNormalCDF(_ x: Double) -> Double {
        0.5 * erfc(-x / 2.0.squareRoot())
    }

    /// Φ((value − threshold) / sd), guarding against a zero/negative sd
    /// (ground-truth edits collapse variance to a tiny floor).
    static func availability(value: Double, threshold: Double, sd: Double) -> Double {
        let safeSD = max(sd, 1e-6)
        return standardNormalCDF((value - threshold) / safeSD)
    }
}

// MARK: - Consumption parameters (read-time learned inputs)

/// The learned consumption inputs to the read-time quantity decay (v3 §3.1).
/// Resolved from an item's `ConsumptionProfile`; `.none` reproduces the
/// pre-learning behaviour — no consumption decay and a neutral spoilage
/// multiplier — which is what an item with no profile yet should see.
struct ConsumptionParameters: Equatable {
    var rate: Double        // r̄ — canonical units consumed per day
    var rateVar: Double     // σ_r² — uncertainty in the rate estimate
    var multiplier: Double  // personal half-life multiplier (spoilage)

    static let none = ConsumptionParameters(rate: 0, rateVar: 0, multiplier: 1.0)

    init(rate: Double, rateVar: Double, multiplier: Double) {
        self.rate = rate
        self.rateVar = rateVar
        self.multiplier = multiplier
    }

    /// Clamp profile values into a sane read-time range (a profile should never
    /// drive a negative rate or a non-positive half-life multiplier).
    init(profile: ConsumptionProfile) {
        self.init(
            rate: max(0, profile.consumptionRatePerDay),
            rateVar: max(0, profile.consumptionRateVar),
            multiplier: profile.personalHalfLifeMultiplier > 0 ? profile.personalHalfLifeMultiplier : 1.0
        )
    }
}

// MARK: - Cold-start spoilage priors

/// Population-average half-lives used until a `food_reference` lookup or learned
/// `ConsumptionProfile` refines them. Shelf-stable categories use a `nil`
/// (infinite) sealed half-life so sealed presence never decays — consumption is
/// the only signal there (v3 design §3.6).
enum DecayPriors {

    /// Sealed half-life in days. `nil` = infinite (no spoilage while sealed).
    static func sealedHalfLifeDays(for category: FoodCategory) -> Double? {
        switch category {
        case .freshProduce: return 5
        case .dairy:        return 7
        case .meat:         return 2
        case .fish:         return 1.5
        case .beverages:    return 14
        case .frozenGoods:  return nil   // shelf-stable while frozen
        case .dryGoods:     return nil   // shelf-stable
        case .condiments:   return nil   // shelf-stable sealed
        case .snacks:       return nil   // shelf-stable sealed
        }
    }

    /// Half-life in days once opened. Always finite — opened goods spoil.
    static func openedHalfLifeDays(for category: FoodCategory) -> Double {
        switch category {
        case .freshProduce: return 5
        case .dairy:        return 7
        case .meat:         return 2
        case .fish:         return 1.5
        case .beverages:    return 7
        case .frozenGoods:  return 3     // once thawed
        case .dryGoods:     return 60
        case .condiments:   return 90
        case .snacks:       return 30
        }
    }
}

// MARK: - Source reliability

/// Fractional measurement uncertainty (coefficient of variation) per source.
/// Measurement variance scales with magnitude: `r = (cv · q)²` (v3 design §3.5).
/// Constants live in code, not a table, so they version with the app.
enum SourceReliability {

    /// Smallest measurement variance, so a ground-truth edit (cv = 0) still
    /// produces a finite, well-conditioned variance rather than exactly zero.
    static let varianceFloor: Double = 1.0

    /// Presence knocked off per scan that covered the location but missed the
    /// item (soft non-detection, never a hard delete).
    static let missPenalty: Double = 0.3

    /// CV for a stock/inflow reading from a given source.
    /// - `assumedSize`: quantity came from `default_container_size`, not a
    ///   stated weight — inflates uncertainty so the model stays honest.
    /// - `measurementConfidence`: 1.0 means user ground truth → cv 0.
    static func cv(
        for source: LogSource,
        kind: ObservationKind,
        assumedSize: Bool,
        measurementConfidence: Double
    ) -> Double {
        if measurementConfidence >= 1.0 { return 0.0 }    // user ground truth
        switch source {
        case .manual:               return 0.0            // app edit/remove
        case .scan, .decayModel:    return 0.25           // CV pantry scan
        case .orderImport:          return assumedSize ? 0.30 : 0.10
        case .usageLog:             return 0.20
        case .chat:                 return 0.20
        }
    }

    /// Measurement variance `r = max(floor, (cv · q)²)`.
    static func measurementVariance(quantity q: Double, cv: Double) -> Double {
        max(varianceFloor, pow(cv * q, 2))
    }
}
