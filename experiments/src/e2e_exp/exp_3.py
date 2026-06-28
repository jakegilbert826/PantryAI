"""
E2E experiment 3 — NO segmentation, 3x3 TILED OCR. Same question as exp_2
("which foods does the text mention?"), but fixes exp_2's bottleneck.

exp_2 showed the limiter wasn't the matcher — it was OCR resolution: a whole-frame
Vision pass gives each small label too few pixels, so labels come back garbled
("GHT THICKENED CREA", "nels"). This variant keeps the detector OUT but slices
the frame into an overlapping 3x3 grid and OCRs each tile, so every label is read
at ~3x the linear resolution. Tile observations are transformed back into
full-image coordinates, de-duplicated across the overlaps, and merged into one
line set fed to the SAME FoodScanner as exp_2.

Cost: 9 OCR passes per image instead of 1 (still detector-free). Overlap
(`overlap`) keeps names that straddle a tile boundary from being cut.

Pipeline:
  1. List input images (glob).
  2. Tile each image 3x3 with overlap; OCR each tile; map lines back to full-image
     coords; dedup overlap duplicates.
  3. FoodScanner.scan over the merged lines (exp2_foodscan).
  4. Render the exp_2 report + QA overlay.

Originals untouched. Reuses exp2_foodscan + exp2_report, and the overlay helpers
from exp_2.

Run from this directory:
    ../.venv/bin/python exp_3.py
"""

from __future__ import annotations

import glob
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import cv2
from dotenv import load_dotenv

SRC_ROOT = Path(__file__).resolve().parent.parent          # .../experiments/src
EXPERIMENTS_ROOT = SRC_ROOT.parent                          # .../experiments
DATA_ROOT = EXPERIMENTS_ROOT / "data"
for service_dir in ("ocr_service", "canonicalization_service"):
    sys.path.insert(0, str(SRC_ROOT / service_dir))

from ocr import OCRService, TextObservation, prominence_weights   # noqa: E402
from canonicalization import (                                    # noqa: E402
    CanonicalizationService,
    InflowSource,
    LineInput,
)
from exp2_foodscan import FoodScanner                             # noqa: E402
from exp2_report import ScanReportItem, render_scan_report        # noqa: E402
from exp_2 import _draw_overlay                                   # noqa: E402  (shared overlay)

IMAGE_EXTENSIONS = ("*.jpg", "*.jpeg", "*.png", "*.bmp", "*.JPG", "*.JPEG", "*.PNG", "*.BMP")


# --------------------------------------------------------------------------- config

@dataclass
class ExperimentConfig:
    input_dir: Path = DATA_ROOT / "cv_input"
    report_path: Path = DATA_ROOT / "work" / "exp_3_report.html"
    overlay_dir: Path = DATA_ROOT / "work" / "exp_3_overlays"
    tile_dir: Path = DATA_ROOT / "work" / "exp_3_tiles"
    grid: int = 6
    overlap: float = 0.15            # tile padding per side, as a fraction of a cell
    dedup_iou: float = 0.5           # merge same-text lines overlapping this much
    source: InflowSource = InflowSource.PANTRY_SCAN
    present_threshold: float = 0.6
    small_text_penalty: float = 0.0  # off — see exp2_foodscan rationale
    max_join: int = 3
    draw_overlay: bool = True


# --------------------------------------------------------------------------- helpers

def _list_images(image_dir: Path) -> list[Path]:
    found: set[Path] = set()
    for ext in IMAGE_EXTENSIONS:
        found.update(Path(p) for p in glob.glob(str(image_dir / ext)))
    return sorted(found)


def _tile_rects(width: int, height: int, grid: int, overlap: float) -> list[tuple[int, int, int, int]]:
    """Pixel rects for a grid x grid tiling, each padded by `overlap` of a cell on
    every side and clipped to the frame (so neighbours share a margin)."""
    cell_w, cell_h = width / grid, height / grid
    pad_x, pad_y = cell_w * overlap, cell_h * overlap
    rects = []
    for r in range(grid):
        for c in range(grid):
            x0 = max(0, int(c * cell_w - pad_x))
            x1 = min(width, int((c + 1) * cell_w + pad_x))
            y0 = max(0, int(r * cell_h - pad_y))
            y1 = min(height, int((r + 1) * cell_h + pad_y))
            rects.append((x0, y0, x1, y1))
    return rects


def _tile_obs_to_full(
    obs: TextObservation, x0: int, y0: int, tw: int, th: int, width: int, height: int
) -> TextObservation:
    """Re-express a tile-local Vision observation in full-image normalized,
    bottom-left coords so it is indistinguishable from a whole-image OCR line
    (prominence_weights + the exp_2 overlay then work unchanged)."""
    tx, ty, tnw, tnh = obs.bbox
    fx0 = x0 + tx * tw
    fx1 = x0 + (tx + tnw) * tw
    fy_top = y0 + (1.0 - (ty + tnh)) * th   # tile origin is bottom-left
    fy_bot = y0 + (1.0 - ty) * th
    return TextObservation(
        text=obs.text,
        confidence=obs.confidence,
        bbox=(fx0 / width, 1.0 - fy_bot / height, (fx1 - fx0) / width, (fy_bot - fy_top) / height),
    )


