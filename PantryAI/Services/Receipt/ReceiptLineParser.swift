import Foundation

// MARK: - Receipt line parser (ADR-002 v1)
//
// Pure, deterministic, and OCR-engine-agnostic: it operates on recognised text
// lines, not images, so it is fully unit-testable. It does NOT assign identity —
// it filters receipt furniture (totals, payment, headers), then for each line it
// believes is an item it pulls out a clean name, an optional price, and a
// best-effort measure (net weight in canonical g/ml, or a multipack count).
// Downstream, `TextNormalizer(.receiptOCR)` expands merchant abbreviations and
// strips pack sizes before the canonicalization cascade resolves the PK.

enum ReceiptLineParser {

    /// Parse OCR lines (with confidence) into candidate items, in receipt order.
    static func parse(_ lines: [ReceiptOCRLine]) -> [ParsedReceiptLine] {
        itemWindow(of: lines).compactMap(parseLine)
    }

    /// Convenience for tests / plain text: assumes full OCR confidence.
    static func parse(_ texts: [String]) -> [ParsedReceiptLine] {
        parse(texts.map { ReceiptOCRLine(text: $0, confidence: 1.0) })
    }

    // MARK: - Single line

    private static func parseLine(_ line: ReceiptOCRLine) -> ParsedReceiptLine? {
        let raw = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isNoise(raw) else { return nil }

        // 1. Trailing price (end-anchored so a mid-line "2.27L" volume isn't a price).
        var working = raw
        let price = extractTrailingPrice(&working)

        // 2. Net weight (preferred measure) → canonical g/ml.
        var measureValue = 0.0
        var measureUnit: MeasureUnit = .unit
        if let weight = extractWeight(from: working) {
            measureValue = weight.value
            measureUnit = weight.unit
            working = weight.stripped
        }

        // 3. Multipack count, only when no explicit weight ("2 @ 0.85", "3 X").
        if measureValue == 0, let pack = extractMultipack(from: working) {
            measureValue = Double(pack.count)
            measureUnit = .unit
            working = pack.stripped
        }

        // 4. Clean the remaining text into a name.
        let name = cleanName(working)
        // Reject if too little signal, or if everything left is unit/filler words
        // ("NET@/kg" → "net kg" → all stopwords). A real item keeps a noun token.
        guard hasEnoughLetters(name), !isAllStopwords(name) else { return nil }

        // 5. Confidence: a trailing price is a strong "real line item" signal.
        var confidence = 0.5
        if price != nil { confidence += 0.2 }
        if measureValue > 0 { confidence += 0.05 }
        confidence = min(1.0, confidence * line.confidence)

        return ParsedReceiptLine(name: name, measureValue: measureValue,
                                 measureUnit: measureUnit, price: price,
                                 confidence: confidence)
    }

    // MARK: - Body-boundary anchoring (ADR-002 v1)
    //
    // A receipt is header → items → totals/footer. Per-line noise filtering catches
    // footer *keywords*, but a store name, slogan, or address in the header carries
    // no keyword and no price, so it leaks through as a phantom item; likewise a
    // post-total VAT summary ("STANDARD RATE GOODS 5.00") has letters + a price +
    // no keyword. So before per-line filtering we window the item body: drop
    // everything from the first totals line down (footer), and everything above the
    // first priced line (header). The per-line filter then runs only inside that
    // window. This is the heuristic every OSS receipt parser shares (knipknap et al).
    //
    // Known limitation: a produce item whose name sits on its own line *above* the
    // receipt's first price ("BANANAS" / "0.452kg @ 1.50/kg  0.68") loses the name
    // line to the header trim. We accept it — the header leak is otherwise
    // guaranteed on every scan, while a leading no-price item is rare and the user
    // can re-add it. When NO line carries a price we trim nothing, so the common
    // all-produce receipt is unaffected.
    // TODO(receipt-header): keep a leading name line adjacent to the first price.
    private static func itemWindow(of lines: [ReceiptOCRLine]) -> ArraySlice<ReceiptOCRLine> {
        let footerStart = lines.firstIndex { isTotalsMarker($0.text) } ?? lines.endIndex
        let header = lines[..<footerStart]
        let headerEnd = header.firstIndex { hasTrailingPrice($0.text) } ?? header.startIndex
        return lines[headerEnd..<footerStart]
    }

