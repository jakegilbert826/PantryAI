import Foundation

// MARK: - Per-source normalization front-ends (ADR-002a)
//
// Every stream converges on one vocabulary index, so the *base* normalization
// must be byte-identical across sources — index keys and queries both run
// through `base(_:)`. Source variants only add preprocessing *before* base
// (merchant-abbrev expansion, store-code stripping, …). De-pluralization is
// exposed separately so the index and the query can each register both the
// raw and singular forms.

struct TextNormalizer {
    let source: InflowSource

    /// Canonical normalized form used for hash lookups and trigram indexing.
    func normalize(_ raw: String) -> String {
        Self.base(Self.preprocess(raw, for: source))
    }

    /// Normalize a token stream (OCR / receipt) into one string.
    func normalize(tokens: [String]) -> String {
        normalize(tokens.joined(separator: " "))
    }

    // MARK: Source preprocessing

    private static func preprocess(_ raw: String, for source: InflowSource) -> String {
        switch source {
        case .receiptOCR, .emailReceipt:
            return stripStoreCodes(expandMerchantAbbreviations(raw))
        case .pantryScan, .barcode, .chat, .manual:
            return raw
        }
    }

    // MARK: Base normalization (shared by index + every query)

    /// lowercase → strip diacritics → drop pack-size tokens → keep [a-z0-9 ] →
    /// collapse whitespace. Deterministic and idempotent.
    static func base(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let depacked = stripPackSize(folded)
        let scalars = depacked.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " "
        }
        let cleaned = String(scalars).lowercased()
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    /// English de-pluralization. Conservative: leaves short words (≤3 chars) and
    /// non-`s` endings alone.
    static func depluralize(_ phrase: String) -> String {
        phrase.split(separator: " ").map { token -> String in
            let w = String(token)
            guard w.count > 3, w.hasSuffix("s") else { return w }
            if w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }     // berries → berry
            if w.hasSuffix("ches") || w.hasSuffix("shes")
                || w.hasSuffix("sses") || w.hasSuffix("xes") {
                return String(w.dropLast(2))                                  // boxes → box
            }
            if w.hasSuffix("oes") { return String(w.dropLast(2)) }            // tomatoes → tomato
            if w.hasSuffix("ss") { return w }                                 // glass → glass
            return String(w.dropLast())                                       // bananas → banana
        }.joined(separator: " ")
    }

    // MARK: Pack-size / store-code stripping

    /// Drops standalone net-weight / multipack tokens ("400g", "1.5 l", "2x",
    /// "500 ml", "6pk") so "heinz baked beans 400g" → "heinz baked beans".
    static func stripPackSize(_ s: String) -> String {
        var out = s
        let patterns = [
            #"\b\d+(?:[.,]\d+)?\s?(?:kg|g|ml|cl|l|oz|lb|ct|pk|pack)\b"#, // 400g, 1.5 l, 6pk
            #"\b\d+\s?[x×]\s?\d*\b"#,                                    // 2x, 4 x 250
            #"\b[x×]\s?\d+\b"#                                            // x6
        ]
        for p in patterns {
            out = out.replacingOccurrences(
                of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

    /// Strips leading/trailing numeric store codes ("0054 MILK" → "MILK").
    static func stripStoreCodes(_ s: String) -> String {
        s.replacingOccurrences(of: #"(?:^|\s)\d{3,}(?:\s|$)"#,
                               with: " ", options: .regularExpression)
    }

    /// Cryptic receipt/merchant abbreviation expansion. Whole-token only.
    static func expandMerchantAbbreviations(_ s: String) -> String {
        let map = [
            "chkn": "chicken", "chk": "chicken", "bf": "beef", "prk": "pork",
            "tom": "tomato", "toms": "tomatoes", "veg": "vegetable",
            "org": "organic", "orgnc": "organic", "whl": "whole", "wht": "white",
            "brwn": "brown", "swt": "sweet", "ched": "cheddar", "chs": "cheese",
            "yog": "yogurt", "yghrt": "yogurt", "btr": "butter", "mlk": "milk",
            "bnna": "banana", "ban": "banana", "appl": "apple", "ptto": "potato"
        ]
        let expanded = s.split(separator: " ").map { token -> String in
            let key = token.lowercased()
            return map[key] ?? String(token)
        }
        return expanded.joined(separator: " ")
    }
}
