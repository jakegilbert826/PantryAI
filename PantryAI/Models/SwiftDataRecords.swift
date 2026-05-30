import Foundation
import SwiftData

/// Persisted form of an `InventoryItem`. We keep the SwiftData class separate
/// from the value-type model so views/services can pass plain structs around.
@Model
final class InventoryItemRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: String          // raw value of `InventoryCategory`
    var brand: String?
    var quantity: Double
    var unit: String?
    var lastScanConfidence: Double
    var lastScanDate: Date
    var decayModelOverride: String?
    @Relationship(deleteRule: .cascade) var usageHistory: [UsageEventRecord]
    var imageURL: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: InventoryCategory,
        brand: String? = nil,
        quantity: Double = 1.0,
        unit: String? = nil,
        lastScanConfidence: Double,
        lastScanDate: Date = .now,
        decayModelOverride: String? = nil,
        usageHistory: [UsageEventRecord] = [],
        imageURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category.rawValue
        self.brand = brand
        self.quantity = quantity
        self.unit = unit
        self.lastScanConfidence = lastScanConfidence
        self.lastScanDate = lastScanDate
        self.decayModelOverride = decayModelOverride
        self.usageHistory = usageHistory
        self.imageURL = imageURL
        self.createdAt = .now
        self.updatedAt = .now
    }

    func toStruct() -> InventoryItem {
        InventoryItem(
            id: id,
            name: name,
            category: InventoryCategory(rawValue: category) ?? .dryGoods,
            brand: brand,
            quantity: quantity,
            unit: unit,
            lastScanConfidence: lastScanConfidence,
            lastScanDate: lastScanDate,
            decayModelOverride: decayModelOverride,
            usageHistory: usageHistory.map { $0.toStruct() },
            imageURL: imageURL
        )
    }

    func apply(_ item: InventoryItem) {
        name = item.name
        category = item.category.rawValue
        brand = item.brand
        quantity = item.quantity
        unit = item.unit
        lastScanConfidence = item.lastScanConfidence
        lastScanDate = item.lastScanDate
        decayModelOverride = item.decayModelOverride
        imageURL = item.imageURL
        updatedAt = .now
    }
}

@Model
final class UsageEventRecord {
    @Attribute(.unique) var id: UUID
    var itemID: UUID
    var date: Date
    var quantityUsed: Double
    var source: String

    init(id: UUID = UUID(), itemID: UUID, date: Date = .now, quantityUsed: Double, source: UsageEvent.Source = .manual) {
        self.id = id
        self.itemID = itemID
        self.date = date
        self.quantityUsed = quantityUsed
        self.source = source.rawValue
    }

    func toStruct() -> UsageEvent {
        UsageEvent(
            id: id,
            itemID: itemID,
            date: date,
            quantityUsed: quantityUsed,
            source: UsageEvent.Source(rawValue: source) ?? .manual
        )
    }
}
