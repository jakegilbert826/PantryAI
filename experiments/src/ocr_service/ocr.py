"""
Reusable on-device OCR via Apple's Vision framework (VNRecognizeTextRequest).

macOS-only (depends on pyobjc Vision/Quartz bindings). Returns the recognized
text for an image either as a flat list of lines (legacy) or as structured
observations that carry each line's bounding box.

Why the bounding box matters: a product label is mostly fine print (nutrition
panel, ingredients, marketing copy). The product *name* is almost always the
largest text on the label — a tall bounding box. Vision already gives us one
observation per line with a normalized boundingBox, so we can rank lines by
prominence and let the resolver focus on the name instead of drowning it in the
fine print. See `prominent_lines()` and `read_observations()`.

Usage:
    from ocr import OCRService
    ocr = OCRService()

    lines = ocr.read_text("crop.jpg")              # list[str] (legacy, blob-style)

    obs = ocr.read_observations("crop.jpg")        # list[TextObservation] w/ bbox
    ranked = ocr.prominent_lines("crop.jpg")       # [(text, prominence 0..1)] desc
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Sequence

import Quartz
import Vision

# --------------------------------------------------------------------------- tunables

# Which bbox dimension defines "prominence". Product names are tall, so height
# is the most reliable signal (a short name like "CORN" has small *area* but
# large *height*); area is offered for labels where width tracks importance.
ProminenceMetric = Literal["height", "area"]
DEFAULT_PROMINENCE_METRIC: ProminenceMetric = "height"

# Default cap on how many of the most-prominent lines to forward downstream.
# None = forward all lines (let the resolver's small-text penalty do the work);
# an int = hard-drop everything below the top-N tallest lines.
DEFAULT_TOP_N_LINES: int | None = None


@dataclass(frozen=True)
class TextObservation:
    """One recognized line with its normalized bounding box (Vision coords).

    `bbox` is (x, y, width, height) in [0, 1] image-normalized coordinates with
    origin at the bottom-left (Vision's convention). Only the size matters for
    prominence, so the origin convention is irrelevant here.
    """
    text: str
    confidence: float
    bbox: tuple[float, float, float, float]  # (x, y, w, h), normalized

    @property
    def width(self) -> float:
        return self.bbox[2]

    @property
    def height(self) -> float:
        return self.bbox[3]

    @property
    def area(self) -> float:
        return self.bbox[2] * self.bbox[3]

    def prominence_value(self, metric: ProminenceMetric = DEFAULT_PROMINENCE_METRIC) -> float:
        return self.area if metric == "area" else self.height


def prominence_weights(
    observations: Sequence[TextObservation],
    metric: ProminenceMetric = DEFAULT_PROMINENCE_METRIC,
) -> list[float]:
    """Normalize each observation's prominence to [0, 1] (largest line == 1.0).

    The returned weight is a *relative* measure within this image so the
    downstream small-text penalty is independent of absolute label scale.
    """
    if not observations:
        return []
    values = [obs.prominence_value(metric) for obs in observations]
    top = max(values)
    if top <= 0:
        return [1.0 for _ in values]
    return [v / top for v in values]


class OCRService:
    """Thin wrapper around Vision text recognition with tunable accuracy."""

    def __init__(self, accurate: bool = True, language_correction: bool = True):
        self._level = (
            Vision.VNRequestTextRecognitionLevelAccurate
            if accurate
            else Vision.VNRequestTextRecognitionLevelFast
        )
        self._language_correction = language_correction

    # ------------------------------------------------------------ recognition

    def read_observations(self, image_path: str | Path) -> list[TextObservation]:
        """Run text recognition, returning one observation per line with bbox.

        Lines are returned in Vision's native order (not prominence order) so
        callers can choose how to rank them.
        """
        path = str(image_path)
        url = Quartz.CFURLCreateFromFileSystemRepresentation(
            None, path.encode(), len(path), False
        )
        handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(url, {})

        request = Vision.VNRecognizeTextRequest.alloc().init()
        request.setRecognitionLevel_(self._level)
        request.setUsesLanguageCorrection_(self._language_correction)

        handler.performRequests_error_([request], None)

        observations: list[TextObservation] = []
        for obs in request.results() or []:
            candidates = obs.topCandidates_(1)
            if not candidates:
                continue
            box = obs.boundingBox()  # CGRect, normalized, origin bottom-left
            observations.append(
                TextObservation(
                    text=candidates[0].string(),
                    confidence=float(candidates[0].confidence()),
                    bbox=(
                        float(box.origin.x),
                        float(box.origin.y),
                        float(box.size.width),
                        float(box.size.height),
                    ),
                )
            )
        return observations

    def read_text(self, image_path: str | Path) -> list[str]:
        """Legacy: recognized lines as plain strings, in Vision's order."""
        return [obs.text for obs in self.read_observations(image_path)]

    # -------------------------------------------------------------- prominence

    def prominent_lines(
        self,
        image_path: str | Path,
        top_n: int | None = DEFAULT_TOP_N_LINES,
        metric: ProminenceMetric = DEFAULT_PROMINENCE_METRIC,
    ) -> list[tuple[str, float]]:
        """Recognized lines paired with a normalized prominence weight (0..1),
        sorted most-prominent first.

        `top_n` optionally hard-drops everything below the N tallest lines; the
        softer alternative is to forward all lines and let the resolver apply a
        tunable small-text penalty (see canonicalization.resolve_lines).
        """
        observations = self.read_observations(image_path)
        weights = prominence_weights(observations, metric)
        ranked = sorted(
            ((obs.text, w) for obs, w in zip(observations, weights)),
            key=lambda pair: pair[1],
            reverse=True,
        )
        return ranked[:top_n] if top_n is not None else ranked


# Backwards-compatible function form.
def apple_ocr(image_path: str | Path) -> list[str]:
    return OCRService().read_text(image_path)


if __name__ == "__main__":
    _data = Path(__file__).resolve().parents[2] / "data"
    _crop = _data / "work" / "crops" / "IMG_4514_box_7.jpg"
    for text, prom in OCRService().prominent_lines(_crop):
        print(f"{prom:.2f}  {text}")
