import SwiftUI

// MARK: - Food classification

enum FoodCategory: String, CaseIterable, Codable, Identifiable, Hashable {
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

    var location: StorageLocation {
        switch self {
        case .freshProduce, .dairy, .meat, .fish, .beverages, .condiments: return .fridge
        case .frozenGoods: return .freezer
        case .dryGoods, .snacks: return .pantry
        }
    }

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

// MARK: - Storage

enum StorageLocation: String, CaseIterable, Codable, Hashable, Identifiable {
    case fridge, freezer, pantry
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

// MARK: - Packaging

enum PackagingCategory: String, Codable, Hashable {
    case canned, dried, frozen, fresh, beverage, condiment
}

// MARK: - Measure

enum MeasureType: String, Codable, Hashable {
    case weight, volume, count
    case bunch // legacy — migrated to .count on first launch; never written

    static func from(_ unit: MeasureUnit) -> MeasureType {
        switch unit {
        case .g, .kg:       return .weight
        case .ml, .l:       return .volume
        case .unit, .bunch: return .count
        }
    }
}

enum MeasureUnit: String, CaseIterable, Codable, Hashable {
    case g, kg, ml, l, unit
    case bunch // legacy — migrated to .unit on first launch; never written

    static func from(_ string: String?) -> MeasureUnit {
        guard let s = string else { return .unit }
        return MeasureUnit(rawValue: s.lowercased()) ?? .unit
    }
}

// MARK: - Provenance

enum InformationSource: String, Codable, Hashable {
    case pantryScan, receipt, receiptSync, barcode, manual, inChat
}

enum RemovalReason: String, Codable, Hashable {
    case consumed, wasted, expired, donated
}

// MARK: - Quantity log

enum LogSource: String, Codable, Hashable {
    case scan, orderImport, manual, decayModel, usageLog
}
