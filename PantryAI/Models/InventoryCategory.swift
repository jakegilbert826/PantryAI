import SwiftUI

enum InventoryCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case freshProduce = "fresh_produce"
    case dairy        = "dairy"
    case meat         = "meat"
    case fish         = "fish"
    case frozenGoods  = "frozen_goods"
    case dryGoods     = "dry_goods"
    case condiments   = "condiments"
    case beverages    = "beverages"
    case snacks       = "snacks"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .freshProduce: return "Fresh produce"
        case .dairy:        return "Dairy"
        case .meat:         return "Meat"
        case .fish:         return "Fish"
        case .frozenGoods:  return "Frozen"
        case .dryGoods:     return "Dry goods"
        case .condiments:   return "Condiments"
        case .beverages:    return "Beverages"
        case .snacks:       return "Snacks"
        }
    }

    /// Where this category lives by default in the user's kitchen.
    var location: StorageLocation {
        switch self {
        case .freshProduce, .dairy, .meat, .fish, .beverages, .condiments:
            return .fridge
        case .frozenGoods:
            return .freezer
        case .dryGoods, .snacks:
            return .pantry
        }
    }

    /// Card colour used in the inventory grid. Matches the palette swatches
    /// (sky/mint/rose/amber/lilac) from the design.
    var cardColor: Color {
        switch self {
        case .dairy:        return Theme.rose
        case .beverages:    return Theme.sky
        case .freshProduce: return Theme.mint
        case .condiments:   return Theme.amber
        case .dryGoods:     return Theme.lilac
        case .meat:         return Theme.rose
        case .fish:         return Theme.sky
        case .frozenGoods:  return Theme.sky
        case .snacks:       return Theme.amber
        }
    }
}

enum StorageLocation: String, CaseIterable, Codable, Hashable, Identifiable {
    case fridge, freezer, pantry
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}
