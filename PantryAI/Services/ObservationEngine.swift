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

    func record(_ observation: InventoryObservation, on item: InventoryItem) {
        let profile = profile(forCanonical: item.canonicalName)
        let rate = profile.consumptionRatePerDay
        let rateVar = profile.consumptionRateVar
        let multiplier = profile.personalHalfLifeMultiplier
        let now = observation.at

        switch observation.kind {
        case .stock:
            applyStock(observation, on: item, rate: rate, rateVar: rateVar, at: now)
        case .inflow:
            applyInflow(observation, on: item, rate: rate, rateVar: rateVar, at: now)
            profile.lastPurchaseAt = now
        case .presenceOnly:
            item.presenceAnchor = 1.0
        case .nonDetection:
            let p = item.presenceConfidence(at: now, multiplier: multiplier)
            item.presenceAnchor = p * (1 - SourceReliability.missPenalty)
        }

        item.lastObservedAt = now
        item.updatedAt = now

        appendLog(observation, on: item)
        pruneLog(item, now: now)

        profile.observationCount += 1
        profile.updatedAt = now

        try? context.save()
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
        let created = ConsumptionProfile(canonicalName: canonical)
        context.insert(created)
        return created
    }
}
