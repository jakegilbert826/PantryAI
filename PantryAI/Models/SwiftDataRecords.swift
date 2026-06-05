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

extension InventoryItem {
    static func migrateBaseUnits(in context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []
        var changed = false
        for item in items {
            switch item.measureUnit {
            case .kg:
                item.measureValue = (item.measureValue ?? 0) * 1000
                item.measureUnit = .g
                item.measureType = .weight
                changed = true
            case .l:
                item.measureValue = (item.measureValue ?? 0) * 1000
                item.measureUnit = .ml
                item.measureType = .volume
                changed = true
            case .bunch:
                item.measureUnit = .unit
                item.measureType = .count
                changed = true
            default:
                if item.measureType == .bunch {
                    item.measureType = .count
                    changed = true
                }
            }
        }
        if changed { try? context.save() }
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
        self.source = source
        self.sourceRef = sourceRef
    }
}
