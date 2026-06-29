"""
Canonicalization service — Python port of Services/Canonicalization/ (Swift).

Mirrors the alias → lexical → fuzzy cascade exactly so experiment results
transfer directly to the app. Pull food_reference + canonical_alias from
Supabase once, then resolve synchronously with no I/O on the hot path.

Usage:
    from canonicalization import CanonicalizationService, InflowSource
    svc = CanonicalizationService.from_supabase()
    result = svc.resolve("heinz baked beans", source=InflowSource.PANTRY_SCAN)
    print(result.canonical_name, result.matched_via, result.confidence)

Requires:
    pip install supabase python-dotenv

Environment variables (or .env in project root):
    SUPABASE_URL
    SUPABASE_KEY
"""

from __future__ import annotations

import os
import unicodedata
from dataclasses import dataclass, field
from enum import Enum
from itertools import combinations
from typing import Optional

from constants import (
    ALIAS_DEFAULT_CONFIDENCE,
    AUTO_ACCEPT_CONFIDENCE,
    COARSE_TYPE_SCORE_BOOST,
    CORRECTION_ALIAS_CONFIDENCE,
    FUZZY_DEFAULT_CANDIDATE_LIMIT,
    FUZZY_MATCH_FLOOR,
    FUZZY_TRIGRAM_SHORTLIST_SIZE,
    MAX_COMBINE_LINES,
    MAX_COMBINE_SIZE,
    MAX_COMBINE_TOKENS,
    MERCHANT_ABBREVIATIONS,
    NON_ALPHANUMERIC_PATTERN,
    NUTRITION_LABEL_STOPWORDS,
    PACK_SIZE_PATTERNS,
    SMALL_TEXT_PENALTY,
    STORE_CODE_PATTERN,
    WHITESPACE_PATTERN,
)

# ---------------------------------------------------------------------------
# Types (mirrors CanonicalizationTypes.swift + InventoryCategory.swift)
# ---------------------------------------------------------------------------

class InflowSource(str, Enum):
    PANTRY_SCAN   = "pantryScan"
    BARCODE       = "barcode"
    RECEIPT_OCR   = "receiptOCR"
    EMAIL_RECEIPT = "emailReceipt"
    CHAT          = "chat"
    MANUAL        = "manual"

class MatchStage(str, Enum):
    BARCODE   = "barcode"
    ALIAS     = "alias"
    LEXICAL   = "lexical"
    FUZZY     = "fuzzy"
    EMBEDDING = "embedding"
    VLM       = "vlm"
    CONFIRMED = "confirmed"
    NONE      = "none"

class CoarseType(str, Enum):
    CAN     = "can"
    BOTTLE  = "bottle"
    JAR     = "jar"
    CARTON  = "carton"
    POUCH   = "pouch"
    BOX     = "box"
    BAG     = "bag"
    PUNNET  = "punnet"
    PRODUCE = "produce"

    # Maps CoarseType → compatible ContainerType raw values (mirrors Swift).
    _COMPATIBLE: dict  # populated below

    def compatible_containers(self) -> set[str]:
        return {
            CoarseType.CAN:     {"can"},
            CoarseType.BOTTLE:  {"bottle"},
            CoarseType.JAR:     {"jar"},
            CoarseType.CARTON:  {"carton"},
            CoarseType.POUCH:   {"bag"},
            CoarseType.BOX:     {"box"},
            CoarseType.BAG:     {"bag"},
            CoarseType.PUNNET:  {"punnet"},
            CoarseType.PRODUCE: set(),
        }[self]

    def is_compatible(self, ref: "FoodReference") -> bool:
        if self == CoarseType.PRODUCE:
            return ref.default_container_type is None and ref.default_packaging_category == "fresh"
        if ref.default_container_type is None and ref.default_packaging_category == "fresh":
            return False
        if ref.default_container_type is not None:
            return ref.default_container_type in self.compatible_containers()
        return True