def _iou(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    ax0, ay0, aw, ah = a
    bx0, by0, bw, bh = b
    ax1, ay1, bx1, by1 = ax0 + aw, ay0 + ah, bx0 + bw, by0 + bh
    iw = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    ih = max(0.0, min(ay1, by1) - max(ay0, by0))
    inter = iw * ih
    union = aw * ah + bw * bh - inter
    return inter / union if union > 0 else 0.0


def _dedup(observations: list[TextObservation], iou_thresh: float) -> list[TextObservation]:
    """Drop the same text read in two overlapping tiles (same string + boxes that
    overlap above iou_thresh). Distinct items sharing a word ("organic") survive
    because their boxes don't overlap."""
    kept: list[TextObservation] = []
    for o in observations:
        key = o.text.strip().lower()
        if not key:
            continue
        if any(key == k.text.strip().lower() and _iou(o.bbox, k.bbox) > iou_thresh for k in kept):
            continue
        kept.append(o)
    return kept


def _ocr_tiled(ocr: OCRService, image, cfg: ExperimentConfig, stem: str) -> list[TextObservation]:
    height, width = image.shape[:2]
    merged: list[TextObservation] = []
    for k, (x0, y0, x1, y1) in enumerate(_tile_rects(width, height, cfg.grid, cfg.overlap)):
        tw, th = x1 - x0, y1 - y0
        if tw <= 0 or th <= 0:
            continue
        tile_path = cfg.tile_dir / f"{stem}_tile_{k}.jpg"
        cv2.imwrite(str(tile_path), image[y0:y1, x0:x1])
        for obs in ocr.read_observations(tile_path):
            if obs.text.strip():
                merged.append(_tile_obs_to_full(obs, x0, y0, tw, th, width, height))
    return _dedup(merged, cfg.dedup_iou)


# --------------------------------------------------------------------------- pipeline

def run(cfg: ExperimentConfig) -> list[ScanReportItem]:
    cfg.overlay_dir.mkdir(parents=True, exist_ok=True)
    cfg.tile_dir.mkdir(parents=True, exist_ok=True)
    cfg.report_path.parent.mkdir(parents=True, exist_ok=True)

    ocr = OCRService()
    canon = CanonicalizationService.from_supabase()
    scanner = FoodScanner(canon)

    image_paths = _list_images(cfg.input_dir)
    if not image_paths:
        print(f"No images found in {cfg.input_dir}.")
        return []

    print(f"Found {len(image_paths)} images.  Tiling {cfg.grid}x{cfg.grid}.\n" + "-" * 50)
    items: list[ScanReportItem] = []

    for idx, img_path in enumerate(image_paths, 1):
        print(f"[{idx}/{len(image_paths)}] {img_path.name}")
        image = cv2.imread(str(img_path))
        if image is None:
            print("   unreadable")
            continue

        observations = _ocr_tiled(ocr, image, cfg, Path(img_path.name).stem)
        weights = prominence_weights(observations)
        lines = [
            LineInput(obs.text.strip(), prominence, order=i)
            for i, (obs, prominence) in enumerate(zip(observations, weights))
            if obs.text.strip()
        ]

        foods = scanner.scan(
            lines,
            source=cfg.source,
            present_threshold=cfg.present_threshold,
            small_text_penalty=cfg.small_text_penalty,
            max_join=cfg.max_join,
        )

        print(f"   {len(observations)} merged OCR lines -> {len(foods)} foods")
        for f in foods:
            ev = f.evidence[0] if f.evidence else ""
            print(f"     {f.score:.2f}  {f.display_name:<24} ({f.canonical_name})  <- '{ev[:30]}'")

        overlay_path: Optional[Path] = None
        if cfg.draw_overlay:
            kept = {f.canonical_name for f in foods}
            overlay = _draw_overlay(image, observations, weights, scanner, kept, cfg)
            overlay_path = cfg.overlay_dir / f"OVERLAY_{img_path.name}"
            cv2.imwrite(str(overlay_path), overlay)

        items.append(ScanReportItem(
            source_image=img_path.name,
            image_path=img_path,
            ocr_line_count=len(observations),
            overlay_path=overlay_path,
            foods=foods,
        ))

    return items


def main() -> None:
    load_dotenv(EXPERIMENTS_ROOT / ".env")
    cfg = ExperimentConfig()
    items = run(cfg)
    if not items:
        return
    report = render_scan_report(items, cfg.report_path,
                                title=f"E2E Exp 3 — {cfg.grid}x{cfg.grid} Tiled Food Scan (no segmentation)")
    total = sum(len(i.foods) for i in items)
    print("\n" + "=" * 50)
    print(f"Scanned {len(items)} images, {total} foods identified. Report: {report}")


if __name__ == "__main__":
    main()
