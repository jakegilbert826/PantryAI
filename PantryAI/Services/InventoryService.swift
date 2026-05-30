import Foundation
import SwiftData

/// Single place that knows how to read/write inventory. Wraps SwiftData and
/// optionally syncs with the FastAPI backend. ViewModels only see structs.
@MainActor
final class InventoryService {
    private let context: ModelContext
    private let network = NetworkService.shared

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Reads

    func all() throws -> [InventoryItem] {
        let descriptor = FetchDescriptor<InventoryItemRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toStruct() }
    }

    func grouped() throws -> [StorageLocation: [InventoryItem]] {
        try Dictionary(grouping: all(), by: { $0.category.location })
    }

    // MARK: Writes

    /// Insert or update items from a confirmed scan. Matches by case-folded name.
    func upsert(_ items: [InventoryItem]) throws {
        let descriptor = FetchDescriptor<InventoryItemRecord>()
        let existing = try context.fetch(descriptor)

        for item in items {
            if let match = existing.first(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
                match.apply(item)
            } else {
                let record = InventoryItemRecord(
                    id: item.id,
                    name: item.name,
                    category: item.category,
                    brand: item.brand,
                    quantity: item.quantity,
                    unit: item.unit,
                    lastScanConfidence: item.lastScanConfidence,
                    lastScanDate: item.lastScanDate,
                    decayModelOverride: item.decayModelOverride,
                    imageURL: item.imageURL
                )
                context.insert(record)
            }
        }
        try context.save()
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.id == id })
        if let record = try context.fetch(descriptor).first {
            context.delete(record)
            try context.save()
        }
    }

    func logUsage(itemID: UUID, quantityUsed: Double, source: UsageEvent.Source = .manual) throws {
        let descriptor = FetchDescriptor<InventoryItemRecord>(predicate: #Predicate { $0.id == itemID })
        guard let record = try context.fetch(descriptor).first else { return }
        let event = UsageEventRecord(itemID: itemID, quantityUsed: quantityUsed, source: source)
        record.usageHistory.append(event)
        record.updatedAt = .now
        try context.save()
    }

    func clearAll() throws {
        try context.delete(model: InventoryItemRecord.self)
        try context.save()
    }

    // MARK: Backend sync (best-effort)

    func pullFromBackend() async {
        do {
            let remote = try await network.get("/api/v1/inventory", as: [BackendInventoryItem].self)
            let items = remote.map { $0.toStruct() }
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
/// SwiftData record so the two can evolve independently.
struct BackendInventoryItem: Codable {
    var id: UUID
    var name: String
    var category: String
    var brand: String?
    var quantity: Double
    var unit: String?
    var lastScanConfidence: Double
    var lastScanDate: Date
    var decayModelOverride: String?
    var imageURL: String?

    init(from item: InventoryItem) {
        self.id = item.id
        self.name = item.name
        self.category = item.category.rawValue
        self.brand = item.brand
        self.quantity = item.quantity
        self.unit = item.unit
        self.lastScanConfidence = item.lastScanConfidence
        self.lastScanDate = item.lastScanDate
        self.decayModelOverride = item.decayModelOverride
        self.imageURL = item.imageURL
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
            usageHistory: [],
            imageURL: imageURL
        )
    }
}