@dataclass
class FoodReference:
    canonical_name: str
    display_name: str
    plural_name: Optional[str]
    default_packaging_category: str
    default_container_type: Optional[str]

    @classmethod
    def from_row(cls, row: dict) -> "FoodReference":
        return cls(
            canonical_name=row["canonical_name"],
            display_name=row["display_name"],
            plural_name=row.get("plural_name"),
            default_packaging_category=row.get("default_packaging_category", ""),
            default_container_type=row.get("default_container_type"),
        )


@dataclass
class AliasEntry:
    raw_normalized: str
    canonical_name: str
    confidence: float = ALIAS_DEFAULT_CONFIDENCE
    count: int = 1
    source: Optional[InflowSource] = None

    @classmethod
    def from_row(cls, row: dict) -> "AliasEntry":
        src = row.get("source")
        return cls(
            raw_normalized=row["raw_normalized"],
            canonical_name=row["canonical_name"],
            confidence=row.get("confidence", ALIAS_DEFAULT_CONFIDENCE),
            count=row.get("count", 1),
            source=InflowSource(src) if src else None,
        )


@dataclass
class Candidate:
    canonical_name: str
    display_name: str
    score: float


@dataclass
class LineInput:
    """One OCR line plus its normalized bounding-box prominence (0..1, where
    1.0 is the most prominent line in the crop). Feeds resolve_lines() so the
    cascade runs per line and the product name isn't diluted by fine print.

    `order` is the line's Vision reading-order index; it lets the recombination
    step join split names in reading order ("Black Beans", not "Beans Black")
    so the join can hit the lexical-exact path."""
    text: str
    prominence: float = 1.0
    order: int = 0


@dataclass
class CanonicalResolution:
    canonical_name: Optional[str]
    confidence: float
    candidates: list[Candidate]
    matched_via: MatchStage
    requires_confirmation: bool

    @classmethod
    def unresolved(
        cls,
        via: MatchStage = MatchStage.NONE,
        candidates: list[Candidate] | None = None,
    ) -> "CanonicalResolution":
        return cls(
            canonical_name=None,
            confidence=0.0,
            candidates=candidates or [],
            matched_via=via,
            requires_confirmation=True,
        )



# ---------------------------------------------------------------------------
# TextNormalizer (mirrors TextNormalizer.swift exactly)
# ---------------------------------------------------------------------------

def _strip_pack_size(s: str) -> str:
    for p in PACK_SIZE_PATTERNS:
        s = p.sub(" ", s)
    return s


def _strip_store_codes(s: str) -> str:
    return STORE_CODE_PATTERN.sub(" ", s)


def _expand_merchant_abbreviations(s: str) -> str:
    return " ".join(MERCHANT_ABBREVIATIONS.get(t.lower(), t) for t in s.split())


def _base_normalize(s: str) -> str:
    """Mirrors TextNormalizer.base(): lowercase → strip diacritics → strip pack
    sizes → keep [a-z0-9 ] → collapse whitespace."""
    # Strip diacritics (equivalent to .diacriticInsensitive folding)
    nfd = unicodedata.normalize("NFD", s)
    ascii_approx = nfd.encode("ascii", "ignore").decode("ascii")
    lowered = ascii_approx.lower()
    depacked = _strip_pack_size(lowered)
    cleaned = NON_ALPHANUMERIC_PATTERN.sub(" ", depacked)
    return WHITESPACE_PATTERN.sub(" ", cleaned).strip()


def _depluralize(phrase: str) -> str:
    """Mirrors TextNormalizer.depluralize() — conservative English rules only."""
    def _depluralize_word(w: str) -> str:
        if len(w) <= 3 or not w.endswith("s"):
            return w
        if w.endswith("ies"):
            return w[:-3] + "y"
        if w.endswith(("ches", "shes", "sses", "xes")):
            return w[:-2]
        if w.endswith("oes"):
            return w[:-2]
        if w.endswith("ss"):
            return w
        return w[:-1]
    return " ".join(_depluralize_word(t) for t in phrase.split())


