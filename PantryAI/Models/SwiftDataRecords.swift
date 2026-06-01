import Foundation
import SwiftData

@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID

    // identity
    var name: String
    var canonicalName: String
    var brandName: String?
    var barcode: String?
    var openFoodFactsId: String?

    // classification
    var packagingCategory: PackagingCategory
    var foodCategory: FoodCategory
    var storageLocation: StorageLocation
    var storageSubLocation: String?

    // measure
    var measureType: MeasureType
    var measureValue: Double?
    var measureUnit: MeasureUnit
    var measureConfidence: Double
    var measureDisplayFraction: Bool

    // container
    var containerType: ContainerType?
    var containerCount: Double?
    var containerNominalSize: Double?
    var containerNominalUnit: NominalUnit?
    var containerDisplayFraction: Bool

    // decay model
    var openedAt: Date?
    var decayRateOverride: Double?

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
        barcode: String? = nil,
        openFoodFactsId: String? = nil,
        packagingCategory: PackagingCategory = .dried,
        foodCategory: FoodCategory,
        storageLocation: StorageLocation? = nil,
        storageSubLocation: String? = nil,
        measureType: MeasureType = .count,
        measureValue: Double? = nil,
        measureUnit: MeasureUnit = .unit,
        measureConfidence: Double,
        measureDisplayFraction: Bool = false,
        containerType: ContainerType? = nil,
        containerCount: Double? = nil,
        containerNominalSize: Double? = nil,
        containerNominalUnit: NominalUnit? = nil,
        containerDisplayFraction: Bool = false,
        openedAt: Date? = nil,
        decayRateOverride: Double? = nil,
        informationSource: InformationSource = .manual,
        sourceRef: String? = nil,
        lastScannedAt: Date? = nil,
        removedAt: Date? = nil,
        removalReason: RemovalReason? = nil
    ) {
        self.id = id
        self.name = name
        self.canonicalName = canonicalName ?? name
        self.brandName = brandName
        self.barcode = barcode
        self.openFoodFactsId = openFoodFactsId
        self.packagingCategory = packagingCategory
        self.foodCategory = foodCategory
        self.storageLocation = storageLocation ?? foodCategory.location
        self.storageSubLocation = storageSubLocation
        self.measureType = measureType
        self.measureValue = measureValue
        self.measureUnit = measureUnit
        self.measureConfidence = measureConfidence
        self.measureDisplayFraction = measureDisplayFraction
        self.containerType = containerType
        self.containerCount = containerCount
        self.containerNominalSize = containerNominalSize
        self.containerNominalUnit = containerNominalUnit
        self.containerDisplayFraction = containerDisplayFraction
        self.openedAt = openedAt
        self.decayRateOverride = decayRateOverride
        self.informationSource = informationSource
        self.sourceRef = sourceRef
        self.addedAt = .now
        self.updatedAt = .now
        self.lastScannedAt = lastScannedAt
        self.removedAt = removedAt
        self.removalReason = removalReason
    }
}

@Model
final class ItemQuantityLog {
    @Attribute(.unique) var id: UUID
    var item: InventoryItem?
    var recordedAt: Date

    // quantity snapshot
    var measureType: MeasureType
    var measureValue: Double?
    var measureUnit: MeasureUnit
    var measureConfidence: Double
    var containerType: ContainerType?
    var containerCount: Double?

    // provenance
    var source: LogSource
    var sourceRef: String?

    init(
        id: UUID = UUID(),
        item: InventoryItem? = nil,
        recordedAt: Date = .now,
        measureType: MeasureType,
        measureValue: Double?,
        measureUnit: MeasureUnit,
        measureConfidence: Double,
        containerType: ContainerType? = nil,
        containerCount: Double? = nil,
        source: LogSource = .manual,
        sourceRef: String? = nil
    ) {
        self.id = id
        self.item = item
        self.recordedAt = recordedAt
        self.measureType = measureType
        self.measureValue = measureValue
        self.measureUnit = measureUnit
        self.measureConfidence = measureConfidence
        self.containerType = containerType
        self.containerCount = containerCount
        self.source = source
        self.sourceRef = sourceRef
    }
}
