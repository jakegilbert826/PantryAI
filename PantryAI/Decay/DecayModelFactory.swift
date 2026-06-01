import Foundation

enum DecayModelFactory {
    /// Default model per category. Pass `halfLifeOverride` to use a custom half-life in days
    /// instead of the category default (corresponds to `InventoryItem.decayRateOverride`).
    static func model(for category: FoodCategory, halfLifeOverride: Double? = nil) -> any DecayModel {
        switch category {
        case .freshProduce: return ExponentialDecayModel(category: category, halfLifeDays: halfLifeOverride)
        case .dairy:        return LinearDecayModel(category: category, halfLifeDays: halfLifeOverride)
        case .meat:         return StepDecayModel(category: category, halfLifeDays: halfLifeOverride)
        case .fish:         return StepDecayModel(category: category, halfLifeDays: halfLifeOverride)
        case .frozenGoods:  return LinearDecayModel(category: category, halfLifeDays: halfLifeOverride)
        case .dryGoods:     return LinearDecayModel(category: category, halfLifeDays: halfLifeOverride)
        case .condiments:   return ExponentialDecayModel(category: category, halfLifeDays: halfLifeOverride)
        case .beverages:    return LinearDecayModel(category: category, halfLifeDays: halfLifeOverride)
        case .snacks:       return ExponentialDecayModel(category: category, halfLifeDays: halfLifeOverride)
        }
    }

    static var allModelIdentifiers: [String] {
        ["linear", "exponential", "step", "learned"]
    }
}
