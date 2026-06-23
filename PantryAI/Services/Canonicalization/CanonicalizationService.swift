import Foundation

// MARK: - Thresholds (ADR-002a — biased toward HITL)

/// Conservative by decision #6: prefer asking the user over silently accepting a
/// fuzzy guess. Fuzzy never auto-writes a PK regardless of score (see the §Caveat
/// — fuzzy was torn out once before).
struct CanonicalizationThresholds {
    /// Minimum fuzzy similarity to even *offer* a candidate as the top suggestion.
    var fuzzyFloor: Double = 0.55
    /// At/above this, a match is trusted enough to skip confirmation. Realistically
    /// only deterministic stages (alias/lexical) clear it.
    var autoAccept: Double = 0.995

    static let `default` = CanonicalizationThresholds()
}

// MARK: - Canonicalization service (ADR-002a)
//
// evidence-bundle in → ranked resolution out. One shared cascade, cheapest +
// most precise first, early-exit. Pure / synchronous hot path: no I/O, no
// network — the alias + vocabulary indices are pre-synced. Front-ends fill the
// query fields they have; this core never branches on `source`.

final class CanonicalizationService {

    private let index: CanonicalIndex
    private let thresholds: CanonicalizationThresholds

    init(index: CanonicalIndex, thresholds: CanonicalizationThresholds = .default) {
        self.index = index
        self.thresholds = thresholds
    }

    /// Resolve one already-segmented item (chat segmentation lives upstream in the
    /// NL router, ADR-003). Synchronous and allocation-light — safe to run a whole
    /// shelf of crops through concurrently.
    func resolve(_ query: CanonicalizationQuery) -> CanonicalResolution {
        let normalizer = TextNormalizer(source: query.source)

        // 1. barcode → product DB — STUBBED this pass. The deterministic layer is
        //    kept; until the OFF subset lands a barcode-only bundle routes to HITL.
        //    (We still fall through to the text layers if any text is present.)

        guard let primary = query.primaryText else {
            // Only a barcode (or nothing) — nothing to match on yet.
            return .unresolved(via: query.barcode != nil ? .barcode : .none)
        }

        let norm = normalizer.normalize(primary)
        let normSingular = TextNormalizer.depluralize(norm)
        guard !norm.isEmpty else { return .unresolved(via: .none) }

        // 2. alias exact — O(1). Seeded + learned corrections.
        if let alias = index.aliasMatch(norm) ?? index.aliasMatch(normSingular) {
            return resolution(canonical: alias.canonicalName,
                              confidence: alias.confidence,
                              via: .alias)
        }

        // 3. lexical exact — O(1) on canonical / display / plural / singular.
        if let pk = index.lexicalMatch(norm) ?? index.lexicalMatch(normSingular) {
            return resolution(canonical: pk, confidence: 1.0, via: .lexical)
        }

        // 4. fuzzy — bounded trigram retrieval, coarse-type rerank, then rank.
        //    Fuzzy NEVER auto-writes: every fuzzy resolution requires confirmation.
        let candidates = rerankedFuzzyCandidates(norm, coarseType: query.coarseType)
        if let top = candidates.first, top.score >= thresholds.fuzzyFloor {
            return CanonicalResolution(
                canonicalName: top.canonicalName,
                confidence: top.score,
                candidates: candidates,
                matchedVia: .fuzzy,
                requiresConfirmation: true   // by decision #6 / the Caveat
            )
        }

        // 5. embedding ANN — slot reserved (ADR-002 v3), not built.

        // 6. HITL — nothing cleared the floor; still offer the best candidates so
        //    the picker shows "We think this is X — confirm / pick / other".
        return .unresolved(via: .none, candidates: candidates)
    }

    /// Record a human confirmation/correction → an alias to persist and index.
    /// The caller (step 2) writes the returned entry to Supabase and syncs it.
    @discardableResult
    func recordCorrection(rawText: String, source: InflowSource, canonicalName: String) -> AliasEntry {
        let norm = TextNormalizer(source: source).normalize(rawText)
        let entry = AliasEntry(rawNormalized: norm, canonicalName: canonicalName,
                               source: source, count: 1, confidence: 0.97)
        index.upsertAlias(entry)
        return entry
    }

    // MARK: - Shared instance / bootstrap

    /// The app-wide resolver, available once `bootstrap()` completes. Hot-path
    /// callers are on the main actor (e.g. `ScanViewModel`), so the instance is
    /// main-actor isolated — no locking needed around the index.
    @MainActor private(set) static var shared: CanonicalizationService?

    /// Build the index once at launch: prefetch references, pull aliases, fold
    /// both into a `CanonicalIndex`. Safe to call before the network is warm —
    /// an empty/partial index degrades gracefully (lexical/fuzzy still work).
    @MainActor
    static func bootstrap() async {
        await FoodReferenceService.shared.prefetch()
        let refs = await FoodReferenceService.shared.allReferences()
        let aliases = await CanonicalAliasService.shared.fetchAll()
        shared = CanonicalizationService(index: CanonicalIndex(references: refs, aliases: aliases))
    }

    // MARK: - Internals

    private func resolution(canonical: String, confidence: Double, via: MatchStage) -> CanonicalResolution {
        let display = index.reference(for: canonical)?.displayName ?? canonical
        return CanonicalResolution(
            canonicalName: canonical,
            confidence: confidence,
            candidates: [Candidate(canonicalName: canonical, displayName: display, score: confidence)],
            matchedVia: via,
            requiresConfirmation: confidence < thresholds.autoAccept
        )
    }

    /// Fuzzy retrieval + coarse-type rerank: veto shape-impossible references and
    /// give a small boost to shape-consistent ones, so a "can" never wins as a
    /// banana and ties break toward the right container (ADR-002a).
    private func rerankedFuzzyCandidates(_ norm: String, coarseType: CoarseType?) -> [Candidate] {
        let raw = index.fuzzyCandidates(norm)
        let adjusted: [Candidate] = raw.compactMap { hit in
            guard let ref = index.reference(for: hit.canonical) else { return nil }
            var score = hit.score
            if let coarse = coarseType {
                guard coarse.isCompatible(with: ref) else { return nil }   // veto
                score = min(1.0, score + 0.05)                             // consistency boost
            }
            return Candidate(canonicalName: hit.canonical, displayName: ref.displayName, score: score)
        }
        return adjusted.sorted { $0.score > $1.score }
    }
}
