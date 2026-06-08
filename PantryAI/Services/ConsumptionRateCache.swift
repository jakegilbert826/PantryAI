import Foundation
import SwiftData

/// Process-wide cache of learned `ConsumptionParameters` keyed by canonical name,
/// so read-time decay (`InventoryItem.consumptionParameters`) is a dictionary
/// lookup instead of a SwiftData fetch on every access. A single card render used
/// to trigger several identical profile fetches (amount + unit + step + ring);
/// this collapses them to ~0 (v3 design §3.1 read-time optimisation).
///
/// Populated lazily from the active `ModelContext` and kept warm by
/// `ObservationEngine.record(...)`, which writes the freshly-learned parameters
/// straight back. If the context identity changes — e.g. a fresh in-memory store
/// per test — the cache reloads automatically, so callers never see stale state.
///
/// Plain lock-guarded class rather than `@Observable`/`actor` on purpose: an
/// `actor` would force the synchronous model read path async, and `@Observable`
/// would couple every view that reads any entry to every cache mutation. Re-render
/// already happens via the `@Model` mutations in `record(...)`; the cache is
/// consulted during that render. Promote to `@Observable` only if reactive
/// invalidation is ever needed.
final class ConsumptionRateCache {
    static let shared = ConsumptionRateCache()

    private let lock = NSLock()
    private var entries: [String: ConsumptionParameters] = [:]
    private weak var loadedContext: ModelContext?

    /// Learned parameters for a canonical name, or `.none` when none are known.
    func parameters(for canonicalName: String, in context: ModelContext) -> ConsumptionParameters {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded(context)
        return entries[canonicalName] ?? .none
    }

    /// Refresh a single entry after an observation — no full reload.
    func store(_ params: ConsumptionParameters, for canonicalName: String, in context: ModelContext) {
        lock.lock(); defer { lock.unlock() }
        ensureLoaded(context)
        entries[canonicalName] = params
    }

    /// Drop everything. Used by tests for isolation; harmless in the app.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
        loadedContext = nil
    }

    /// One-time (per-context) population from persisted profiles.
    private func ensureLoaded(_ context: ModelContext) {
        guard loadedContext !== context else { return }
        entries.removeAll()
        let profiles = (try? context.fetch(FetchDescriptor<ConsumptionProfile>())) ?? []
        for profile in profiles {
            entries[profile.canonicalName] = ConsumptionParameters(profile: profile)
        }
        loadedContext = context
    }
}
