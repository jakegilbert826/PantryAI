import Foundation

// MARK: - Shared amount display & stepping
//
// `measureValue` is the single source of truth for how much of an item is on
// hand. The container view ("2 bags", "1 bunch") is just a *lens* over that
// value, derived via the nominal container size — so the compact card and the
// detail view can never disagree, and switching lenses never mutates data.

struct AmountDisplay {
    /// Primary line, e.g. "500 g" or "2 bags".
    let primary: String
    /// Optional caption, e.g. "500g each". `nil` in measure mode.
    let secondary: String?
}

enum MeasureFamily { case weight, volume, count, bunch }

extension InventoryItem {

    var hasAmount: Bool { (measureValue ?? 0) > 0 }

    /// How to present the amount, honouring the user's stored lens choice.
    var amountDisplay: AmountDisplay {
        let value = measureValue ?? 0
        switch preferredUnit {
        case .measure:
            return AmountDisplay(primary: "\(Self.formatNumber(value)) \(measureUnit.rawValue)", secondary: nil)

        case .container:
            if let count = derivedContainerCount,
               let size = containerNominalSize,
               let nominalUnit = containerNominalUnit {
                return AmountDisplay(
                    primary: "\(Self.formatNumber(count)) \(containerNoun(for: count))",
                    secondary: "\(Self.formatNumber(size))\(nominalUnit.rawValue) each"
                )
            }
            // No nominal size (count / bunch items like "1 bunch broccolini").
            return AmountDisplay(primary: "\(Self.formatNumber(value)) \(containerNoun(for: value))", secondary: nil)
        }
    }

    /// Number of containers implied by the current measure value, or `nil` when
    /// there is no comparable nominal size (different unit families / no size).
    var derivedContainerCount: Double? {
        guard let value = measureValue,
              let size = containerNominalSize, size > 0,
              let nominalUnit = containerNominalUnit,
              let measureBase = measureUnit.baseFactor,
              measureUnit.family == nominalUnit.family
        else { return nil }
        let totalBase = value * measureBase
        let sizeBase = size * nominalUnit.baseFactor
        return totalBase / sizeBase
    }

    /// Whether both lenses are meaningful for this item (controls the toggle).
    var supportsContainerLens: Bool {
        containerType != nil || measureType == .count || measureType == .bunch
    }

    /// Step applied to `measureValue` per +/- tap, expressed in `measureUnit`.
    var amountStepSize: Double {
        switch preferredUnit {
        case .container:
            // One container's worth, converted into measure units.
            if let size = containerNominalSize,
               let nominalUnit = containerNominalUnit,
               let measureBase = measureUnit.baseFactor, measureBase > 0,
               measureUnit.family == nominalUnit.family {
                return size * nominalUnit.baseFactor / measureBase
            }
            return 1
        case .measure:
            switch measureUnit {
            case .g:            return 10
            case .kg:           return 0.1
            case .ml:           return 10
            case .l:            return 0.1
            case .unit, .bunch: return 1
            }
        }
    }

    // MARK: helpers

    func containerNoun(for count: Double) -> String {
        let base: String
        if let ct = containerType {
            base = ct.rawValue
        } else if measureUnit == .bunch {
            base = "bunch"
        } else {
            base = "unit"
        }
        return count == 1 ? base : Self.pluralize(base)
    }

    static func formatNumber(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    static func pluralize(_ word: String) -> String {
        if word.hasSuffix("s") || word.hasSuffix("x") || word.hasSuffix("ch") || word.hasSuffix("sh") {
            return word + "es"          // box -> boxes, bunch -> bunches
        }
        return word + "s"                // bag -> bags, can -> cans, jar -> jars
    }
}

// MARK: - Unit families / base conversion

extension MeasureUnit {
    /// Grams or millilitres per unit; `nil` for count/bunch (not convertible).
    var baseFactor: Double? {
        switch self {
        case .g, .ml:       return 1
        case .kg, .l:       return 1000
        case .unit, .bunch: return nil
        }
    }

    var family: MeasureFamily {
        switch self {
        case .g, .kg:  return .weight
        case .ml, .l:  return .volume
        case .unit:    return .count
        case .bunch:   return .bunch
        }
    }
}

extension NominalUnit {
    var baseFactor: Double {
        switch self {
        case .g, .ml: return 1
        case .kg, .l: return 1000
        }
    }

    var family: MeasureFamily {
        switch self {
        case .g, .kg: return .weight
        case .ml, .l: return .volume
        }
    }
}
