"""
Reusable open-vocabulary segmentation service (YOLOE).

Wraps a YOLOE model behind a small, side-effect-free API so experiments can
run detection without re-implementing the load / predict / crop boilerplate.

Usage:
    from segmentation import SegmentationService

    svc = SegmentationService(model_path="../models/yoloe-26n-seg.pt",
                              classes=["product", "produce"])
    detections = svc.segment("photo.jpg")          # list[Detection]
    overlay    = svc.draw_overlay(svc.read(...), detections)
"""

from __future__ import annotations

import glob
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

import cv2
import numpy as np
from ultralytics import YOLOE

IMAGE_EXTENSIONS = ("*.jpg", "*.jpeg", "*.png", "*.bmp", "*.JPG", "*.JPEG", "*.PNG", "*.BMP")


@dataclass(frozen=True)
class Detection:
    """A single detected item: its place in the frame and the isolated crop."""
    box_id: int
    label: str
    confidence: float
    bbox: tuple[int, int, int, int]  # (xmin, ymin, xmax, ymax), clipped to image
    crop: np.ndarray                 # BGR pixels for the bbox region

    @property
    def area(self) -> int:
        xmin, ymin, xmax, ymax = self.bbox
        return max(0, xmax - xmin) * max(0, ymax - ymin)


def _use_local_text_encoder(weights_dir: Path) -> None:
    """Point ultralytics at a local directory for YOLOE's MobileCLIP text
    encoder so set_classes() resolves the weight there instead of
    re-downloading it.

    ultralytics looks for "mobileclip2_b.ts" relative to the CWD and then in
    SETTINGS["weights_dir"] (also CWD-relative by default), so the lookup is
    CWD-dependent. We override weights_dir to an absolute path in memory only —
    bypassing the persisting setter so the user's global ultralytics config on
    disk is left untouched.
    """
    if not weights_dir.is_dir():
        return
    try:
        from ultralytics.utils import SETTINGS
        dict.__setitem__(SETTINGS, "weights_dir", str(weights_dir))
    except Exception:
        pass


class SegmentationService:
    """Loads a YOLOE model once and exposes stateless detection helpers."""

    def __init__(
        self,
        model_path: str | Path,
        classes: Optional[Sequence[str]] = None,
        confidence_threshold: float = 0.2,
        min_area_fraction: float = 0.0,
    ):
        self.confidence_threshold = confidence_threshold
        # Drop detections smaller than this fraction of the frame area before
        # they ever reach OCR — tiny boxes are usually background clutter whose
        # OCR yields noise. 0.0 keeps every detection (default, non-breaking).
        self.min_area_fraction = min_area_fraction
        # Open-vocab classes need the MobileCLIP text encoder; resolve it from
        # the model's own directory (where mobileclip2_b.ts lives) rather than
        # the CWD, so it is never re-downloaded.
        _use_local_text_encoder(Path(model_path).resolve().parent)
        self._model = YOLOE(str(model_path))
        if classes:
            self._model.set_classes(list(classes))

    # ------------------------------------------------------------------ I/O

    @staticmethod
    def read(image_path: str | Path) -> np.ndarray:
        """Load an image as a BGR array, raising on unreadable files."""
        img = cv2.imread(str(image_path))
        if img is None:
            raise ValueError(f"Unreadable image: {image_path}")
        return img

    @staticmethod
    def list_images(image_dir: str | Path) -> list[Path]:
        """Return sorted, de-duplicated image paths in a directory."""
        directory = Path(image_dir)
        found: set[Path] = set()
        for ext in IMAGE_EXTENSIONS:
            found.update(Path(p) for p in glob.glob(str(directory / ext)))
        return sorted(found)

    # ------------------------------------------------------------ inference

    def segment(self, image_path: str | Path) -> list[Detection]:
        """Detect items in an image file and return their crops."""
        return self.segment_array(self.read(image_path), source=str(image_path))

    def segment_array(self, image: np.ndarray, source: Optional[str] = None) -> list[Detection]:
        """Detect items in an in-memory BGR image."""
        results = self._model.predict(
            source=source if source is not None else image,
            conf=self.confidence_threshold,
            verbose=False,
        )
        result = results[0]
        height, width = image.shape[:2]
        frame_area = max(1, height * width)
        min_area = self.min_area_fraction * frame_area

        detections: list[Detection] = []
        for box_id, box in enumerate(result.boxes):
            xmin, ymin, xmax, ymax = box.xyxy[0].cpu().numpy().astype(int)
            xmin, xmax = max(0, int(xmin)), min(width, int(xmax))
            ymin, ymax = max(0, int(ymin)), min(height, int(ymax))
            if (xmax - xmin) <= 0 or (ymax - ymin) <= 0:
                continue
            if (xmax - xmin) * (ymax - ymin) < min_area:
                continue

            cls_id = int(box.cls[0].item())
            detections.append(
                Detection(
                    box_id=box_id,
                    label=result.names[cls_id],
                    confidence=float(box.conf[0].item()),
                    bbox=(xmin, ymin, xmax, ymax),
                    crop=image[ymin:ymax, xmin:xmax].copy(),
                )
            )
        # Most prominent (largest) items first; box_id still identifies each crop.
        detections.sort(key=lambda d: d.area, reverse=True)
        return detections

    # -------------------------------------------------------------- drawing

    @staticmethod
    def draw_overlay(image: np.ndarray, detections: Sequence[Detection]) -> np.ndarray:
        """Return a copy of the image with bounding boxes + labels drawn on."""
        overlay = image.copy()
        for det in detections:
            xmin, ymin, xmax, ymax = det.bbox
            cv2.rectangle(overlay, (xmin, ymin), (xmax, ymax), (0, 255, 0), 2)
            cv2.putText(
                overlay,
                f"{det.label} {det.confidence:.2f}",
                (xmin, max(0, ymin - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (0, 255, 0),
                1,
            )
        return overlay
