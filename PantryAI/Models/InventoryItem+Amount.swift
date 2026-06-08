import Foundation

// MARK: - Amount display & stepping
//
// The amount shown is `quantityMeanDisplay` — a value *computed* from the v3
// anchors at read time, always in base units (grams for weight, millilitres for
// volume). Display auto-scales to kg/l above 1000 so users see human-readable
// numbers without the model tracking a separate "display unit".

extension InventoryItem {

    /// Current best-estimate amount in base units, or 0 when unknown.
    var displayAmount: Double { quantityMeanDisplay ?? 0 }

    var hasAmount: Bool { displayAmount > 0 }

    /// Human-readable amount, auto-scaling to kg/l above 1000.
    var amountDisplay: String {
        let v = displayAmount
        switch measureUnit {
        case .g  where v >= 1000: return "\(Self.formatNumber(v / 1000)) kg"
        case .ml where v >= 1000: return "\(Self.formatNumber(v / 1000)) l"
        default: return "\(Self.formatNumber(v)) \(measureUnit.rawValue)"
        }
    }

    /// Uppercased unit label for card headers, matching the current display scale.
    var displayUnitLabel: String {
        let v = displayAmount
        switch measureUnit {
        case .g  where v >= 1000: return "KG"
        case .ml where v >= 1000: return "L"
        default: return measureUnit.rawValue.uppercased()
        }
    }

    /// Step size applied per +/- tap, in stored units. Increases to 100 g/ml
    /// once the value is in the kg/l display range so each tap still moves by a
    /// visually meaningful amount (0.1 kg / 0.1 l).
    var amountStepSize: Double {
        let v = displayAmount
        switch measureUnit {
        case .g, .kg:       return v >= 1000 ? 100 : 10
        case .ml, .l:       return v >= 1000 ? 100 : 10
        case .unit, .bunch: return 1
        }
    }

    // MARK: helpers

    static func formatNumber(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
