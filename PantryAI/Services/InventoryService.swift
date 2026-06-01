import Foundation
import SwiftData

/// Single place that knows how to read/write inventory. Wraps SwiftData and
/// optionally syncs with the FastAPI backend. Deletion is soft — items are
/// hidden by setting `removedAt` rather than being permanently erased.
@MainActor
final class InventoryService {
    private let context: ModelContext
    private let network = NetworkService.shared

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Reads

    func all() throws -> [InventoryItem] {
        let descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate { $0.removedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func grouped() throws -> [StorageLocation: [InventoryItem]] {
        try Dictionary(grouping: all(), by: { $0.storageLocation })
    }

    // MARK: Writes

    /// Insert or update items from a confirmed scan. Matches by case-folded name
    /// against active (non-removed) items.
    func upsert(_ items: [InventoryItem]) throws {
        let existing = try context.fetch(
            FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.removedAt == nil })
        )
        for item in items {
            if let match = existing.first(where: {
                $0.name.caseInsensitiveCompare(item.name) == .orderedSame
            }) {
                match.brandName = item.brandName
                match.foodCategory = item.foodCategory
                match.packagingCategory = item.packagingCategory
                match.storageLocation = item.storageLocation
                match.measureType = item.measureType
                match.measureValue = item.measureValue
                match.measureUnit = item.measureUnit
                match.measureConfidence = item.measureConfidence
                match.informationSource = item.informationSource
                match.lastScannedAt = item.lastScannedAt ?? .now
                match.updatedAt = .now
            } else {
                context.insert(item)
            }
        }
        try context.save()
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })
        if let item = try context.fetch(descriptor).first {
            item.removedAt = .now
            item.removalReason = .consumed
            item.updatedAt = .now
            try context.save()
        }
    }

    func delete(name: String) throws {
        let lower = name.lowercased()
        let descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.removedAt == nil })
        var changed = false
        for item in try context.fetch(descriptor) where item.name.lowercased() == lower {
            item.removedAt = .now
            item.removalReason = .consumed
            item.updatedAt = .now
            changed = true
        }
        if changed { try context.save() }
    }

    func logUsage(itemID: UUID, quantityUsed: Double, source: LogSource = .manual) throws {
        let descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == itemID })
        guard let item = try context.fetch(descriptor).first else { return }
        let log = ItemQuantityLog(
            measureType: item.measureType,
            measureValue: quantityUsed,
            measureUnit: item.measureUnit,
            measureConfidence: item.measureConfidence,
            source: source
        )
        context.insert(log)
        item.quantityLog.append(log)
        item.updatedAt = .now
        try context.save()
    }

    func clearAll() throws {
        try context.delete(model: InventoryItem.self)
        try context.save()
    }

    // MARK: Backend sync (best-effort)

    func pullFromBackend() async {
        do {
            let remote = try await network.get("/api/v1/inventory", as: [BackendInventoryItem].self)
            let items = remote.map { $0.toModel() }
            try upsert(items)
        } catch {
            // Backend offline → silently keep the cached SwiftData copy.
        }
    }

    func pushUpsert(_ items: [InventoryItem]) async {
        let payload = items.map { BackendInventoryItem(from: $0) }
        _ = try? await network.post("/api/v1/inventory/upsert", body: payload, as: [BackendInventoryItem].self)
    }
}

/// Wire-format mirror for the FastAPI endpoint. Kept separate from the local
/// SwiftData model so the two can evolve independently.
struct BackendInventoryItem: Codable {
    var id: UUID
    var name: String
    var foodCategory: String
    var brandName: String?
    var measureValue: Double?
    var measureUnit: String
    var measureConfidence: Double
    var lastScannedAt: Date?
    var decayRateOverride: Double?

    init(from item: InventoryItem) {
        self.id = item.id
        self.name = item.name
        self.foodCategory = item.foodCategory.rawValue
        self.brandName = item.brandName
        self.measureValue = item.measureValue
        self.measureUnit = item.measureUnit.rawValue
        self.measureConfidence = item.measureConfidence
        self.lastScannedAt = item.lastScannedAt
        self.decayRateOverride = item.decayRateOverride
    }

    func toModel() -> InventoryItem {
        InventoryItem(
            id: id,
            name: name,
            brandName: brandName,
            foodCategory: FoodCategory(rawValue: foodCategory) ?? .dryGoods,
            measureValue: measureValue,
            measureUnit: MeasureUnit(rawValue: measureUnit) ?? .unit,
            measureConfidence: measureConfidence,
            decayRateOverride: decayRateOverride,
            informationSource: .manual,
            lastScannedAt: lastScannedAt
        )
    }
}
