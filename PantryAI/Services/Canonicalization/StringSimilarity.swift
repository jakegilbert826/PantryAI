import Foundation

// MARK: - Fuzzy scoring (ADR-002a layer 4)
//
// Ranking primitives only — retrieval is handled by the trigram inverted index
// in `CanonicalIndex` (these scorers are O(len) and must never sweep the whole
// vocabulary). All scores are normalised to [0, 1], higher = closer.

enum StringSimilarity {

    /// Combined token-set + character similarity. Token overlap (Dice) catches
    /// reordering / extra words ("organic whole milk" ≈ "milk whole"); character
    /// similarity catches typos where no whole token matches ("chedar chese" ≈
    /// "cheddar cheese"). We lead with whichever signal is stronger so a clean
    /// typo isn't halved to nothing by a zero token overlap, and let the weaker
    /// signal nudge ties.
    static func score(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let token = tokenSetDice(a, b)
        let char = characterSimilarity(a, b)
        return 0.8 * max(token, char) + 0.2 * min(token, char)
    }

    /// Dice coefficient over whitespace tokens: 2·|A∩B| / (|A|+|B|).
    static func tokenSetDice(_ a: String, _ b: String) -> Double {
        let ta = Set(a.split(separator: " ").map(String.init))
        let tb = Set(b.split(separator: " ").map(String.init))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let inter = ta.intersection(tb).count
        return (2.0 * Double(inter)) / Double(ta.count + tb.count)
    }

    /// 1 − normalised Levenshtein distance.
    static func characterSimilarity(_ a: String, _ b: String) -> Double {
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1 }
        let dist = levenshtein(Array(a), Array(b))
        return 1.0 - Double(dist) / Double(maxLen)
    }

    /// Classic O(m·n) edit distance with a rolling two-row buffer.
    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1,        // deletion
                              curr[j - 1] + 1,    // insertion
                              prev[j - 1] + cost) // substitution
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
