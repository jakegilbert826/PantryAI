"""Thin demo for the OCR service — reusable logic lives in ocr.py."""

from pathlib import Path

from ocr import apple_ocr

if __name__ == "__main__":
    print(apple_ocr(Path("../cv_output/IMG_4514_box_7.jpg")))
