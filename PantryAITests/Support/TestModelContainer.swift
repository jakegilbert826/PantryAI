import Foundation
import SwiftData
@testable import PantryAI

/// Spins up an in-memory SwiftData stack so service/view-model tests never
/// touch the on-disk store. Each call is fully isolated.
@MainActor
enum TestModelContainer {
    static func make() -> ModelContext {
        let schema = Schema([
            InventoryItemRecord.self,
            UsageEventRecord.self,
            RecipePreference.self,
            ScanSession.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // In-memory configuration cannot fail in practice; trap if it ever does.
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}

extension Date {
    /// Convenience: a date `days` in the past from now.
    static func daysAgo(_ days: Double) -> Date {
        Date.now.addingTimeInterval(-days * 86_400)
    }
}