    /// Strong "the summary block starts here" markers — the end of the item list.
    /// Single-token forms; multi-word forms ("sub total", "amount due") below.
    private static let totalsMarkers: Set<String> = ["total", "subtotal", "balance"]

    private static func isTotalsMarker(_ line: String) -> Bool {
        let lower = line.lowercased()
        if matches(lower, #"\bsub\s*total\b"#) { return true }
        if matches(lower, #"\bamount\s+due\b"#) || matches(lower, #"\bto\s+pay\b"#) { return true }
        let tokens = lower.split { !$0.isLetter }.map(String.init)
        return tokens.contains { totalsMarkers.contains($0) }
    }

    private static func hasTrailingPrice(_ line: String) -> Bool {
        matches(line, trailingPricePattern)
    }

    // MARK: - Noise filtering

    /// Receipt furniture that is never a purchasable food item. Whole-token match
    /// (so "card" doesn't nuke a word that merely contains those letters).
    private static let noiseTokens: Set<String> = [
        "total", "subtotal", "balance", "change", "cash", "card", "visa",
        "mastercard", "debit", "credit", "contactless", "tender", "vat", "tax",
        "points", "clubcard", "nectar", "savings", "saved", "due", "amount",
        "receipt", "thank", "thanks", "store", "tel", "www", "http", "https",
        "reg", "till", "cashier", "items", "qty", "ltd", "plc", "returns",
        "refund", "void", "gbp", "eur", "usd", "auth", "terminal", "merchant",
        "account", "approved", "verified", "aid", "mid", "operator",
        // Tax-invoice / loyalty furniture (AU/UK/NZ).
        "invoice", "abn", "gst", "eftpos", "loyalty", "rewards", "fax",
    ]

    /// Soft stopwords: unit/quantity/promo words that are only "noise" when a line
    /// is composed *entirely* of them (e.g. "NET @ /kg", "PER KG", "SAVE 2.00").
    /// Never a hard drop — "SPECIAL K" keeps the noun token "k" and survives.
    private static let residualStopwords: Set<String> = [
        "net", "kg", "kgs", "g", "gm", "gms", "ml", "l", "ltr", "litre", "litres",
        "ea", "each", "per", "pk", "pack", "ct", "ctn", "qty", "unit", "units",
        "approx", "avg", "was", "now", "save", "special", "member", "price",
        "rrp", "incl", "excl", "wt", "weight", "value", "multi", "buy", "x",
    ]

    private static func isNoise(_ line: String) -> Bool {
        let lower = line.lowercased()
        // URLs / store domains ("woolworths.com", "www.tesco.com").
        if matches(lower, #"(?:https?://|www\.)"#) { return true }
        if matches(lower, #"[a-z0-9][a-z0-9-]*\.(?:com|net|org|co|io|gov|edu|au|uk|nz|ca|ie)\b"#) {
            return true
        }
        // Phone numbers / dates / pure-number rows.
        if matches(lower, #"^[\s\d\W]+$"#) { return true }                     // no letters at all
        if matches(lower, #"\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}"#) { return true }  // a date
        if matches(lower, #"\b\d{2}:\d{2}\b"#) { return true }                  // a time

        let tokens = lower.split { !$0.isLetter }.map(String.init)
        return tokens.contains { noiseTokens.contains($0) }
    }

    /// True when every letter-run in the cleaned name is a unit/filler stopword,
    /// so there is no actual food noun left.
    private static func isAllStopwords(_ name: String) -> Bool {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { residualStopwords.contains($0) }
    }

    // MARK: - Extraction

    /// Trailing line price, end-anchored so a mid-line "2.27L" volume isn't a price.
    /// e.g. "1.30", "£1.30", "1.30 A" (VAT code), "-0.50" (offer). Shared by the
    /// header-boundary probe (`hasTrailingPrice`) so the two can never drift.
    private static let trailingPricePattern = #"(?:[£$€])?\s?-?\d{1,4}[.,]\d{2}(?:\s?[A-Za-z])?\s*$"#

    private static func extractTrailingPrice(_ s: inout String) -> Double? {
        guard let range = s.range(of: trailingPricePattern, options: [.regularExpression]) else { return nil }
        let matchText = String(s[range])
        s.removeSubrange(range)
        let digits = matchText.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
            .replacingOccurrences(of: ",", with: ".")
        return Double(digits)
    }

    private struct Weight { let value: Double; let unit: MeasureUnit; let stripped: String }

    private static func extractWeight(from s: String) -> Weight? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s?(kg|g|ml|cl|l|lb|oz)\b"#
        guard let groups = firstMatch(in: s, pattern: pattern, caseInsensitive: true),
              groups.count >= 3,
              let amount = Double(groups[1].replacingOccurrences(of: ",", with: "."))
        else { return nil }

        let canonical: (Double, MeasureUnit)
        switch groups[2].lowercased() {
        case "kg": canonical = (amount * 1000, .g)
        case "g":  canonical = (amount, .g)
        case "l":  canonical = (amount * 1000, .ml)
        case "cl": canonical = (amount * 10, .ml)
        case "ml": canonical = (amount, .ml)
        case "lb": canonical = (amount * 453.592, .g)
        case "oz": canonical = (amount * 28.3495, .g)
        default:   return nil
        }
        let stripped = s.replacingOccurrences(of: groups[0], with: " ")
        return Weight(value: (canonical.0 * 100).rounded() / 100, unit: canonical.1, stripped: stripped)
    }

    private struct Multipack { let count: Int; let stripped: String }

    private static func extractMultipack(from s: String) -> Multipack? {
        // "2 @ 0.85", "3 X", "2 x", "4 for" — quantity at line start. `\b` only
        // attaches to the word alternative so non-word markers (@, *) still match.
        let pattern = #"^\s*(\d{1,2})\s*(?:[@x×*]|for\b)"#
        guard let groups = firstMatch(in: s, pattern: pattern, caseInsensitive: true),
              groups.count >= 2, let count = Int(groups[1]), count > 0
        else { return nil }
        let stripped = s.replacingOccurrences(of: groups[0], with: " ")
        return Multipack(count: count, stripped: stripped)
    }

    // MARK: - Name cleanup

    private static func cleanName(_ s: String) -> String {
        var name = s
        // Drop leading quantity integer ("2 MILK" → "MILK").
        name = name.replacingOccurrences(of: #"^\s*\d{1,2}\s+(?=[A-Za-z])"#,
                                         with: "", options: .regularExpression)
        // Drop standalone numbers and currency/VAT marker leftovers.
        name = name.replacingOccurrences(of: #"[£$€*]"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\b\d+(?:[.,]\d+)?\b"#, with: " ", options: .regularExpression)
        // Collapse whitespace.
        name = name.split { $0 == " " || $0 == "\t" }.joined(separator: " ")
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasEnoughLetters(_ s: String) -> Bool {
        s.filter(\.isLetter).count >= 2
    }

    // MARK: - Regex helpers

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: [.regularExpression]) != nil
    }

    /// Returns `[fullMatch, group1, group2, …]` for the first match, else `nil`.
    private static func firstMatch(in s: String, pattern: String,
                                   caseInsensitive: Bool = false) -> [String]? {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let match = regex.firstMatch(in: s, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            guard let r = Range(match.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
    }
}
