"""Thin demo for the OCR service — reusable logic lives in ocr.py."""

from pathlib import Path

from ocr import apple_ocr

if __name__ == "__main__":
    _data = Path(__file__).resolve().parents[2] / "data"
    print(apple_ocr(_data / "work" / "crops" / "IMG_4514_box_7.jpg"))
