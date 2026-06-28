"""Thin demo for the OCR service — reusable logic lives in ocr.py."""

from pathlib import Path

from ocr import OCRService

if __name__ == "__main__":
    _data = Path(__file__).resolve().parents[2] / "data"
    _crop = _data / "work" / "crops" / "IMG_4510_box_12.jpeg"

    print("Lines ranked by bounding-box prominence (product name should be near the top):")
    for text, prominence in OCRService().prominent_lines(_crop):
        print(f"  {prominence:.2f}  {text}")
