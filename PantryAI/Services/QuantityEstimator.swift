import Foundation

/// Estimates the canonical-unit quantity of an inflow when the exact amount is
/// not stated (v3 design §3.4):
///   • a stated weight/volume is used verbatim;
///   • otherwise `count × default_container_size` from `food_reference`
///     (e.g. "1 × Baked Beans" → 415 g, "12 eggs" → 12 units);
///   • failing that, the bare count.
///
/// When the size is assumed from a reference container (rather than stated) the
/// `assumedSize` flag flows into `SourceReliability.cv(...)`, inflating the
/// inflow variance so the model stays honestly uncertain.
enum QuantityEstimator {

    static func estimate(
        statedSize: Double? = nil,
        count: Int = 1,
        reference: FoodReference?
    ) -> (quantity: Double, assumedSize: Bool) {
        let n = max(1, count)
        if let statedSize, statedSize > 0 {
            return (statedSize, false)                       // exact amount given
        }
        if let unit = reference?.defaultContainerSize, unit > 0 {
            return (Double(n) * unit, true)                  // count × container size
        }
        return (Double(n), true)                             // last resort: bare count
    }
}
