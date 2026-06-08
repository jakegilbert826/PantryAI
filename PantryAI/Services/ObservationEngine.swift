import Foundation
import SwiftData

// MARK: - Observation

/// One typed signal about an item. Every mutation to an item's quantity/presence
/// flows through `ObservationEngine.record(_:on:)` as an `InventoryObservation` — the
/// single funnel from v3 §5. Nothing writes the anchors directly.
struct InventoryObservation {
    var kind: ObservationKind
    var quantity: Double?
    var source: LogSource
    /// Quality of *this* reading, 0–1. 1.0 = user ground truth (cv 0).
    var measurementConfidence: Double
    /// Quantity came from a default container size rather than a stated amount.
    var assumedSize: Bool
    var at: Date

    init(
        kind: ObservationKind,
        quantity: Double? = nil,
        source: LogSource,
        measurementConfidence: Double,
        assumedSize: Bool = false,
        at: Date = .now
    ) {
        self.kind = kind
        self.quantity = quantity
        self.source = source
        self.measurementConfidence = measurementConfidence
        self.assumedSize = assumedSize
        self.at = at
    }

    /// A ground-truth stock reading from a user edit in the app.
    static func userStock(_ quantity: Double, at: Date = .now) -> InventoryObservation {
        InventoryObservation(kind: .stock, quantity: quantity, source: .manual,
                    measurementConfidence: 1.0, at: at)
    }

    /// An inflow (purchase) whose amount may be estimated from a reference
    /// container size when not stated (v3 §3.4). The `assumedSize` flag set by
    /// `QuantityEstimator` widens the inflow variance accordingly.
    static func purchase(
        statedSize: Double? = nil,
        count: Int = 1,
        reference: FoodReference?,
        source: LogSource = .orderImport,
        at: Date = .now
    ) -> InventoryObservation {
        let est = QuantityEstimator.estimate(statedSize: statedSize, count: count, reference: reference)
        return InventoryObservation(
            kind: .inflow,
            quantity: est.quantity,
            source: source,
            measurementConfidence: est.assumedSize ? 0.6 : 0.9,
            assumedSize: est.assumedSize,
            at: at
        )
    }
}

// MARK: - ObservationEngine

/// Applies the v3 typed observation update (§3.3): re-anchors the decay clock,
/// fuses/updates the quantity distribution, appends an `ItemQuantityLog`, prunes
/// the log, and keeps the per-canonical `ConsumptionProfile` in step.
@MainActor
struct ObservationEngine {
    let context: ModelContext

    // Log retention: keep the most recent observations or 120 days, whichever
    // is larger. Online learning means pruning loses nothing (v3 §2).
    private static let maxLogEntries = 20
    private static let maxLogAgeDays: Double = 120

    // Online learning (v3 §4.2). EWMA so the estimate tracks recent behaviour;
    // the first sample is adopted directly, later samples are smoothed. Single
    // noisy readings are gated out by requiring a minimum interval and genuine
    // depletion before a sample is taken.
    private static let rateLearningAlpha = 0.3
    private static let minStockIntervalDays: Double = 0.25
    private static let minCadenceIntervalDays: Double = 0.5

    func record(_ observation: InventoryObservation, on item: InventoryItem) {
        let profile = profile(forCanonical: item.canonicalName)
        let params = ConsumptionParameters(profile: profile)
        let now = observation.at

        // Snapshot the prior anchors before the update re-anchors them — both
        // learning signals compare the new reading against the previous one.
        let prevQuantity = item.lastObservedQuantity
        let prevObservedAt = item.lastObservedAt
        let prevPurchaseAt = profile.lastPurchaseAt

        switch observation.kind {
        case .stock:
            applyStock(observation, on: item, rate: params.rate, rateVar: params.rateVar, at: now)
            learnFromStockPair(qPrev: prevQuantity, prevAt: prevObservedAt,
                               observation: observation, profile: profile)
        case .inflow:
            applyInflow(observation, on: item, rate: params.rate, rateVar: params.rateVar, at: now)
            learnFromCadence(purchased: observation.quantity ?? 0,
                             lastPurchaseAt: prevPurchaseAt, at: now, profile: profile)
            profile.lastPurchaseAt = now
        case .presenceOnly:
            item.presenceAnchor = 1.0
        case .nonDetection:
            let p = item.presenceConfidence(at: now, multiplier: params.multiplier)
            item.presenceAnchor = p * (1 - SourceReliability.missPenalty)
        }

        item.lastObservedAt = now
        item.updatedAt = now

        appendLog(observation, on: item)
        pruneLog(item, now: now)

        profile.observationCount += 1
        profile.updatedAt = now

        try? context.save()

        // Keep the read-time cache warm so the next render is a dict lookup.
        ConsumptionRateCache.shared.store(ConsumptionParameters(profile: profile),
                                          for: item.canonicalName, in: context)
    }

    // MARK: update kinds

    /// Kalman-fuse the new reading onto the predicted (decayed) mean.
    private func applyStock(_ obs: InventoryObservation, on item: InventoryItem, rate: Double, rateVar: Double, at now: Date) {
        let qObs = obs.quantity ?? 0
        let cv = SourceReliability.cv(for: obs.source, kind: .stock,
                                      assumedSize: obs.assumedSize,
                                      measurementConfidence: obs.measurementConfidence)
        let r = SourceReliability.measurementVariance(quantity: qObs, cv: cv)

        if let predMean = item.quantityMeanRaw(rate: rate, at: now) {
            let predVar = item.quantityVariance(rateVar: rateVar, at: now)
            let k = predVar / (predVar + r)
            item.lastObservedQuantity = predMean + k * (qObs - predMean)
            item.observationVariance = (1 - k) * predVar
        } else {
            // First quantity ever observed → adopt it directly.
            item.lastObservedQuantity = qObs
            item.observationVariance = r
        }
        item.presenceAnchor = 1.0
    }

