import Foundation

// MARK: - Pre-confirmation scan output (not yet persisted)

struct ScannedItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var foodCategory: FoodCategory
    var brandName: String?
    var measureValue: Double
    var measureUnit: MeasureUnit
    var confidence: Double
    var include: Bool = true
}

// MARK: - Computed properties on InventoryItem @Model

extension InventoryItem {

    var decayModel: any DecayModel {
        DecayModelFactory.model(for: foodCategory, halfLifeOverride: decayRateOverride)
    }

    var currentConfidence: Double {
        decayModel.confidence(
            lastScanConfidence: measureConfidence,
            lastScanDate: lastScannedAt ?? addedAt,
            householdSize: UserPreferences.shared.householdSize,
            usageHistory: quantityLog
        )
    }

    var isLow: Bool { currentConfidence < 0.25 }
    var isExpiring: Bool { currentConfidence < 0.40 }
}