def normalize(raw: str, source: InflowSource = InflowSource.MANUAL) -> str:
    if source in (InflowSource.RECEIPT_OCR, InflowSource.EMAIL_RECEIPT):
        raw = _strip_store_codes(_expand_merchant_abbreviations(raw))
    return _base_normalize(raw)


# ---------------------------------------------------------------------------
# Trigram helpers (mirrors CanonicalIndex.trigrams(of:))
# ---------------------------------------------------------------------------

def _trigrams(s: str) -> set[str]:
    """Space-padded character trigrams."""
    if not s:
        return set()
    padded = " " + s + " "
    if len(padded) < 3:
        return {padded}
    return {padded[i:i + 3] for i in range(len(padded) - 2)}


# ---------------------------------------------------------------------------
# StringSimilarity (mirrors StringSimilarity.swift exactly)
# ---------------------------------------------------------------------------

def _token_set_dice(a: str, b: str) -> float:
    ta, tb = set(a.split()), set(b.split())
    if not ta or not tb:
        return 0.0
    shared = ta & tb
    if not shared:
        return 0.0
    # Weight each token by character length: matching "capsicum" (8 chars)
    # is stronger evidence than matching "pp" (2 chars).
    shared_w = sum(len(t) for t in shared)
    total_w  = sum(len(t) for t in ta) + sum(len(t) for t in tb)
    return 2.0 * shared_w / total_w


def _levenshtein(a: str, b: str) -> int:
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    curr = [0] * (len(b) + 1)
    for i, ca in enumerate(a, 1):
        curr[0] = i
        for j, cb in enumerate(b, 1):
            cost = 0 if ca == cb else 1
            curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        prev, curr = curr, prev
    return prev[len(b)]


def _character_similarity(a: str, b: str) -> float:
    max_len = max(len(a), len(b))
    if max_len == 0:
        return 1.0
    return 1.0 - _levenshtein(a, b) / max_len


def similarity_score(a: str, b: str) -> float:
    """Mirrors StringSimilarity.score(): 0.8·max + 0.2·min of token/char signals."""
    if not a or not b:
        return 0.0
    token = _token_set_dice(a, b)
    char  = _character_similarity(a, b)
    return 0.8 * max(token, char) + 0.2 * min(token, char)


# ---------------------------------------------------------------------------
# CanonicalIndex (mirrors CanonicalIndex.swift)
# ---------------------------------------------------------------------------

