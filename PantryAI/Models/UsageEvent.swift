import Foundation

struct UsageEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var itemID: UUID
    var date: Date
    /// Estimated fraction of the item used in this event (0.0–1.0).
    var quantityUsed: Double
    var source: Source

    enum Source: String, Codable, Hashable {
        case manual           // user logged it explicitly
        case recipeCooked     // recorded when a recipe was marked cooked
        case inferred         // inferred from a re-scan diff
    }

    init(id: UUID = UUID(), itemID: UUID, date: Date = .now, quantityUsed: Double, source: Source = .manual) {
        self.id = id
        self.itemID = itemID
        self.date = date
        self.quantityUsed = quantityUsed
        self.source = source
    }
}
