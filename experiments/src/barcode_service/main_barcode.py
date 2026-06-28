"""CLI demo for the barcode service — reusable logic lives in barcode.py.

Scans an image for barcodes and prints each decoded value, symbology, and pixel
bbox. With --off, each barcode is also looked up on Open Food Facts and its
product name / brand printed.

Run from this directory:
    ../.venv/bin/python main_barcode.py /path/to/photo.jpg
    ../.venv/bin/python main_barcode.py /path/to/photo.jpg --off
    ../.venv/bin/python main_barcode.py /path/to/photo.jpg --off --overlay out.jpg
"""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2

from barcode import BarcodeService
from openfoodfacts import OpenFoodFactsClient


def main() -> None:
    parser = argparse.ArgumentParser(description="Scan an image for barcodes.")
    parser.add_argument("image", type=Path, help="path to the image to scan")
    parser.add_argument(
        "--off", action="store_true",
        help="resolve each barcode against Open Food Facts (no API key needed)",
    )
    parser.add_argument(
        "--overlay", type=Path, default=None,
        help="optional path to write a copy of the image with barcode boxes drawn",
    )
    args = parser.parse_args()

    if not args.image.exists():
        parser.error(f"image not found: {args.image}")

    svc = BarcodeService()
    image = svc.read(args.image)
    barcodes = svc.scan_array(image)

    print(f"{args.image.name}: {len(barcodes)} barcode(s) decoded")
    off = OpenFoodFactsClient() if args.off else None

    for i, bc in enumerate(barcodes, 1):
        print(f"  [{i}] {bc.value}  ({bc.symbology or 'unknown'})  bbox={bc.bbox}")
        if off is not None:
            product = off.lookup(bc.value)
            if product and product.best_name:
                brand = f" — {product.brand_hint}" if product.brand_hint else ""
                print(f"        OFF: {product.best_name}{brand}")
            else:
                print("        OFF: no match")

    if args.overlay is not None:
        out = svc.draw_overlay(image, barcodes)
        args.overlay.parent.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(args.overlay), out)
        print(f"  overlay written to {args.overlay}")


if __name__ == "__main__":
    main()
