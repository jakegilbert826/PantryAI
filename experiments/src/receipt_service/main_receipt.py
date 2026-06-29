"""
Receipt scanning service demo.

Run from this directory:
    ../../.venv/bin/python main_receipt.py receipt.jpg

Without a file argument the script exercises the parser directly on sample
receipt text (no Vision / macOS dependency needed).
"""

from __future__ import annotations

import sys
from pathlib import Path

# Make the sibling canonicalization package importable regardless of CWD.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "canonicalization_service"))

from receipt_scanner import MeasureUnit, ParsedReceiptLine, ReceiptLineParser, ReceiptScanner


# ---------------------------------------------------------------------------
# Pure-parser smoke test (no Vision dependency)
# ---------------------------------------------------------------------------

SAMPLE_LINES = [
    # Header (should be trimmed — no trailing price yet)
    "TESCO STORES LTD",
    "STORE 1234  TEL 0800 000 000",
    # Item body
    "WHOLE MILK 6PT            1.89",
    "FREE RANGE EGGS 12        2.50",
    "CHEDDAR CHEESE 400g       3.00",
    "HEINZ BAKED BEANS 415g    0.70",
    "2 X GREEK YOGURT          1.40",
    "OLIVE OIL 500ml           4.00",
    "BANANA                    0.19",
    # Non-item lines that should be dropped
    "SAVE 0.50 ON YOGURT",
    "CLUBCARD PRICE",
    # Footer (everything from here down should be stripped)
    "SUBTOTAL                  13.68",
    "TOTAL                     13.68",
    "VISA CONTACTLESS          13.68",
    "AID A0000000031010",
    "THANK YOU FOR SHOPPING",
]


def _print_items(items: list[ParsedReceiptLine]) -> None:
    for item in items:
        measure = (
            f"{item.measure_value}{item.measure_unit.value}"
            if item.measure_value > 0
            else "—"
        )
        price = f"£{item.price:.2f}" if item.price is not None else "—"
        print(f"  {item.name:<35} {measure:<10} {price:<8} conf={item.confidence:.2f}")


def run_parser_demo() -> None:
    print("=== ReceiptLineParser (pure Python, no Vision) ===\n")
    items = ReceiptLineParser.parse(SAMPLE_LINES)
    _print_items(items)
    print(f"\n{len(items)} item(s) parsed from {len(SAMPLE_LINES)} input lines.")


def run_scanner(image_path: str) -> None:
    print(f"=== ReceiptScanner → {image_path} ===\n")
    scanner = ReceiptScanner()
    items = scanner.scan(image_path)
    run_canonicalization(items)
    # _print_items(items)
    # print(f"\n{len(items)} item(s) parsed.")


def run_canonicalization(items: list[ParsedReceiptLine]) -> None:
    """Resolve each parsed receipt line through the canonicalization cascade."""
    from dotenv import load_dotenv
    load_dotenv()

    from canonicalization import CanonicalizationService, InflowSource
    svc = CanonicalizationService.from_supabase()

    print("\n=== Canonicalization (receiptOCR) ===\n")
    print(f"  {'Raw name':<35} {'Canonical':<30} {'Via':<10} {'Conf'}")
    print(f"  {'-'*35} {'-'*30} {'-'*10} {'-'*4}")
    for item in items:
        result = svc.resolve(item.name, source=InflowSource.RECEIPT_OCR)
        canonical = result.canonical_name or "—"
        via       = result.matched_via.value
        conf      = f"{result.confidence:.2f}"
        print(f"  {item.name:<35} {canonical:<30} {via:<10} {conf}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        run_scanner(sys.argv[1])
    else:
        items = ReceiptLineParser.parse(SAMPLE_LINES)
        run_parser_demo()
        run_canonicalization(items)
