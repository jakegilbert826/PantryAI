"""
Receipt scanning service — Python port of Services/Receipt/ (Swift).

Mirrors the three-file Swift design:
  ReceiptScanning.swift      → ReceiptOCRLine / ParsedReceiptLine types
  ReceiptLineParser.swift    → ReceiptLineParser (pure, deterministic, testable)
  VisionReceiptScanner.swift → ReceiptScanner (Vision OCR + parser wired together)

macOS-only: ReceiptScanner depends on the pyobjc Vision/Quartz bindings.
ReceiptLineParser is pure Python and fully unit-testable without Vision.

Usage:
    from receipt_scanner import ReceiptScanner, ReceiptLineParser, ReceiptOCRLine

    # Full pipeline (requires Vision / macOS):
    scanner = ReceiptScanner()
    items = scanner.scan("receipt.jpg")          # list[ParsedReceiptLine]

    # Parser only (pure Python, for tests):
    lines = ReceiptLineParser.parse(["WHOLE MILK 2.09", "TOTAL 2.09"])
    for item in lines:
        print(item.name, item.measure_value, item.price)
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Types (mirrors ReceiptScanning.swift)
# ---------------------------------------------------------------------------

class MeasureUnit(str, Enum):
    G    = "g"
    ML   = "ml"
    UNIT = "unit"


@dataclass
class ReceiptOCRLine:
    """One recognised line of text with OCR confidence and vertical position.

    `min_y` is Vision's bottom-up normalised coordinate; used only to sort
    lines top-to-bottom before parsing (descending min_y = top-to-bottom).
    """
    text: str
    confidence: float
    min_y: float = 0.0


@dataclass
class ParsedReceiptLine:
    """A receipt line the parser believes is a purchasable item.

    Measure is in canonical units (g/ml) when a net weight is present, a
    multipack count in UNIT, or 0 / UNIT for "undetermined". `price` is the
    trailing line price carried for debugging/UX — not committed to the DB.
    """
    name: str
    measure_value: float
    measure_unit: MeasureUnit
    price: Optional[float]
    confidence: float


# ---------------------------------------------------------------------------
# ReceiptLineParser (mirrors ReceiptLineParser.swift exactly)
# ---------------------------------------------------------------------------

class ReceiptLineParser:
    """Pure, deterministic, OCR-engine-agnostic receipt line parser.

    Filters receipt furniture (totals, payment, headers), then for each line
    it believes is an item it extracts a clean name, optional price, and a
    best-effort measure. Does NOT assign canonical identity.
    """

    # -- Noise tokens (whole-token match) -----------------------------------

    _NOISE_TOKENS: frozenset[str] = frozenset({
        "total", "subtotal", "balance", "change", "cash", "card", "visa",
        "mastercard", "debit", "credit", "contactless", "tender", "vat", "tax",
        "points", "clubcard", "nectar", "savings", "saved", "due", "amount",
        "receipt", "thank", "thanks", "store", "tel", "www", "http", "https",
        "reg", "till", "cashier", "items", "qty", "ltd", "plc", "returns",
        "refund", "void", "gbp", "eur", "usd", "auth", "terminal", "merchant",
        "account", "approved", "verified", "aid", "mid", "operator",
        # Tax-invoice / loyalty furniture (AU/UK/NZ).
        "invoice", "abn", "gst", "eftpos", "loyalty", "rewards", "fax",
    })

    # Soft stopwords: only noise when the line is composed *entirely* of them.
    _RESIDUAL_STOPWORDS: frozenset[str] = frozenset({
        "net", "kg", "kgs", "g", "gm", "gms", "ml", "l", "ltr", "litre", "litres",
        "ea", "each", "per", "pk", "pack", "ct", "ctn", "qty", "unit", "units",
        "approx", "avg", "was", "now", "save", "special", "member", "price",
        "rrp", "incl", "excl", "wt", "weight", "value", "multi", "buy", "x",
    })

    _TOTALS_MARKERS: frozenset[str] = frozenset({"total", "subtotal", "balance"})

    # Compiled patterns — built once at class definition time.
    _TRAILING_PRICE_RE = re.compile(
        r'(?:[£$€])?\s?-?\d{1,4}[.,]\d{2}(?:\s?[A-Za-z])?\s*$'
    )
    _WEIGHT_RE         = re.compile(r'(\d+(?:[.,]\d+)?)\s?(kg|g|ml|cl|l|lb|oz)\b', re.IGNORECASE)
    _MULTIPACK_RE      = re.compile(r'^\s*(\d{1,2})\s*(?:[@x×*]|for\b)', re.IGNORECASE)
    _LEADING_QTY_RE    = re.compile(r'^\s*\d{1,2}\s+(?=[A-Za-z])')
    _CURRENCY_RE       = re.compile(r'[£$€*]')
    _STANDALONE_NUM_RE = re.compile(r'\b\d+(?:[.,]\d+)?\b')
    _SUB_TOTAL_RE      = re.compile(r'\bsub\s*total\b', re.IGNORECASE)
    _AMOUNT_DUE_RE     = re.compile(r'\bamount\s+due\b', re.IGNORECASE)
    _TO_PAY_RE         = re.compile(r'\bto\s+pay\b', re.IGNORECASE)
    _URL_RE            = re.compile(r'(?:https?://|www\.)', re.IGNORECASE)
    _DOMAIN_RE         = re.compile(
        r'[a-z0-9][a-z0-9-]*\.(?:com|net|org|co|io|gov|edu|au|uk|nz|ca|ie)\b',
        re.IGNORECASE,
    )
    _PURE_NONLETTER_RE = re.compile(r'^[\s\d\W]+$')
    _DATE_RE           = re.compile(r'\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}')
    _TIME_RE           = re.compile(r'\b\d{2}:\d{2}\b')

    # -----------------------------------------------------------------------
    # Public API
    # -----------------------------------------------------------------------

    @classmethod
    def parse(cls, lines: list[ReceiptOCRLine] | list[str]) -> list[ParsedReceiptLine]:
        """Parse OCR lines into candidate items, in receipt order."""
        ocr_lines: list[ReceiptOCRLine] = [
            ReceiptOCRLine(text=ln, confidence=1.0) if isinstance(ln, str) else ln
            for ln in lines
        ]
        window = cls._item_window(ocr_lines)
        return [item for item in (cls._parse_line(ln) for ln in window) if item is not None]

    # -----------------------------------------------------------------------
    # Body-boundary anchoring (ADR-002 v1)
    #
    # Drop everything from the first totals line down (footer), and everything
    # above the first priced line (header). Per-line filtering then runs only
    # inside that window. When NO line carries a price we trim nothing.
    # -----------------------------------------------------------------------

    @classmethod
    def _item_window(cls, lines: list[ReceiptOCRLine]) -> list[ReceiptOCRLine]:
        footer_start = next(
            (i for i, ln in enumerate(lines) if cls._is_totals_marker(ln.text)),
            len(lines),
        )
        header = lines[:footer_start]
        header_end = next(
            (i for i, ln in enumerate(header) if cls._has_trailing_price(ln.text)),
            0,
        )
        return lines[header_end - 1:footer_start]

    @classmethod
    def _is_totals_marker(cls, line: str) -> bool:
        lower = line.lower()
        if cls._SUB_TOTAL_RE.search(lower):
            return True
        if cls._AMOUNT_DUE_RE.search(lower) or cls._TO_PAY_RE.search(lower):
            return True
        tokens = re.split(r'[^a-z]+', lower)
        return any(t in cls._TOTALS_MARKERS for t in tokens if t)

    @classmethod
    def _has_trailing_price(cls, line: str) -> bool:
        return bool(cls._TRAILING_PRICE_RE.search(line))

    # -----------------------------------------------------------------------
    # Noise filtering
    # -----------------------------------------------------------------------

    @classmethod
    def _is_noise(cls, line: str) -> bool:
        lower = line.lower()
        if cls._URL_RE.search(lower):
            return True
        if cls._DOMAIN_RE.search(lower):
            return True
        if cls._PURE_NONLETTER_RE.match(lower):
            return True
        if cls._DATE_RE.search(lower):
            return True
        if cls._TIME_RE.search(lower):
            return True
        tokens = re.split(r'[^a-z]+', lower)
        return any(t in cls._NOISE_TOKENS for t in tokens if t)

    @classmethod
    def _is_all_stopwords(cls, name: str) -> bool:
        words = re.split(r'[^a-z]+', name.lower())
        non_empty = [w for w in words if w]
        if not non_empty:
            return True
        return all(w in cls._RESIDUAL_STOPWORDS for w in non_empty)

    # -----------------------------------------------------------------------
    # Single-line parsing
    # -----------------------------------------------------------------------

    @classmethod
    def _parse_line(cls, line: ReceiptOCRLine) -> Optional[ParsedReceiptLine]:
        raw = line.text.strip()
        if not raw or cls._is_noise(raw):
            return None

        working = raw

        # 1. Trailing price (end-anchored so a mid-line "2.27L" isn't a price).
        price, working = cls._extract_trailing_price(working)

        # 2. Net weight → canonical g/ml.
        measure_value = 0.0
        measure_unit  = MeasureUnit.UNIT
        weight = cls._extract_weight(working)
        if weight is not None:
            measure_value, measure_unit, working = weight

        # 3. Multipack count, only when no explicit weight.
        if measure_value == 0.0:
            multipack = cls._extract_multipack(working)
            if multipack is not None:
                measure_value, working = float(multipack[0]), multipack[1]
                measure_unit = MeasureUnit.UNIT

        # 4. Clean name.
        name = cls._clean_name(working)
        if not cls._has_enough_letters(name) or cls._is_all_stopwords(name):
            return None

        # 5. Confidence: trailing price is a strong "real line item" signal.
        confidence = 0.5
        if price is not None:
            confidence += 0.2
        if measure_value > 0:
            confidence += 0.05
        confidence = min(1.0, confidence * line.confidence)

        return ParsedReceiptLine(
            name=name,
            measure_value=measure_value,
            measure_unit=measure_unit,
            price=price,
            confidence=confidence,
        )

    # -----------------------------------------------------------------------
    # Extraction
    # -----------------------------------------------------------------------

    @classmethod
    def _extract_trailing_price(cls, s: str) -> tuple[Optional[float], str]:
        m = cls._TRAILING_PRICE_RE.search(s)
        if not m:
            return None, s
        match_text = m.group(0)
        remainder  = s[:m.start()]
        digits = re.sub(r'[^0-9.,\-]', '', match_text).replace(',', '.')
        try:
            return float(digits), remainder
        except ValueError:
            return None, s

    @classmethod
    def _extract_weight(cls, s: str) -> Optional[tuple[float, MeasureUnit, str]]:
        """Return (canonical_value, unit, stripped_string) or None."""
        m = cls._WEIGHT_RE.search(s)
        if not m:
            return None
        try:
            amount = float(m.group(1).replace(',', '.'))
        except ValueError:
            return None

        unit_str = m.group(2).lower()
        conversions: dict[str, tuple[float, MeasureUnit]] = {
            "kg": (amount * 1000,    MeasureUnit.G),
            "g":  (amount,           MeasureUnit.G),
            "l":  (amount * 1000,    MeasureUnit.ML),
            "cl": (amount * 10,      MeasureUnit.ML),
            "ml": (amount,           MeasureUnit.ML),
            "lb": (amount * 453.592, MeasureUnit.G),
            "oz": (amount * 28.3495, MeasureUnit.G),
        }
        if unit_str not in conversions:
            return None
        value, unit = conversions[unit_str]
        value = round(value * 100) / 100
        stripped = s[:m.start()] + " " + s[m.end():]
        return value, unit, stripped

    @classmethod
    def _extract_multipack(cls, s: str) -> Optional[tuple[int, str]]:
        """Return (count, stripped_string) or None."""
        m = cls._MULTIPACK_RE.match(s)
        if not m:
            return None
        count = int(m.group(1))
        if count <= 0:
            return None
        stripped = s[m.end():]
        return count, stripped

    # -----------------------------------------------------------------------
    # Name cleanup
    # -----------------------------------------------------------------------

    @classmethod
    def _clean_name(cls, s: str) -> str:
        name = cls._LEADING_QTY_RE.sub('', s)
        name = cls._CURRENCY_RE.sub(' ', name)
        name = cls._STANDALONE_NUM_RE.sub(' ', name)
        return ' '.join(name.split()).strip()

    @staticmethod
    def _has_enough_letters(s: str) -> bool:
        return sum(1 for c in s if c.isalpha()) >= 2


# ---------------------------------------------------------------------------
# ReceiptScanner (mirrors VisionReceiptScanner.swift)
# ---------------------------------------------------------------------------

class ReceiptScanner:
    """On-device receipt OCR via Apple Vision, fed into ReceiptLineParser.

    macOS-only — depends on pyobjc Vision/Quartz bindings. Zero running cost:
    the whole point of replacing a per-scan LLM call is on-device inference.

    Accepts a file path (unlike the Swift `imageData: Data` form) to stay
    consistent with the other experiment services (OCRService, BarcodeService).
    """

    def __init__(self, accurate: bool = True, language_correction: bool = True):
        self._accurate            = accurate
        self._language_correction = language_correction

    def scan(self, image_path: str | Path) -> list[ParsedReceiptLine]:
        """Run Vision OCR on a receipt image and return parsed line items."""
        lines = self._recognize_lines(image_path)
        return ReceiptLineParser.parse(lines)

    def _recognize_lines(self, image_path: str | Path) -> list[ReceiptOCRLine]:
        """Run VNRecognizeTextRequest and sort lines top-to-bottom."""
        import Quartz
        import Vision

        path = str(image_path)
        url = Quartz.CFURLCreateFromFileSystemRepresentation(
            None, path.encode(), len(path), False
        )
        handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(url, {})

        request = Vision.VNRecognizeTextRequest.alloc().init()
        request.setRecognitionLevel_(
            Vision.VNRequestTextRecognitionLevelAccurate
            if self._accurate
            else Vision.VNRequestTextRecognitionLevelFast
        )
        request.setUsesLanguageCorrection_(self._language_correction)

        handler.performRequests_error_([request], None)

        ocr_lines: list[ReceiptOCRLine] = []
        for obs in request.results() or []:
            candidates = obs.topCandidates_(1)
            if not candidates:
                continue
            box = obs.boundingBox()  # CGRect, normalised, origin bottom-left
            ocr_lines.append(ReceiptOCRLine(
                text=candidates[0].string(),
                confidence=float(candidates[0].confidence()),
                min_y=float(box.origin.y),
            ))

        # Vision coordinates are bottom-up; sort descending min_y for
        # natural top-to-bottom receipt order (mirrors VisionReceiptScanner.swift).
        return sorted(ocr_lines, key=lambda ln: ln.min_y, reverse=True)