class CanonicalIndex:
    def __init__(self, references: list[FoodReference], aliases: list[AliasEntry]):
        self._references: dict[str, FoodReference] = {}
        self._lexical:    dict[str, str]            = {}  # normalized key → PK
        self._aliases:    dict[str, AliasEntry]     = {}  # normalized form → alias
        self._trigrams:   dict[str, set[str]]       = {}  # trigram → PKs
        self._fuzzy_text: dict[str, str]            = {}  # PK → normalized display name
        self._build(references, aliases)

    def _build(self, refs: list[FoodReference], alias_rows: list[AliasEntry]) -> None:
        for ref in refs:
            self._references[ref.canonical_name] = ref
            self._register_lexical(ref)
            self._register_trigrams(ref)
        for alias in alias_rows:
            self.upsert_alias(alias)

    def _register_lexical(self, ref: FoodReference) -> None:
        keys = [ref.canonical_name, ref.display_name]
        if ref.plural_name:
            keys.append(ref.plural_name)
        for key in keys:
            norm = normalize(key)
            self._add_lexical(norm, ref.canonical_name)
            self._add_lexical(_depluralize(norm), ref.canonical_name)

    def _add_lexical(self, key: str, pk: str) -> None:
        if key and key not in self._lexical:
            self._lexical[key] = pk

    def _register_trigrams(self, ref: FoodReference) -> None:
        text = normalize(ref.display_name)
        self._fuzzy_text[ref.canonical_name] = text
        for gram in _trigrams(text):
            self._trigrams.setdefault(gram, set()).add(ref.canonical_name)

    def reference(self, canonical: str) -> Optional[FoodReference]:
        return self._references.get(canonical)

    def alias_match(self, normalized: str) -> Optional[AliasEntry]:
        return self._aliases.get(normalized)

    def lexical_match(self, normalized: str) -> Optional[str]:
        return self._lexical.get(normalized)

    def fuzzy_candidates(self, normalized: str, limit: int = FUZZY_DEFAULT_CANDIDATE_LIMIT) -> list[tuple[str, float]]:
        """Bounded trigram retrieval + full similarity scoring."""
        if not normalized:
            return []
        grams = _trigrams(normalized)
        if not grams:
            return []
        overlap: dict[str, int] = {}
        for gram in grams:
            for pk in self._trigrams.get(gram, set()):
                overlap[pk] = overlap.get(pk, 0) + 1
        if not overlap:
            return []
        shortlist = sorted(overlap, key=lambda pk: overlap[pk], reverse=True)[:FUZZY_TRIGRAM_SHORTLIST_SIZE]
        scored = [
            (pk, similarity_score(normalized, self._fuzzy_text[pk]))
            for pk in shortlist
            if pk in self._fuzzy_text
        ]
        return sorted(scored, key=lambda x: x[1], reverse=True)[:limit]

    def upsert_alias(self, entry: AliasEntry) -> None:
        key = entry.raw_normalized
        if not key:
            return
        existing = self._aliases.get(key)
        if existing:
            self._aliases[key] = AliasEntry(
                raw_normalized=key,
                canonical_name=entry.canonical_name,
                confidence=max(existing.confidence, entry.confidence),
                count=existing.count + entry.count,
                source=entry.source if entry.source is not None else existing.source,
            )
        else:
            self._aliases[key] = entry
        for gram in _trigrams(key):
            self._trigrams.setdefault(gram, set()).add(entry.canonical_name)

    @property
    def reference_count(self) -> int:
        return len(self._references)

    @property
    def alias_count(self) -> int:
        return len(self._aliases)

    @property
    def references(self) -> list["FoodReference"]:
        """All loaded food_reference rows (read-only view)."""
        return list(self._references.values())


# ---------------------------------------------------------------------------
# CanonicalizationService (mirrors CanonicalizationService.swift)
# ---------------------------------------------------------------------------

