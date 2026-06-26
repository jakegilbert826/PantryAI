"""
Reusable on-device OCR via Apple's Vision framework (VNRecognizeTextRequest).

macOS-only (depends on pyobjc Vision/Quartz bindings). Returns the recognized
text lines for an image, ordered as Vision returns them.

Usage:
    from ocr import OCRService
    ocr = OCRService()
    lines = ocr.read_text("crop.jpg")      # list[str]
"""

from __future__ import annotations

from pathlib import Path

import Quartz
import Vision


class OCRService:
    """Thin wrapper around Vision text recognition with tunable accuracy."""

    def __init__(self, accurate: bool = True, language_correction: bool = True):
        self._level = (
            Vision.VNRequestTextRecognitionLevelAccurate
            if accurate
            else Vision.VNRequestTextRecognitionLevelFast
        )
        self._language_correction = language_correction

    def read_text(self, image_path: str | Path) -> list[str]:
        """Run text recognition on an image file, returning recognized lines."""
        path = str(image_path)
        url = Quartz.CFURLCreateFromFileSystemRepresentation(
            None, path.encode(), len(path), False
        )
        handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(url, {})

        request = Vision.VNRecognizeTextRequest.alloc().init()
        request.setRecognitionLevel_(self._level)
        request.setUsesLanguageCorrection_(self._language_correction)

        handler.performRequests_error_([request], None)

        lines: list[str] = []
        for obs in request.results() or []:
            candidates = obs.topCandidates_(1)
            if candidates:
                lines.append(candidates[0].string())
        return lines


# Backwards-compatible function form.
def apple_ocr(image_path: str | Path) -> list[str]:
    return OCRService().read_text(image_path)


if __name__ == "__main__":
    print(apple_ocr(Path("../cv_output/IMG_4514_box_7.jpg")))
