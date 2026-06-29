"""
Reusable barcode scanning service (Apple Vision).

Detects and decodes 1-D product barcodes (EAN-13 / EAN-8 / UPC-A …) anywhere in
an image using Vision's VNDetectBarcodesRequest — the same on-device framework
the OCR service uses, and markedly more robust than OpenCV's barcode module.

VNDetectBarcodesRequest does not internally retry orientations: for 1-D linear
barcodes (EAN-13, UPC) the scanner looks for parallel lines along a fixed axis, so
a barcode rotated 90° relative to the image frame can be missed entirely. QR codes
and Data Matrix are rotation-invariant (finder patterns), so this is a 1-D-only
issue — which is exactly the food product case.

The service runs up to N orientation passes (default 4) and deduplicates by
payload. Only barcodes detected in the Up (standard) pass get a reliable bbox;
detections from rotated passes are marked `spatial_reliable=False` with a zeroed
bbox — they contribute a payload for lookup but are excluded from spatial joins.
The caller controls how many orientations to try via `n_orientations`.

macOS-only (depends on the pyobjc Vision/Quartz bindings, as ocr.py does). Each
barcode's bbox is returned in **pixel** coordinates with a top-left origin so it
shares the segmentation crops' coordinate system.

Coordinate note: Vision returns a normalized CGRect with a *bottom-left* origin
and applies a file's EXIF orientation. Segmentation reads raw pixels via cv2
(no EXIF), so to keep both in the same space we scan the cv2-decoded array (via a
short-lived temp file) rather than the original path, then flip Vision's y axis.

Usage:
    from barcode import BarcodeService, associate_barcodes_to_crops

    svc = BarcodeService()                           # 4-orientation scan (default)
    svc = BarcodeService(n_orientations=1)           # Up only — fastest, no rotation recovery
    barcodes = svc.scan("photo.jpg")                 # whole-image scan
    barcodes = svc.scan_grid(image, grid_n=3)        # 3×3 tile scan; coords normalised to full image
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

# Ordered scan orientations: first N are used depending on n_orientations.
# Up and Down cover the horizontal axis (0°/180°); Left and Right add the vertical axis.
_SCAN_ORIENTATIONS = [
    Quartz.kCGImagePropertyOrientationUp,     # 0° — standard; bbox reliable
    Quartz.kCGImagePropertyOrientationDown,   # 180° — catches upside-down codes on same axis
    Quartz.kCGImagePropertyOrientationLeft,   # 90° CCW — catches sideways 1-D barcodes
    Quartz.kCGImagePropertyOrientationRight,  # 90° CW
]


@dataclass(frozen=True)
class BarcodeDetection:
    """One decoded barcode: its value, symbology, and place in the frame."""
    value: str
    symbology: str                  # e.g. "EAN13" / "UPCA" ("" if Vision didn't report)
    bbox: BBox                      # axis-aligned, pixel coords, top-left origin
    corners: tuple[tuple[int, int], ...]  # 4 quad vertices (axis-aligned from bbox)
    spatial_reliable: bool = True   # False when bbox is from a rotated pass (wrong frame)

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
    """Runs Vision's barcode detector and exposes stateless scan helpers.

    n_orientations controls how many CGImage orientation passes are attempted
    (from the ordered list [Up, Down, Left, Right]). Barcode detection is
    fast enough that four passes costs less than one OCR crop pass, so the
    default is 4. Use 1 for Up-only if orientation is guaranteed or spatial
    accuracy of every detection matters more than recall.
    """

    def __init__(self, n_orientations: int = 1) -> None:
        if not 1 <= n_orientations <= 4:
            raise ValueError(f"n_orientations must be 1–4, got {n_orientations}")
        self._orientations = _SCAN_ORIENTATIONS[:n_orientations]

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

        Runs `n_orientations` passes. Barcodes found in the Up (standard) pass
        carry a reliable pixel bbox; those discovered only in a rotated pass are
        marked `spatial_reliable=False` with a zeroed bbox — they provide a
        payload for lookup but are skipped by `associate_barcodes_to_crops`.

        Vision needs a file/CGImage, so the array is written to a short-lived
        temp file (which also strips EXIF, keeping coords aligned with cv2 crops).
        """
        height, width = image.shape[:2]
        tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
        tmp.close()
        try:
            cv2.imwrite(tmp.name, image)
            detections = self._detect_multi(tmp.name, width, height)
        finally:
            os.unlink(tmp.name)
        return [self._with_corners(d) for d in detections]

    def scan_grid(
        self,
        image: np.ndarray,
        grid_n: int = 2,
        overlap_frac: float = 0.1,
    ) -> list[BarcodeDetection]:
        """Scan a grid_n × grid_n tile partition of the image.

        Addresses the case where barcodes are small relative to the full frame —
        tiling gives Vision a higher effective resolution on each region. Each tile
        is scanned with the full multi-orientation pass; detections are mapped back
        to full-image pixel coordinates before deduplication.

        Tiles overlap by `overlap_frac` of their size on each edge to reduce the
        chance of a barcode being cut by a seam. A full-image pass is also run so
        that any barcode wider than the overlap zone (and therefore still split
        across both tiles) is always seen intact. Across all passes the detection
        with the largest bbox area wins; non-spatial detections (rotated passes)
        fall back to first-seen.
        """
        if grid_n == 1:
            return self.scan_array(image)

        height, width = image.shape[:2]
        tile_w = width / grid_n
        tile_h = height / grid_n

        best: dict[str, BarcodeDetection] = {}  # payload -> best detection so far

        def _merge(det: BarcodeDetection) -> None:
            prev = best.get(det.value)
            if prev is None or det.area > prev.area:
                best[det.value] = det

        # Full-image pass first: catches any barcode that spans a seam. Tile
        # passes can only improve on this with a larger (more zoomed-in) bbox.
        for det in self.scan_array(image):
            _merge(det)

        for row in range(grid_n):
            for col in range(grid_n):
                x0 = max(0, int(col * tile_w - overlap_frac * tile_w))
                y0 = max(0, int(row * tile_h - overlap_frac * tile_h))
                x1 = min(width, int((col + 1) * tile_w + overlap_frac * tile_w))
                y1 = min(height, int((row + 1) * tile_h + overlap_frac * tile_h))

                for det in self.scan_array(image[y0:y1, x0:x1]):
                    if det.spatial_reliable:
                        bx0, by0, bx1, by1 = det.bbox
                        full_bbox: BBox = (bx0 + x0, by0 + y0, bx1 + x0, by1 + y0)
                        full_corners = tuple(
                            (cx + x0, cy + y0) for cx, cy in det.corners
                        )
                        det = BarcodeDetection(
                            det.value, det.symbology, full_bbox, full_corners, True
                        )
                    _merge(det)

        return list(best.values())

    def _detect_multi(self, image_path: str, width: int, height: int) -> list[BarcodeDetection]:
        """Run VNDetectBarcodesRequest for each configured orientation.

        Deduplicates by payload across passes. The Up pass is always attempted
        first (it is position 0 in _SCAN_ORIENTATIONS) so that, when a barcode
        is visible in multiple orientations, the reliable bbox is recorded.
        """
        url = Quartz.CFURLCreateFromFileSystemRepresentation(
            None, image_path.encode(), len(image_path), False
        )
        up_orientation = Quartz.kCGImagePropertyOrientationUp
        seen: set[str] = set()
        detections: list[BarcodeDetection] = []

        for orientation in self._orientations:
            handler = Vision.VNImageRequestHandler.alloc().initWithURL_orientation_options_(
                url, orientation, {}
            )
            request = Vision.VNDetectBarcodesRequest.alloc().init()
            handler.performRequests_error_([request], None)

            for obs in (request.results() or []):
                payload = obs.payloadStringValue()
                if not payload:
                    continue
                value = str(payload).strip()
                if not value or value in seen:
                    continue
                seen.add(value)

                # Bbox from a rotated pass is in the rotated frame — unusable for
                # spatial join without a coordinate transform. Record it as zeroed
                # and let the caller decide based on spatial_reliable.
                spatial_reliable = (orientation == up_orientation)
                bbox: BBox = (
                    self._bbox_to_pixels(obs.boundingBox(), width, height)
                    if spatial_reliable
                    else (0, 0, 0, 0)
                )
                detections.append(BarcodeDetection(
                    value=value,
                    symbology=_clean_symbology(obs.symbology()),
                    bbox=bbox,
                    corners=tuple(),
                    spatial_reliable=spatial_reliable,
                ))

        return detections

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
        return BarcodeDetection(d.value, d.symbology, d.bbox, corners, d.spatial_reliable)

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
        if not bc.spatial_reliable:
            continue  # bbox is in a rotated frame; can't do a meaningful spatial join
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
