import Foundation

// MARK: - Alias entry (mirrors the canonical_alias row, ADR-002a)

/// A learned or seeded mapping from a normalized surface form to a canonical PK.
/// Persisted in Supabase `canonical_alias`; synced into the index at boot.
struct AliasEntry: Hashable, Decodable {
    let rawNormalized: String
    let canonicalName: String
    var source: InflowSource?
    var count: Int
    var confidence: Double

    init(rawNormalized: String, canonicalName: String,
         source: InflowSource? = nil, count: Int = 1, confidence: Double = 0.95) {
        self.rawNormalized = rawNormalized
        self.canonicalName = canonicalName
        self.source = source
        self.count = count
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case rawNormalized = "raw_normalized"
        case canonicalName = "canonical_name"
        case source, count, confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawNormalized = try c.decode(String.self, forKey: .rawNormalized)
        canonicalName = try c.decode(String.self, forKey: .canonicalName)
        source = try c.decodeIfPresent(InflowSource.self, forKey: .source)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.95
    }
}

// MARK: - In-memory vocabulary index (ADR-002a)
//
// Built once after FoodReferenceService.prefetch(). Vocabulary is a few-thousand
// rows / <5 MB, so all three structures live in RAM and build in ms:
//   • lexical   — normalized canonical/display/plural (+ singular) → PK   (O(1))
//   • alias     — normalized surface form → AliasEntry                    (O(1))
//   • trigram   — trigram → set of PKs, for *bounded* fuzzy retrieval
// The hot path is pure and synchronous (ADR-002a speed design).

final class CanonicalIndex {

    private var references: [String: FoodReference] = [:]   // PK → reference
    private var lexical: [String: String] = [:]            // normalized key → PK (first wins)
    private var aliases: [String: AliasEntry] = [:]        // normalized form → alias
    private var trigrams: [String: Set<String>] = [:]      // trigram → PKs
    private var fuzzyText: [String: String] = [:]          // PK → representative normalized text

    /// Shared neutral normalizer for index keys (manual = base only, no
    /// source-specific preprocessing). Queries use their own source normalizer;
    /// the shared `base(_:)` keeps both sides comparable.
    private let normalizer = TextNormalizer(source: .manual)

    init(references: [FoodReference] = [], aliases: [AliasEntry] = []) {
        build(references: references, aliases: aliases)
    }

    // MARK: Build

    func build(references refs: [FoodReference], aliases aliasRows: [AliasEntry]) {
        references.removeAll(keepingCapacity: true)
        lexical.removeAll(keepingCapacity: true)
        aliases.removeAll(keepingCapacity: true)
        trigrams.removeAll(keepingCapacity: true)
        fuzzyText.removeAll(keepingCapacity: true)

        for ref in refs {
            references[ref.canonicalName] = ref
            registerLexical(ref)
            registerTrigrams(ref)
        }
        for alias in aliasRows { upsertAlias(alias) }
    }

    private func registerLexical(_ ref: FoodReference) {
        var keys = [ref.canonicalName, ref.displayName]
        if let plural = ref.pluralName { keys.append(plural) }
        for key in keys {
            let norm = normalizer.normalize(key)
            addLexical(norm, ref.canonicalName)
            addLexical(TextNormalizer.depluralize(norm), ref.canonicalName)
        }
    }

    private func addLexical(_ key: String, _ pk: String) {
        guard !key.isEmpty, lexical[key] == nil else { return }   // first wins
        lexical[key] = pk
    }

    private func registerTrigrams(_ ref: FoodReference) {
        // Score against the display name (richest human form), normalized.
        let text = normalizer.normalize(ref.displayName)
        fuzzyText[ref.canonicalName] = text
        for gram in Self.trigrams(of: text) {
            trigrams[gram, default: []].insert(ref.canonicalName)
        }
    }

    // MARK: Lookups (hot path — O(1) for layers 2–3)

    func reference(for canonical: String) -> FoodReference? { references[canonical] }

    func aliasMatch(_ normalized: String) -> AliasEntry? { aliases[normalized] }

    func lexicalMatch(_ normalized: String) -> String? { lexical[normalized] }

    /// Bounded fuzzy retrieval: gather PKs sharing trigrams with the query, rank
    /// the small candidate set by combined token/char similarity. Never sweeps
    /// the whole vocabulary.
    func fuzzyCandidates(_ normalized: String, limit: Int = 8) -> [(canonical: String, score: Double)] {
        guard !normalized.isEmpty else { return [] }
        let grams = Self.trigrams(of: normalized)
        guard !grams.isEmpty else { return [] }

        // 1. Retrieve: count trigram overlap per candidate PK.
        var overlap: [String: Int] = [:]
        for gram in grams {
            guard let pks = trigrams[gram] else { continue }
            for pk in pks { overlap[pk, default: 0] += 1 }
        }
        guard !overlap.isEmpty else { return [] }

        // 2. Rank a bounded shortlist (highest overlap first) by full similarity.
        let shortlist = overlap.sorted { $0.value > $1.value }.prefix(50)
        let scored = shortlist.compactMap { pk, _ -> (String, Double)? in
            guard let text = fuzzyText[pk] else { return nil }
            return (pk, StringSimilarity.score(normalized, text))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { (canonical: $0.0, score: $0.1) }
    }

    // MARK: Write-back (alias flywheel)

    /// Upsert an alias into both the alias hash and the trigram index so a
    /// correction is searchable immediately, without a rebuild.
    func upsertAlias(_ entry: AliasEntry) {
        let key = entry.rawNormalized
        guard !key.isEmpty else { return }
        if let existing = aliases[key] {
            aliases[key] = AliasEntry(
                rawNormalized: key,
                canonicalName: entry.canonicalName,
                source: entry.source ?? existing.source,
                count: existing.count + entry.count,
                confidence: max(existing.confidence, entry.confidence)
            )
        } else {
            aliases[key] = entry
        }
        // Make the alias surface form fuzzy-retrievable too (points at the PK's text).
        for gram in Self.trigrams(of: key) {
            trigrams[gram, default: []].insert(entry.canonicalName)
        }
    }

    var referenceCount: Int { references.count }
    var aliasCount: Int { aliases.count }

    // MARK: Trigrams

    /// Space-padded character trigrams. Padding gives prefix/suffix grams weight
    /// so "milk" and "milky" still overlap strongly.
    static func trigrams(of s: String) -> Set<String> {
        guard !s.isEmpty else { return [] }
        let padded = " " + s + " "
        let chars = Array(padded)
        guard chars.count >= 3 else { return [String(chars)] }
        var grams = Set<String>()
        for i in 0...(chars.count - 3) {
            grams.insert(String(chars[i..<(i + 3)]))
        }
        return grams
    }
}
