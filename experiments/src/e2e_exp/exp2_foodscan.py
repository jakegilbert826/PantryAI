"""
Whole-image multi-food extraction for exp_2 — LOCAL to this experiment.

exp_1's CanonicalizationService answers "given the text of ONE item, which
canonical food is it?" and returns a ranked candidate list for a single item.
This experiment asks a different question entirely: "given ALL the text in a
photo (no segmentation at all), which foods are present?" That is multi-label
extraction, not single-item resolution.

Rather than mutate the shared service, the aggregation lives here and reuses the
underlying alias -> lexical -> fuzzy cascade unchanged via
CanonicalizationService.resolve_top_n. Each text fragment votes for its best
canonical match; votes are aggregated into a set of distinct foods, gated by a
presence threshold.

A bounding-box prominence bias is available (`small_text_penalty`) but defaults
OFF at the call site. Unlike a single crop — where the tallest line is reliably
the product name — across a whole multi-item frame the tallest text is just one
item's name, or junk (on the test image it's a price string), so penalizing
smaller text discards every other item's legible label. Presence is therefore
gated on match quality alone unless a caller opts the bias back in.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Sequence

# Reuse the unmodified canonicalization package.
_SRC_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_SRC_ROOT / "canonicalization_service"))

from canonicalization import CanonicalizationService, InflowSource, LineInput  # noqa: E402
from constants import SMALL_TEXT_PENALTY                                       # noqa: E402


@dataclass
class FoodHit:
    """One distinct food the image's text is judged to mention."""
    canonical_name: str
    display_name: str
    score: float              # best prominence-weighted score across all evidence
    evidence: list[str] = field(default_factory=list)  # text fragments that matched


class FoodScanner:
    """Extracts a set of distinct foods from every OCR line of one image."""

    def __init__(self, canon: CanonicalizationService):
        self._canon = canon

    # ------------------------------------------------------------------ scoring

    @staticmethod
    def _prominence_factor(prominence: float, small_text_penalty: float) -> float:
        # Same shape as the per-line penalty in canonicalization.resolve_top_n_lines:
        # 1.0 for the tallest line, down to (1 - penalty) for vanishing text.
        return 1.0 - small_text_penalty * (1.0 - prominence)

    def _best(self, text: str, source: InflowSource):
        cands = self._canon.resolve_top_n(text, n=1, source=source)
        return cands[0] if cands else None

    def resolve_line(
        self,
        text: str,
        prominence: float,
        source: InflowSource = InflowSource.PANTRY_SCAN,
        small_text_penalty: float = SMALL_TEXT_PENALTY,
    ) -> Optional[tuple[str, str, float]]:
        """Best single-food guess for one fragment, prominence-weighted.

        Returns (canonical_name, display_name, weighted_score) or None. Used by
        the QA overlay to attribute each OCR box to the food it voted for.
        """
        c = self._best(text.strip(), source)
        if c is None:
            return None
        return c.canonical_name, c.display_name, c.score * self._prominence_factor(prominence, small_text_penalty)

    # ------------------------------------------------------------------ scan

    def scan(
        self,
        lines: Sequence[LineInput],
        source: InflowSource = InflowSource.PANTRY_SCAN,
        present_threshold: float = 0.6,
        small_text_penalty: float = SMALL_TEXT_PENALTY,
        max_join: int = 3,
        max_evidence: int = 4,
    ) -> list[FoodHit]:
        """Return the distinct foods the text mentions, ranked by confidence.

        Every line votes on its own, plus joins of adjacent lines in reading
        order (to catch names split across lines). A vote only registers a food
        if its prominence-weighted score clears `present_threshold`; the same
        food seen multiple times keeps its strongest score and accrues evidence.
        """
        items = [l for l in lines if l.text.strip()]
        hits: dict[str, FoodHit] = {}

        def vote(text: str, prominence: float) -> None:
            text = text.strip()
            if not text:
                return
            c = self._best(text, source)
            if c is None:
                return
            score = c.score * self._prominence_factor(prominence, small_text_penalty)
            if score < present_threshold:
                return
            h = hits.get(c.canonical_name)
            if h is None:
                hits[c.canonical_name] = FoodHit(c.canonical_name, c.display_name, score, [text])
            else:
                h.score = max(h.score, score)
                if text not in h.evidence and len(h.evidence) < max_evidence:
                    h.evidence.append(text)

        # 1. Each line on its own.
        for it in items:
            vote(it.text, it.prominence)

        # 2. Adjacent lines joined in reading order ("Black" + "Beans").
        if max_join >= 2:
            ordered = sorted(items, key=lambda l: l.order)
            for size in range(2, max_join + 1):
                for i in range(len(ordered) - size + 1):
                    window = ordered[i:i + size]
                    joined = " ".join(w.text for w in window)
                    mean_prominence = sum(w.prominence for w in window) / size
                    vote(joined, mean_prominence)

        return sorted(hits.values(), key=lambda h: h.score, reverse=True)