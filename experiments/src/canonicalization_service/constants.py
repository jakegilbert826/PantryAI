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