class CanonicalizationService:

    def __init__(self, index: CanonicalIndex):
        self._index = index

    @property
    def references(self) -> list[FoodReference]:
        """All loaded food_reference rows — the vocabulary an LLM fallback can
        resolve into. Read-only; mutating the list does not touch the index."""
        return self._index.references

    def resolve(
        self,
        raw_text: str,
        source: InflowSource = InflowSource.PANTRY_SCAN,
        coarse_type: Optional[CoarseType] = None,
        ocr_tokens: Optional[list[str]] = None,
        visual_class: Optional[str] = None,
        brand_hint: Optional[str] = None,
    ) -> CanonicalResolution:
        """Mirrors CanonicalizationService.resolve(_:)."""
        primary = self._primary_text(raw_text, ocr_tokens, brand_hint, visual_class)
        if not primary:
            return CanonicalResolution.unresolved()

        norm = normalize(primary, source)
        norm_singular = _depluralize(norm)
        if not norm:
            return CanonicalResolution.unresolved(via=MatchStage.NONE)

        # 2. Alias exact match — O(1)
        alias = self._index.alias_match(norm) or self._index.alias_match(norm_singular)
        if alias:
            return self._resolution(alias.canonical_name, alias.confidence, MatchStage.ALIAS)

        # 3. Lexical exact match — O(1)
        pk = self._index.lexical_match(norm) or self._index.lexical_match(norm_singular)
        if pk:
            return self._resolution(pk, 1.0, MatchStage.LEXICAL)

        # 4. Fuzzy — trigram retrieval + coarse-type rerank
        candidates = self._reranked_fuzzy_candidates(norm, coarse_type)
        if candidates and candidates[0].score >= FUZZY_MATCH_FLOOR:
            return CanonicalResolution(
                canonical_name=candidates[0].canonical_name,
                confidence=candidates[0].score,
                candidates=candidates,
                matched_via=MatchStage.FUZZY,
                requires_confirmation=True,
            )

        # 5. Embedding — not built.

        # 6. HITL
        return CanonicalResolution.unresolved(via=MatchStage.NONE, candidates=candidates)

    def resolve_top_n(
        self,
        raw_text: str,
        n: int = 5,
        source: InflowSource = InflowSource.PANTRY_SCAN,
        coarse_type: Optional[CoarseType] = None,
        ocr_tokens: Optional[list[str]] = None,
        visual_class: Optional[str] = None,
        brand_hint: Optional[str] = None,
    ) -> list[Candidate]:
        """Return the top N candidates sorted by confidence descending.

        Runs the same alias → lexical → fuzzy cascade as resolve() but collects
        candidates from every stage rather than short-circuiting, so callers
        always see the full ranked list up to N entries.
        """
        primary = self._primary_text(raw_text, ocr_tokens, brand_hint, visual_class)
        if not primary:
            return []

        norm = normalize(primary, source)
        norm_singular = _depluralize(norm)
        if not norm:
            return []

        seen: dict[str, Candidate] = {}

        def _upsert(canonical: str, display: str, score: float) -> None:
            if canonical not in seen or seen[canonical].score < score:
                seen[canonical] = Candidate(canonical, display, score)

        alias = self._index.alias_match(norm) or self._index.alias_match(norm_singular)
        if alias:
            ref = self._index.reference(alias.canonical_name)
            display = ref.display_name if ref else alias.canonical_name
            _upsert(alias.canonical_name, display, alias.confidence)

        pk = self._index.lexical_match(norm) or self._index.lexical_match(norm_singular)
        if pk:
            ref = self._index.reference(pk)
            display = ref.display_name if ref else pk
            _upsert(pk, display, 1.0)

        fuzzy_limit = max(n * 3, 20)
        for canonical, score in self._index.fuzzy_candidates(norm, limit=fuzzy_limit):
            ref = self._index.reference(canonical)
            if ref is None:
                continue
            if coarse_type is not None:
                if not coarse_type.is_compatible(ref):
                    continue
                score = min(1.0, score + COARSE_TYPE_SCORE_BOOST)
            _upsert(canonical, ref.display_name, score)

        return sorted(seen.values(), key=lambda c: c.score, reverse=True)[:n]

    def print_top_n(
            self,
            raw_text: str,
            n: int = 5,
            source: InflowSource = InflowSource.PANTRY_SCAN,
            coarse_type: Optional[CoarseType] = None,
            ocr_tokens: Optional[list[str]] = None,
            visual_class: Optional[str] = None,
            brand_hint: Optional[str] = None,
    ) -> None:
        candidates = self.resolve_top_n(raw_text, n, source, coarse_type, ocr_tokens, visual_class, brand_hint)
        for c in candidates:
            print(c.canonical_name, c.score)

    # ------------------------------------------------------------------
    # Per-line resolution (prominence-weighted) — fixes the blob-Dice problem
    # ------------------------------------------------------------------

    def resolve_top_n_lines(
        self,
        lines: list[LineInput] | list[str],
        n: int = 5,
        source: InflowSource = InflowSource.PANTRY_SCAN,
        coarse_type: Optional[CoarseType] = None,
        small_text_penalty: float = SMALL_TEXT_PENALTY,
        max_combine_lines: int = MAX_COMBINE_LINES,
        max_combine_size: int = MAX_COMBINE_SIZE,
    ) -> list[Candidate]:
        """Resolve each OCR line independently, then merge into one ranked list.

        Running the cascade per line keeps the token-set-Dice denominator small
        (a line, not the whole label), so a true match like "corn ker" no longer
        gets buried under the nutrition panel. Each line's candidate scores are
        scaled by a prominence factor so the largest text (usually the product
        name) dominates; `small_text_penalty` tunes how aggressive that bias is.

        Names split across lines ("Black" / "Beans") are recovered by also
        resolving *joins* of the top-`max_combine_lines` prominent lines, in
        subsets up to `max_combine_size`, in reading order. This is bounded to a
        small constant (independent of how many lines OCR returns), so it stays
        cheap on-device. `max_combine_lines <= 1` disables recombination.
        """
        # Normalize inputs to LineInput so singles and joins share order/prominence.
        items: list[LineInput] = []
        for i, line in enumerate(lines):
            if isinstance(line, LineInput):
                text, prominence, order = line.text, line.prominence, line.order
            else:
                text, prominence, order = line, 1.0, i
            if text and text.strip():
                items.append(LineInput(text.strip(), prominence, order))

        seen: dict[str, Candidate] = {}
        resolved: set[str] = set()  # dedup identical queries by normalized form

        def _add_query(text: str, prominence: float) -> None:
            key = normalize(text, source)
            if not key:
                return
            # Strip nutrition-label stopwords and bare numbers, then drop the
            # query if fewer than 3 non-whitespace characters remain. This
            # prevents tokens like "per" (from "per 100g" after pack-size
            # stripping) from producing spurious fuzzy matches (e.g. "pear").
            tokens = key.split()
            cleaned_tokens = [t for t in tokens if t not in NUTRITION_LABEL_STOPWORDS and not t.isdigit()]
            cleaned_key = " ".join(cleaned_tokens)
            if len(cleaned_key.replace(" ", "")) < 3:
                return
            if cleaned_key in resolved:
                return
            resolved.add(cleaned_key)
            factor = 1.0 - small_text_penalty * (1.0 - prominence)
            for c in self.resolve_top_n(cleaned_key, n, source, coarse_type):
                weighted = c.score * factor
                existing = seen.get(c.canonical_name)
                if existing is None or existing.score < weighted:
                    seen[c.canonical_name] = Candidate(c.canonical_name, c.display_name, weighted)

        # 1. Singles — every line, prominence-penalized (never excluded).
        for it in items:
            _add_query(it.text, it.prominence)

        # 2. Joins — only the top-K prominent lines, subsets of size 2..C.
        if max_combine_lines >= 2 and len(items) >= 2:
            top = sorted(items, key=lambda it: it.prominence, reverse=True)[:max_combine_lines]
            for size in range(2, min(max_combine_size, len(top)) + 1):
                for subset in combinations(top, size):
                    ordered = sorted(subset, key=lambda it: it.order)
                    joined = " ".join(it.text for it in ordered)
                    if len(normalize(joined, source).split()) > MAX_COMBINE_TOKENS:
                        continue
                    mean_prominence = sum(it.prominence for it in subset) / len(subset)
                    _add_query(joined, mean_prominence)

        return sorted(seen.values(), key=lambda c: c.score, reverse=True)[:n]

    def resolve_lines(
        self,
        lines: list[LineInput] | list[str],
        source: InflowSource = InflowSource.PANTRY_SCAN,
        coarse_type: Optional[CoarseType] = None,
        small_text_penalty: float = SMALL_TEXT_PENALTY,
        max_combine_lines: int = MAX_COMBINE_LINES,
        max_combine_size: int = MAX_COMBINE_SIZE,
    ) -> CanonicalResolution:
        """Per-line analogue of resolve(): returns the best prominence-weighted
        match across all OCR lines, gated by the same fuzzy floor."""
        candidates = self.resolve_top_n_lines(
            lines,
            n=FUZZY_DEFAULT_CANDIDATE_LIMIT,
            source=source,
            coarse_type=coarse_type,
            small_text_penalty=small_text_penalty,
            max_combine_lines=max_combine_lines,
            max_combine_size=max_combine_size,
        )
        if candidates and candidates[0].score >= FUZZY_MATCH_FLOOR:
            top = candidates[0]
            return CanonicalResolution(
                canonical_name=top.canonical_name,
                confidence=top.score,
                candidates=candidates,
                matched_via=MatchStage.FUZZY,
                requires_confirmation=top.score < AUTO_ACCEPT_CONFIDENCE,
            )
        return CanonicalResolution.unresolved(via=MatchStage.NONE, candidates=candidates)

    def print_top_n_lines(
        self,
        lines: list[LineInput] | list[str],
        n: int = 5,
        source: InflowSource = InflowSource.PANTRY_SCAN,
        coarse_type: Optional[CoarseType] = None,
        small_text_penalty: float = SMALL_TEXT_PENALTY,
        max_combine_lines: int = MAX_COMBINE_LINES,
        max_combine_size: int = MAX_COMBINE_SIZE,
    ) -> None:
        candidates = self.resolve_top_n_lines(
            lines, n, source, coarse_type, small_text_penalty,
            max_combine_lines, max_combine_size,
        )
        for c in candidates:
            print(c.canonical_name, round(c.score, 3))

    def record_correction(
        self,
        raw_text: str,
        source: InflowSource,
        canonical_name: str,
    ) -> AliasEntry:
        """Mirrors CanonicalizationService.recordCorrection(). Updates the local
        index immediately; callers may also persist the returned entry to Supabase."""
        norm = normalize(raw_text, source)
        entry = AliasEntry(
            raw_normalized=norm,
            canonical_name=canonical_name,
            confidence=CORRECTION_ALIAS_CONFIDENCE,
            count=1,
            source=source,
        )
        self._index.upsert_alias(entry)
        return entry

    # ------------------------------------------------------------------

    def _primary_text(
        self,
        raw_text: Optional[str],
        ocr_tokens: Optional[list[str]],
        brand_hint: Optional[str],
        visual_class: Optional[str],
    ) -> Optional[str]:
        if raw_text and raw_text.strip():
            return raw_text.strip()
        if ocr_tokens:
            joined = " ".join(ocr_tokens).strip()
            if joined:
                return joined
        if brand_hint and brand_hint.strip():
            return brand_hint.strip()
        if visual_class and visual_class.strip():
            return visual_class.strip()
        return None

    def _resolution(self, canonical: str, confidence: float, via: MatchStage) -> CanonicalResolution:
        ref = self._index.reference(canonical)
        display = ref.display_name if ref else canonical
        return CanonicalResolution(
            canonical_name=canonical,
            confidence=confidence,
            candidates=[Candidate(canonical, display, confidence)],
            matched_via=via,
            requires_confirmation=confidence < AUTO_ACCEPT_CONFIDENCE,
        )

    def _reranked_fuzzy_candidates(
        self,
        norm: str,
        coarse_type: Optional[CoarseType],
    ) -> list[Candidate]:
        raw = self._index.fuzzy_candidates(norm)
        candidates: list[Candidate] = []
        for canonical, score in raw:
            ref = self._index.reference(canonical)
            if ref is None:
                continue
            if coarse_type is not None:
                if not coarse_type.is_compatible(ref):
                    continue
                score = min(1.0, score + COARSE_TYPE_SCORE_BOOST)
            candidates.append(Candidate(canonical, ref.display_name, score))
        return sorted(candidates, key=lambda c: c.score, reverse=True)

    # ------------------------------------------------------------------
    # Factory — pull live data from Supabase
    # ------------------------------------------------------------------

    @classmethod
    def from_supabase(cls) -> "CanonicalizationService":
        """
        Fetch food_reference + canonical_alias from Supabase and build the
        index. Reads SUPABASE_URL and SUPABASE_KEY from the environment (or
        a .env file loaded before calling this).
        """
        try:
            from supabase import create_client
        except ImportError:
            raise ImportError("pip install supabase")

        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_KEY"]
        client = create_client(url, key)

        ref_rows   = client.table("food_reference").select("*").execute().data
        alias_rows = client.table("canonical_alias").select("*").execute().data

        references = [FoodReference.from_row(r) for r in ref_rows]
        aliases    = [AliasEntry.from_row(r)    for r in alias_rows]

        print(f"[canonicalization] loaded {len(references)} references, {len(aliases)} aliases")
        index = CanonicalIndex(references, aliases)
        return cls(index)
