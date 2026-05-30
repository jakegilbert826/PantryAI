import Foundation

struct InventoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var category: InventoryCategory
    var brand: String?
    /// Scan-observed quantity. 1.0 = full/new, 0.5 = half used.
    var quantity: Double
    /// Optional unit: "g", "ml", "units", or nil if unknown.
    var unit: String?
    /// Confidence at the moment of last scan (0.0–1.0).
    var lastScanConfidence: Double
    var lastScanDate: Date
    /// Per-item override for which decay model to use. `nil` → factory default.
    var decayModelOverride: String?
    var usageHistory: [UsageEvent]
    var imageURL: String?

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
        usageHistory: [UsageEvent] = [],
        imageURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.brand = brand
        self.quantity = quantity
        self.unit = unit
        self.lastScanConfidence = lastScanConfidence
        self.lastScanDate = lastScanDate
        self.decayModelOverride = decayModelOverride
        self.usageHistory = usageHistory
        self.imageURL = imageURL
    }

    /// Resolved decay model — override first, then category default.
    var decayModel: any DecayModel {
        if let id = decayModelOverride, let model = DecayModelFactory.model(byIdentifier: id, category: category) {
            return model
        }
        return DecayModelFactory.model(for: category)
    }

    /// Currently estimated confidence (combines stored decay model + history).
    var currentConfidence: Double {
        decayModel.confidence(
            lastScanConfidence: lastScanConfidence,
            lastScanDate: lastScanDate,
            householdSize: UserPreferences.shared.householdSize,
            usageHistory: usageHistory
        )
    }

    var isLow: Bool { currentConfidence < 0.25 }
    var isExpiring: Bool { currentConfidence < 0.40 }
}

/// Output of the Gemini vision call — pre-confirmation, not yet in inventory.
struct ScannedItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var category: InventoryCategory
    var brand: String?
    var quantity: Double
    var unit: String?
    var confidence: Double
    /// User can toggle this off in the review pane before commit.
    var include: Bool = true
}
