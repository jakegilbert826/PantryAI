"""
Reusable barcode scanning service (Apple Vision).

Detects and decodes 1-D product barcodes (EAN-13 / EAN-8 / UPC-A …) anywhere in
an image using Vision's VNDetectBarcodesRequest — the same on-device framework
the OCR service uses, and markedly more robust than OpenCV's barcode module. The
whole frame is scanned once; the caller spatially joins the results to detector
crops (see `associate_barcodes_to_crops`).

macOS-only (depends on the pyobjc Vision/Quartz bindings, as ocr.py does). Each
barcode's bbox is returned in **pixel** coordinates with a top-left origin so it
shares the segmentation crops' coordinate system.

Coordinate note: Vision returns a normalized CGRect with a *bottom-left* origin
and applies a file's EXIF orientation. Segmentation reads raw pixels via cv2
(no EXIF), so to keep both in the same space we scan the cv2-decoded array (via a
short-lived temp file) rather than the original path, then flip Vision's y axis.

Usage:
    from barcode import BarcodeService, associate_barcodes_to_crops

    svc = BarcodeService()
    barcodes = svc.scan("photo.jpg")                 # list[BarcodeDetection]
    assoc = associate_barcodes_to_crops(barcodes, detections)  # {crop_box_id: BarcodeDetection}
"""

from __future__ import annotations

import os
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

import cv2
import numpy as np
import Quartz
import Vision

# (xmin, ymin, xmax, ymax) clipped to image, matching segmentation.Detection.bbox.
BBox = tuple[int, int, int, int]


@dataclass(frozen=True)
class BarcodeDetection:
    """One decoded barcode: its value, symbology, and place in the frame."""
    value: str
    symbology: str                 # e.g. "EAN13" / "UPCA" ("" if Vision didn't report)
    bbox: BBox                     # axis-aligned, pixel coords, top-left origin
    corners: tuple[tuple[int, int], ...]  # 4 quad vertices (axis-aligned from bbox)

    @property
    def center(self) -> tuple[float, float]:
        xmin, ymin, xmax, ymax = self.bbox
        return ((xmin + xmax) / 2.0, (ymin + ymax) / 2.0)

    @property
    def area(self) -> int:
        xmin, ymin, xmax, ymax = self.bbox
        return max(0, xmax - xmin) * max(0, ymax - ymin)


def _clean_symbology(raw: object) -> str:
    """Vision reports e.g. 'VNBarcodeSymbologyEAN13'; drop the prefix."""
    s = str(raw or "")
    return s.replace("VNBarcodeSymbology", "").strip()


