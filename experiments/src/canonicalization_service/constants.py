"""
Tunable constants for the canonicalization pipeline.

Edit this file to adjust matching thresholds, text-normalization patterns,
and fuzzy-search sizes without touching the resolver logic.
"""

import re

# ---------------------------------------------------------------------------
# Text normalization — regex patterns
# ---------------------------------------------------------------------------

PACK_SIZE_PATTERNS = [
    re.compile(r"\b\d+(?:[.,]\d+)?\s?(?:kg|g|ml|cl|l|oz|lb|ct|pk|pack)\b", re.IGNORECASE),
    re.compile(r"\b\d+\s?[x×]\s?\d*\b", re.IGNORECASE),
    re.compile(r"\b[x×]\s?\d+\b", re.IGNORECASE),
]
STORE_CODE_PATTERN       = re.compile(r"(?:^|\s)\d{3,}(?:\s|$)")
NON_ALPHANUMERIC_PATTERN = re.compile(r"[^a-z0-9 ]")
WHITESPACE_PATTERN       = re.compile(r"\s+")

# ---------------------------------------------------------------------------
# Text normalization — merchant abbreviation expansion (receipt OCR / email)
# ---------------------------------------------------------------------------

MERCHANT_ABBREVIATIONS: dict[str, str] = {
    "chkn": "chicken", "chk": "chicken", "bf": "beef",    "prk": "pork",
    "tom":  "tomato",  "toms": "tomatoes", "veg": "vegetable",
    "org":  "organic", "orgnc": "organic", "whl": "whole", "wht": "white",
    "brwn": "brown",   "swt":  "sweet",   "ched": "cheddar", "chs": "cheese",
    "yog":  "yogurt",  "yghrt": "yogurt", "btr": "butter",  "mlk": "milk",
    "bnna": "banana",  "ban":  "banana",  "appl": "apple",  "ptto": "potato",
}

# ---------------------------------------------------------------------------
# Alias confidence values
# ---------------------------------------------------------------------------

ALIAS_DEFAULT_CONFIDENCE    = 0.95  # default confidence for alias table entries
CORRECTION_ALIAS_CONFIDENCE = 0.97  # confidence assigned when a user correction is recorded

# ---------------------------------------------------------------------------
# Match thresholds
# ---------------------------------------------------------------------------

# FUZZY_MATCH_FLOOR      = 0.55   # original
FUZZY_MATCH_FLOOR      = 0.3   # minimum fuzzy score required to surface a candidate
AUTO_ACCEPT_CONFIDENCE = 0.995  # above this score, no human confirmation is needed

# ---------------------------------------------------------------------------
# Fuzzy search tuning
# ---------------------------------------------------------------------------

COARSE_TYPE_SCORE_BOOST       = 0.05  # score added when coarse type is compatible with the food reference
FUZZY_TRIGRAM_SHORTLIST_SIZE  = 50    # candidates pulled from trigram index before full similarity scoring
FUZZY_DEFAULT_CANDIDATE_LIMIT = 8     # default maximum fuzzy results returned by the index

# ---------------------------------------------------------------------------
# Per-line resolution tuning
# ---------------------------------------------------------------------------
#
# Resolving each OCR line independently (instead of one concatenated blob)
# avoids the token-set-Dice denominator blowing up on fine print: a 1-word
# match against a 30-token blob scores ~0.06, but against its own short line it
# scores near 1.0. Prominence (bounding-box height, normalized 0..1) then biases
# toward the largest text — usually the product name.
#
# SMALL_TEXT_PENALTY controls how hard a non-prominent line is down-weighted:
#   per-line factor = 1 - SMALL_TEXT_PENALTY * (1 - prominence)
#   0.0 → prominence ignored (every line treated equally)
#   1.0 → a line's score is scaled straight by its prominence
# Default is deliberately moderate: brand text or a large net-weight line is
# sometimes taller than the product name, so we bias rather than hard-filter.
SMALL_TEXT_PENALTY = 0.5

# ---------------------------------------------------------------------------
# Multi-line name recombination
# ---------------------------------------------------------------------------
#
# Per-line resolution can't see a product name split across lines ("Black" /
# "Beans" → "black beans"), so it scores neither half as the whole and a shorter
# distractor ("black tea") can edge it out. We additionally resolve *joins* of
# the most-prominent lines so the full name is scored as a unit (and can hit the
# lexical-exact path for 1.0).
#
# Cost is bounded to a small constant — only the top-K prominent lines are
# eligible, and only subsets up to size C are joined — so this stays fast on
# iPhone hardware regardless of how much fine print OCR returns. With the
# defaults below a crop adds at most C(4,2)+C(4,3) = 10 joined queries.
MAX_COMBINE_LINES  = 4  # K: top-K prominent lines eligible to combine (0/1 disables)
MAX_COMBINE_SIZE   = 3  # C: largest subset of lines joined into one query
MAX_COMBINE_TOKENS = 6  # skip any join longer than this many tokens (denominator guard)
