import Foundation

// MARK: - Canonicalization contract (ADR-002a)
//
// Evidence-bundle in → ranked resolution out. Per-source front-ends fill the
// query fields they have; the shared cascade core never branches on `source`.
// A new inflow stream is a new front-end (normalizer), never a core change.

/// The inflow stream a query originates from. Used only to pick the right
/// `TextNormalizer` front-end and to stamp alias provenance — the cascade core
/// is identical across sources.
enum InflowSource: String, Codable, Hashable {
    case pantryScan, barcode, receiptOCR, emailReceipt, chat, manual
}

/// Coarse visual shape from the YOLO detector. Used by the coarse-type rerank
/// to break fuzzy ties and veto shape-impossible matches (a "can" box never
/// resolves to a loose banana). Maps against `FoodReference.defaultContainerType`
/// / `defaultPackagingCategory` — no schema change.
enum CoarseType: String, Codable, Hashable {
    case can, bottle, jar, carton, pouch, box, bag, punnet, produce

    /// `ContainerType`s this shape is consistent with. `.produce` is container-less.
    var compatibleContainers: Set<ContainerType> {
        switch self {
        case .can:     return [.can]
        case .bottle:  return [.bottle]
        case .jar:     return [.jar]
        case .carton:  return [.carton]
        case .pouch:   return [.bag]
        case .box:     return [.box]
        case .bag:     return [.bag]
        case .punnet:  return [.punnet]
        case .produce: return []
        }
    }

    /// Conservative veto: only returns `false` when the shape makes the reference
    /// impossible. Unknown container info never vetoes (we don't rule out what we
    /// can't see).
    func isCompatible(with ref: FoodReference) -> Bool {
        switch self {
        case .produce:
            // Loose produce: only fresh, container-less references qualify.
            return ref.defaultContainerType == nil && ref.defaultPackagingCategory == .fresh
        default:
            // A container shape can't be loose fresh produce.
            if ref.defaultContainerType == nil && ref.defaultPackagingCategory == .fresh {
                return false
            }
            // If the reference declares a container, it must be a compatible shape.
            if let container = ref.defaultContainerType {
                return compatibleContainers.contains(container)
            }
            // No declared container → can't rule it out.
            return true
        }
    }
}

/// A parsed amount in canonical units (g/ml) or a count, honouring the app's
/// canonical-unit invariant. Front-ends pass a parsed net pack size here.
struct Measure: Hashable {
    var value: Double
    var unit: MeasureUnit
}

/// Which cascade layer produced a resolution. `.none` = nothing matched.
enum MatchStage: String, Codable, Hashable {
    case barcode, alias, lexical, fuzzy, embedding, vlm, none

    /// A human-confirmed resolution (HITL pick). Distinct from automatic stages.
    case confirmed
}

/// A ranked candidate offered to the human-in-the-loop picker.
struct Candidate: Identifiable, Hashable {
    var id: String { canonicalName }
    let canonicalName: String
    let displayName: String
    let score: Double
}

/// Evidence bundle. Front-ends fill the fields they have; everything is optional
/// except `source`.
struct CanonicalizationQuery {
    var source: InflowSource
    var rawText: String?            // chat phrase / product name
    var ocrTokens: [String]?        // label or receipt tokens
    var barcode: String?            // decoded EAN/UPC
    var coarseType: CoarseType?     // YOLO coarse shape
    var visualClass: String?        // produce classifier label
    var brandHint: String?
    var packSize: Measure?          // parsed net weight/volume (canonical g/ml)

    init(
        source: InflowSource,
        rawText: String? = nil,
        ocrTokens: [String]? = nil,
        barcode: String? = nil,
        coarseType: CoarseType? = nil,
        visualClass: String? = nil,
        brandHint: String? = nil,
        packSize: Measure? = nil
    ) {
        self.source = source
        self.rawText = rawText
        self.ocrTokens = ocrTokens
        self.barcode = barcode
        self.coarseType = coarseType
        self.visualClass = visualClass
        self.brandHint = brandHint
        self.packSize = packSize
    }

    /// The best free-text signal available, in priority order. `nil` when the
    /// bundle carries only a barcode (→ HITL until the product DB lands).
    var primaryText: String? {
        if let t = rawText?.trimmedNonEmpty { return t }
        if let tokens = ocrTokens, !tokens.isEmpty {
            let joined = tokens.joined(separator: " ").trimmedNonEmpty
            if joined != nil { return joined }
        }
        if let b = brandHint?.trimmedNonEmpty { return b }
        if let v = visualClass?.trimmedNonEmpty { return v }
        return nil
    }
}

/// Ranked resolution out. `canonicalName` is a real `food_reference` PK or `nil`.
struct CanonicalResolution: Hashable {
    let canonicalName: String?
    let confidence: Double
    let candidates: [Candidate]
    let matchedVia: MatchStage
    var requiresConfirmation: Bool

    /// Nothing resolved — route to HITL, offering whatever candidates we found.
    static func unresolved(via: MatchStage = .none, candidates: [Candidate] = []) -> CanonicalResolution {
        CanonicalResolution(
            canonicalName: nil,
            confidence: 0,
            candidates: candidates,
            matchedVia: via,
            requiresConfirmation: true
        )
    }
}

// MARK: - Helpers

extension String {
    /// Trimmed, or `nil` if empty after trimming.
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