    /// Add a purchase to the current (decayed) amount and re-anchor.
    private func applyInflow(_ obs: InventoryObservation, on item: InventoryItem, rate: Double, rateVar: Double, at now: Date) {
        let purchased = obs.quantity ?? 0
        let base = max(0, item.quantityMeanRaw(rate: rate, at: now) ?? 0)
        let cv = SourceReliability.cv(for: obs.source, kind: .inflow,
                                      assumedSize: obs.assumedSize,
                                      measurementConfidence: obs.measurementConfidence)
        let inflowVar = SourceReliability.measurementVariance(quantity: purchased, cv: cv)
        item.lastObservedQuantity = base + purchased
        item.observationVariance = item.quantityVariance(rateVar: rateVar, at: now) + inflowVar
        item.presenceAnchor = 1.0
    }

    // MARK: learning (v3 §4.2)

    /// Signal A — stock-pair: depletion observed between two stock readings
    /// implies a consumption rate. Skips refills (a higher reading) and
    /// near-instant re-reads, which carry no usable rate information.
    private func learnFromStockPair(
        qPrev: Double?,
        prevAt: Date,
        observation: InventoryObservation,
        profile: ConsumptionProfile
    ) {
        guard let qPrev, let qNow = observation.quantity else { return }
        let days = observation.at.timeIntervalSince(prevAt) / 86_400
        guard days >= Self.minStockIntervalDays else { return }
        let depleted = qPrev - qNow
        guard depleted > 0 else { return }   // a higher reading is a restock
        updateRate(profile, sample: depleted / days)
    }

    /// Signal B — purchase cadence: in steady state, rate ≈ purchased amount
    /// over the inter-purchase interval. The densest signal for online shoppers
    /// (it needs no stock observation at all).
    private func learnFromCadence(
        purchased: Double,
        lastPurchaseAt: Date?,
        at now: Date,
        profile: ConsumptionProfile
    ) {
        guard let lastPurchaseAt, purchased > 0 else { return }
        let days = now.timeIntervalSince(lastPurchaseAt) / 86_400
        guard days >= Self.minCadenceIntervalDays else { return }
        updateRate(profile, sample: purchased / days)
    }

    /// EWMA update of the learned rate and its uncertainty. The first sample is
    /// adopted directly (no prior); subsequent samples are smoothed, and the
    /// rate variance shrinks as samples agree, grows when they disagree.
    private func updateRate(_ profile: ConsumptionProfile, sample: Double) {
        guard sample > 0 else { return }
        if profile.consumptionRatePerDay <= 0 {
            profile.consumptionRatePerDay = sample
            profile.consumptionRateVar = pow(sample * 0.5, 2)
            return
        }
        let a = Self.rateLearningAlpha
        let prev = profile.consumptionRatePerDay
        let resid = sample - prev
        profile.consumptionRatePerDay = prev + a * resid
        profile.consumptionRateVar = (1 - a) * (profile.consumptionRateVar + a * resid * resid)
    }

    // MARK: log + profile

    private func appendLog(_ obs: InventoryObservation, on item: InventoryItem) {
        let log = ItemQuantityLog(
            item: item,
            recordedAt: obs.at,
            observationKind: obs.kind,
            measureValue: obs.quantity,
            measureUnit: item.measureUnit,
            measurementConfidence: obs.measurementConfidence,
            assumedSize: obs.assumedSize,
            source: obs.source
        )
        context.insert(log)
        item.quantityLog.append(log)
    }

    /// Keep the most recent entries or those within the retention window.
    private func pruneLog(_ item: InventoryItem, now: Date) {
        guard item.quantityLog.count > Self.maxLogEntries else { return }
        let cutoff = now.addingTimeInterval(-Self.maxLogAgeDays * 86_400)
        let sorted = item.quantityLog.sorted { $0.recordedAt > $1.recordedAt }
        for (index, log) in sorted.enumerated() {
            guard index >= Self.maxLogEntries, log.recordedAt < cutoff else { continue }
            if let position = item.quantityLog.firstIndex(where: { $0.id == log.id }) {
                item.quantityLog.remove(at: position)
            }
            context.delete(log)
        }
    }

    /// Fetch or lazily create the per-canonical consumption profile.
    private func profile(forCanonical canonical: String) -> ConsumptionProfile {
        let descriptor = FetchDescriptor<ConsumptionProfile>(
            predicate: #Predicate { $0.canonicalName == canonical }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        // TODO(consumption-prior): the new profile starts at rate 0, so quantity
        // does not decay from consumption until the first stock-pair / cadence
        // sample lands. Re-evaluate seeding a per-food `consumption_rate_per_day`
        // (canonical units) from `food_reference`, scaled by the household factor
        // (design §4.1), so cold-start items decay sensibly before any learning.
        // Deferred for now: needs seed data + an item-level prior field to surface
        // the async `food_reference` value synchronously. See Current-State.md.
        let created = ConsumptionProfile(canonicalName: canonical)
        context.insert(created)
        return created
    }
}
