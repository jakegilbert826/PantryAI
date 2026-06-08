import Foundation
import SwiftData

// MARK: - InventoryItem (v3 anchor model)
//
// Only *anchors* are stored. Everything time-varying (`quantityMeanDisplay`,
// `presenceConfidence`, variance, `availabilityConfidence`) is computed at read
// time from these anchors — see `InventoryItem+Decay.swift`. This is the core
// correctness fix of v3: nothing time-dependent is persisted as a mutable value,
// so nothing goes stale.

@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID

    // identity
    var name: String
    var canonicalName: String
    var brandName: String?

    // classification
    var packagingCategory: PackagingCategory
    var foodCategory: FoodCategory
    var storageLocation: StorageLocation
    var storageSubLocation: String?

    // measure — only the unit is stored; the amount is computed from anchors.
    var measureUnit: MeasureUnit

    // spoilage config (anchors)
    var halfLifeDays: Double?          // sealed; nil = infinite (no spoilage)
    var openHalfLifeDays: Double?      // applies once opened
    var openedAt: Date?

    // observation anchors (the last hard signal)
    var lastObservedAt: Date
    var lastObservedQuantity: Double?  // mean quantity at observation (Q0); nil = amount unknown
    var observationVariance: Double    // quantity variance at observation
    var presenceAnchor: Double         // presence value at observation (usually 1.0)

    // provenance
    var informationSource: InformationSource
    var sourceRef: String?
    var addedAt: Date
    var updatedAt: Date
    var lastScannedAt: Date?

    // soft delete
    var removedAt: Date?
    var removalReason: RemovalReason?

    @Relationship(deleteRule: .cascade) var quantityLog: [ItemQuantityLog] = []

    init(
        id: UUID = UUID(),
        name: String,
        canonicalName: String? = nil,
        brandName: String? = nil,
        packagingCategory: PackagingCategory = .dried,
        foodCategory: FoodCategory,
        storageLocation: StorageLocation? = nil,
        storageSubLocation: String? = nil,
        measureUnit: MeasureUnit = .unit,
        quantity: Double? = nil,
        quantityVariance: Double? = nil,
        halfLifeDays: Double?? = nil,
        openHalfLifeDays: Double? = nil,
        openedAt: Date? = nil,
        presenceAnchor: Double = 1.0,
        informationSource: InformationSource = .manual,
        sourceRef: String? = nil,
        lastObservedAt: Date? = nil,
        lastScannedAt: Date? = nil,
        removedAt: Date? = nil,
        removalReason: RemovalReason? = nil
    ) {
        self.id = id
        self.name = name
        self.canonicalName = canonicalName ?? name
        self.brandName = brandName
        self.packagingCategory = packagingCategory
        self.foodCategory = foodCategory
        self.storageLocation = storageLocation ?? foodCategory.location
        self.storageSubLocation = storageSubLocation
        self.measureUnit = measureUnit
        // Cold-start spoilage prior: explicit value wins, else category default.
        // `Double??` lets a caller pass `.some(nil)` to force "infinite".
        switch halfLifeDays {
        case .some(let value): self.halfLifeDays = value
        case .none:            self.halfLifeDays = DecayPriors.sealedHalfLifeDays(for: foodCategory)
        }
        self.openHalfLifeDays = openHalfLifeDays ?? DecayPriors.openedHalfLifeDays(for: foodCategory)
        self.openedAt = openedAt
        self.lastObservedAt = lastObservedAt ?? lastScannedAt ?? .now
        self.lastObservedQuantity = quantity
        // Cold-start variance: explicit value wins, else a generous prior so the
        // model stays honestly uncertain about an assumed amount.
        self.observationVariance = quantityVariance ?? (quantity.map { pow(0.3 * $0, 2) } ?? 0)
        self.presenceAnchor = presenceAnchor
        self.informationSource = informationSource
        self.sourceRef = sourceRef
        self.addedAt = .now
        self.updatedAt = .now
        self.lastScannedAt = lastScannedAt
        self.removedAt = removedAt
        self.removalReason = removalReason
    }

    /// Derived from the stored unit — `measure_type` is never persisted (v3 §6.1).
    var measureType: MeasureType { MeasureType.from(measureUnit) }

    /// Opened state is derived, not stored, to avoid a write-sync risk (v3 §11.3).
    var isOpened: Bool { openedAt != nil }
}

// MARK: - ItemQuantityLog (recent observation log)
//
// A bounded, append-only record of every observation. Doubles as the data
// source for a future "item history / undo" feature (v3 §2).

@Model
final class ItemQuantityLog {
    @Attribute(.unique) var id: UUID
    var item: InventoryItem?
    var recordedAt: Date

    // what kind of signal this was
    var observationKind: ObservationKind

    // quantity reading (nil when presence-only / non-detection)
    var measureValue: Double?
    var measureUnit: MeasureUnit
    var measurementConfidence: Double   // quality of *this* reading
    var assumedSize: Bool               // quantity came from a default container size

    // provenance
    var source: LogSource
    var sourceRef: String?

    init(
        id: UUID = UUID(),
        item: InventoryItem? = nil,
        recordedAt: Date = .now,
        observationKind: ObservationKind,
        measureValue: Double?,
        measureUnit: MeasureUnit,
        measurementConfidence: Double,
        assumedSize: Bool = false,
        source: LogSource = .manual,
        sourceRef: String? = nil
    ) {
        self.id = id
        self.item = item
        self.recordedAt = recordedAt
        self.observationKind = observationKind
        self.measureValue = measureValue
        self.measureUnit = measureUnit
        self.measurementConfidence = measurementConfidence
        self.assumedSize = assumedSize
        self.source = source
        self.sourceRef = sourceRef
    }

    /// Derived from the stored unit — never persisted separately.
    var measureType: MeasureType { MeasureType.from(measureUnit) }
}

// MARK: - ConsumptionProfile (per canonical_name learned params)
//
// Survives item churn: when an item is removed its depletion folds in here, and
// the recent log can be pruned without losing the learned signal (v3 §6.3).

@Model
final class ConsumptionProfile {
    @Attribute(.unique) var canonicalName: String
    var consumptionRatePerDay: Double        // r̄ (canonical units/day, EWMA)
    var consumptionRateVar: Double           // σ_r²
    var personalHalfLifeMultiplier: Double   // 1.0 default
    var observationCount: Int
    var lastPurchaseAt: Date?                 // for purchase-cadence learning
    var updatedAt: Date

    init(
        canonicalName: String,
        consumptionRatePerDay: Double = 0,
        consumptionRateVar: Double = 0,
        personalHalfLifeMultiplier: Double = 1.0,
        observationCount: Int = 0,
        lastPurchaseAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.canonicalName = canonicalName
        self.consumptionRatePerDay = consumptionRatePerDay
        self.consumptionRateVar = consumptionRateVar
        self.personalHalfLifeMultiplier = personalHalfLifeMultiplier
        self.observationCount = observationCount
        self.lastPurchaseAt = lastPurchaseAt
        self.updatedAt = updatedAt
    }
}
