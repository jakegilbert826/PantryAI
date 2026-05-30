import Foundation
import SwiftData

@MainActor
@Observable
final class PantryViewModel {
    var items: [InventoryItem] = []
    var isRefreshing = false
    var error: PantryError?
    var backendOffline = false

    private let service: InventoryService

    init(context: ModelContext) {
        self.service = InventoryService(context: context)
        load()
    }

    var hasLowItems: Bool {
        items.contains(where: { $0.isLow })
    }

    var lowItems: [InventoryItem] {
        items.filter { $0.isLow }
    }

    var byLocation: [(StorageLocation, [InventoryItem])] {
        let grouped = Dictionary(grouping: items, by: { $0.category.location })
        return [StorageLocation.fridge, .freezer, .pantry].map { loc in
            (loc, grouped[loc] ?? [])
        }
    }

    func load() {
        do {
            items = try service.all()
        } catch {
            self.error = .decoding(String(describing: error))
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await service.pullFromBackend()
        load()
    }

    func delete(_ item: InventoryItem) {
        do {
            try service.delete(id: item.id)
            load()
        } catch {
            self.error = .decoding(String(describing: error))
        }
    }

    func logUsage(_ item: InventoryItem, fraction: Double) {
        do {
            try service.logUsage(itemID: item.id, quantityUsed: fraction)
            load()
        } catch {
            self.error = .decoding(String(describing: error))
        }
    }
}
