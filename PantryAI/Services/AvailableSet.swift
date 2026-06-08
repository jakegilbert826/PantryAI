import Foundation

/// Computes the "available" canonical-name set for recipe matching (design §8):
/// pantry items whose read-time `availabilityConfidence` clears the threshold τ.
///
/// Substitution expansion (symmetric `substitution_group` + directed pairs)
/// happens *remotely* inside the `match_recipes` RPC, where the substitution
/// tables live — so this only applies the threshold filter and de-duplicates by
/// canonical name. Keeping the device side this thin is deliberate: it never
/// caches the substitution data.
@MainActor
enum AvailableSet {
    /// τ — minimum read-time availability for an item to count as "in stock" for
    /// recipe matching. 0.5 ≈ "more likely present than not". Tunable.
    nonisolated static let defaultThreshold = 0.5

    /// De-duplicated canonical names of active items above `threshold` at `now`.
    /// Order follows first appearance in `items` (stable for callers/tests).
    static func canonicalNames(
        from items: [InventoryItem],
        threshold: Double = defaultThreshold,
        at now: Date = .now
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items where item.removedAt == nil
            && item.resolvedAvailabilityConfidence(at: now) > threshold {
            if seen.insert(item.canonicalName).inserted {
                result.append(item.canonicalName)
            }
        }
        return result
    }
}