class BarcodeService:
    """Runs Vision's barcode detector and exposes stateless scan helpers."""

    def __init__(self) -> None:
        # Vision's request object is cheap; build one per scan to stay stateless.
        pass

    # ------------------------------------------------------------------ I/O

    @staticmethod
    def read(image_path: str | Path) -> np.ndarray:
        img = cv2.imread(str(image_path))
        if img is None:
            raise ValueError(f"Unreadable image: {image_path}")
        return img

    # ------------------------------------------------------------ inference

    def scan(self, image_path: str | Path) -> list[BarcodeDetection]:
        """Detect + decode every barcode in an image file.

        Routed through cv2 decoding so the pixel space matches segmentation
        (EXIF-agnostic), even though Vision does the detection.
        """
        return self.scan_array(self.read(image_path))

    def scan_array(self, image: np.ndarray) -> list[BarcodeDetection]:
        """Detect + decode every barcode in an in-memory BGR image.

        Returns only barcodes that decoded to a non-empty payload (a detected but
        undecodable code is useless for lookup). Vision needs a file/CGImage, so
        the array is written to a short-lived temp file (also strips any EXIF, so
        coordinates stay aligned with the cv2-read segmentation crops).
        """
        height, width = image.shape[:2]
        tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
        tmp.close()
        try:
            cv2.imwrite(tmp.name, image)
            observations = self._detect(tmp.name)
        finally:
            os.unlink(tmp.name)

        detections: list[BarcodeDetection] = []
        for obs in observations:
            payload = obs.payloadStringValue()
            if not payload:
                continue  # detected a code but couldn't decode its payload
            value = str(payload).strip()
            if not value:
                continue
            detections.append(
                BarcodeDetection(
                    value=value,
                    symbology=_clean_symbology(obs.symbology()),
                    bbox=self._bbox_to_pixels(obs.boundingBox(), width, height),
                    corners=tuple(),  # filled below from bbox
                )
            )
        # Derive axis-aligned corners from the pixel bbox (for the QA overlay).
        return [self._with_corners(d) for d in detections]

    @staticmethod
    def _detect(image_path: str) -> list:
        """Run VNDetectBarcodesRequest on a file path; return raw observations."""
        url = Quartz.CFURLCreateFromFileSystemRepresentation(
            None, image_path.encode(), len(image_path), False
        )
        handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(url, {})
        request = Vision.VNDetectBarcodesRequest.alloc().init()
        handler.performRequests_error_([request], None)
        return list(request.results() or [])

    @staticmethod
    def _bbox_to_pixels(box, width: int, height: int) -> BBox:
        """Vision normalized CGRect (bottom-left origin) → pixel bbox (top-left).

        The box top edge in image space is the *larger* normalized y
        (origin.y + height), which maps to the *smaller* pixel y.
        """
        x = float(box.origin.x)
        y = float(box.origin.y)
        w = float(box.size.width)
        h = float(box.size.height)
        xmin = max(0, int(round(x * width)))
        xmax = min(width, int(round((x + w) * width)))
        ymin = max(0, int(round((1.0 - (y + h)) * height)))
        ymax = min(height, int(round((1.0 - y) * height)))
        return (xmin, ymin, xmax, ymax)

    @staticmethod
    def _with_corners(d: BarcodeDetection) -> BarcodeDetection:
        xmin, ymin, xmax, ymax = d.bbox
        corners = ((xmin, ymin), (xmax, ymin), (xmax, ymax), (xmin, ymax))
        return BarcodeDetection(d.value, d.symbology, d.bbox, corners)

    # -------------------------------------------------------------- drawing

    @staticmethod
    def draw_overlay(image: np.ndarray, barcodes: Sequence[BarcodeDetection]) -> np.ndarray:
        """Return a copy of the image with each barcode box + value drawn on."""
        overlay = image.copy()
        for bc in barcodes:
            pts = np.array(bc.corners, dtype=np.int32).reshape(-1, 1, 2)
            cv2.polylines(overlay, [pts], isClosed=True, color=(0, 0, 255), thickness=2)
            xmin, ymin, _, _ = bc.bbox
            cv2.putText(
                overlay,
                bc.value,
                (xmin, max(0, ymin - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (0, 0, 255),
                1,
            )
        return overlay


# --------------------------------------------------------------------------- spatial join

def _expand(bbox: BBox, margin_frac: float) -> BBox:
    """Grow a bbox outward by margin_frac of its own width/height on each side."""
    xmin, ymin, xmax, ymax = bbox
    dx = (xmax - xmin) * margin_frac
    dy = (ymax - ymin) * margin_frac
    return (xmin - dx, ymin - dy, xmax + dx, ymax + dy)


def _point_in(point: tuple[float, float], bbox: BBox) -> bool:
    x, y = point
    xmin, ymin, xmax, ymax = bbox
    return xmin <= x <= xmax and ymin <= y <= ymax


def _overlap_over_barcode(barcode_bbox: BBox, crop_bbox: BBox) -> float:
    """Fraction of the barcode's area that falls inside the crop (0..1).

    IoU is the wrong metric here: a barcode is tiny next to a product crop, so
    even perfect containment gives a near-zero IoU. Intersection-over-barcode-area
    instead asks "how much of the barcode sits inside this crop?", which is what
    we actually care about for association.
    """
    bx0, by0, bx1, by1 = barcode_bbox
    cx0, cy0, cx1, cy1 = crop_bbox
    ix0, iy0 = max(bx0, cx0), max(by0, cy0)
    ix1, iy1 = min(bx1, cx1), min(by1, cy1)
    inter = max(0, ix1 - ix0) * max(0, iy1 - iy0)
    barcode_area = max(1, (bx1 - bx0) * (by1 - by0))
    return inter / barcode_area


def associate_barcodes_to_crops(
    barcodes: Sequence[BarcodeDetection],
    crops: Sequence["Detection"],  # segmentation.Detection (has .box_id, .bbox, .area)
    margin_frac: float = 0.15,
    overlap_floor: float = 0.30,
) -> dict[int, BarcodeDetection]:
    """Map each crop's box_id to the barcode that best belongs to it.

    A strict center-point-in-box test is too brittle: a barcode printed on the
    *side* of a product whose *front* face was the detected crop can sit slightly
    outside the YOLOE box. We therefore associate a (barcode, crop) pair when
    EITHER:
      - the barcode center lands inside the crop box expanded by `margin_frac`
        (tolerates a code just over the edge), OR
      - at least `overlap_floor` of the barcode's area overlaps the crop box.

    Each barcode is assigned to a single best crop (highest overlap, tie-broken
    toward the tightest enclosing crop so a small product wins over a shelf-sized
    box). Returns {crop_box_id: barcode}; if two barcodes claim the same crop the
    one with the greater overlap wins.
    """
    assigned: dict[int, tuple[float, BarcodeDetection]] = {}  # box_id -> (overlap, barcode)

    for bc in barcodes:
        best_crop: Optional["Detection"] = None
        best_overlap = -1.0
        for crop in crops:
            overlap = _overlap_over_barcode(bc.bbox, crop.bbox)
            center_in = _point_in(bc.center, _expand(crop.bbox, margin_frac))
            if overlap < overlap_floor and not center_in:
                continue
            # Prefer the crop the barcode overlaps most; on a tie, the tighter box.
            better = overlap > best_overlap or (
                overlap == best_overlap and best_crop is not None and crop.area < best_crop.area
            )
            if better:
                best_overlap, best_crop = overlap, crop
        if best_crop is None:
            continue
        prev = assigned.get(best_crop.box_id)
        if prev is None or best_overlap > prev[0]:
            assigned[best_crop.box_id] = (best_overlap, bc)

    return {box_id: bc for box_id, (_, bc) in assigned.items()}
