import Foundation

enum DecayModelFactory {
    /// Default model per category — straight from the handoff doc.
    static func model(for category: InventoryCategory) -> any DecayModel {
        switch category {
        case .freshProduce: return ExponentialDecayModel(category: category)
        case .dairy:        return LinearDecayModel(category: category)
        case .meat:         return StepDecayModel(category: category)
        case .fish:         return StepDecayModel(category: category)
        case .frozenGoods:  return LinearDecayModel(category: category)
        case .dryGoods:     return LinearDecayModel(category: category)
        case .condiments:   return ExponentialDecayModel(category: category)
        case .beverages:    return LinearDecayModel(category: category)
        case .snacks:       return ExponentialDecayModel(category: category)
        }
    }

    /// Resolve a model from its persisted identifier (used to honour the
    /// per-item override on `InventoryItem.decayModelOverride`).
    static func model(byIdentifier id: String, category: InventoryCategory) -> (any DecayModel)? {
        switch id {
        case "linear":      return LinearDecayModel(category: category)
        case "exponential": return ExponentialDecayModel(category: category)
        case "step":        return StepDecayModel(category: category)
        case "learned":     return LearnedDecayModel(category: category)
        default:            return nil
        }
    }

    static var allModelIdentifiers: [String] {
        ["linear", "exponential", "step", "learned"]
    }
}
