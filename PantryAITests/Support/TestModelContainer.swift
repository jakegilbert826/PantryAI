import Foundation
import SwiftData
@testable import PantryAI

/// Spins up an in-memory SwiftData stack so service/view-model tests never
/// touch the on-disk store. Each call is fully isolated.
@MainActor
enum TestModelContainer {
    static func make() -> ModelContext {
        let schema = Schema([
            InventoryItem.self,
            ItemQuantityLog.self,
            RecipePreference.self,
            ScanSession.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}

extension Date {
    static func daysAgo(_ days: Double) -> Date {
        Date.now.addingTimeInterval(-days * 86_400)
    }
}
