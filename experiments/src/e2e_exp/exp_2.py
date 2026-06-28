"""
E2E experiment 2 — NO segmentation. OCR the whole frame, identify every food the
text mentions.

Rationale: exp_1's detector→crop→OCR pipeline never sees an item the detector
misses (occluded, odd packaging, out of open-vocab), even when its label is
plainly legible. exp_2 drops the detector entirely: OCR the whole image once and
mine ALL recognized text for known foods. This recovers undetected items at the
cost of precision — fine print and ingredient lists can falsely register as
items, controlled here by a presence threshold + bounding-box prominence bias.

Pipeline:
  1. List input images (glob — no detector loaded).
  2. OCR the whole image once (OCRService.read_observations).
  3. Prominence-weight every line, then extract a SET of foods via FoodScanner
     (exp2_foodscan) — reuses the canonicalization cascade, aggregating across
     lines instead of resolving a single item.
  4. Render an HTML report: each image with the ranked foods found + evidence,
     plus an optional QA overlay attributing OCR boxes to the food they voted for.

Originals untouched: ocr.py / canonicalization.py / report.py are imported as-is.
Experiment-specific logic lives in exp2_foodscan.py + exp2_report.py.

Run from this directory:
    ../.venv/bin/python exp_2.py
"""

from __future__ import annotations

import glob
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import cv2
from dotenv import load_dotenv

# Make the sibling service packages importable regardless of CWD.
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

IMAGE_EXTENSIONS = ("*.jpg", "*.jpeg", "*.png", "*.bmp", "*.JPG", "*.JPEG", "*.PNG", "*.BMP")


# --------------------------------------------------------------------------- config

@dataclass
class ExperimentConfig:
    input_dir: Path = DATA_ROOT / "cv_input"
    report_path: Path = DATA_ROOT / "work" / "exp_2_report.html"
    overlay_dir: Path = DATA_ROOT / "work" / "exp_2_overlays"
    source: InflowSource = InflowSource.PANTRY_SCAN
    # A food registers only if its prominence-weighted score clears this.
    present_threshold: float = 0.6
    # Prominence is OFF by default here. In a single crop the tallest line is the
    # product name, but across a whole multi-item frame the tallest text is just
    # one item's name (or junk — on the test image it's a price string '299a015'),
    # so penalizing smaller text discards every other item's legible label. We
    # gate on match quality alone; raise this above 0 to re-enable the bias.
    small_text_penalty: float = 0.0
    # Largest run of adjacent reading-order lines joined into one query.
    max_join: int = 3
    draw_overlay: bool = True


# --------------------------------------------------------------------------- helpers

def _list_images(image_dir: Path) -> list[Path]:
    found: set[Path] = set()
    for ext in IMAGE_EXTENSIONS:
        found.update(Path(p) for p in glob.glob(str(image_dir / ext)))
    return sorted(found)


def _obs_pixel_bbox(obs: TextObservation, width: int, height: int) -> tuple[int, int, int, int]:
    """Vision bbox (normalized, origin bottom-left) → pixel (xmin, ymin, xmax,
    ymax) with origin top-left. The y axis is flipped: Vision's y is the box
    bottom measured from the image bottom."""
    x, y, w, h = obs.bbox
    xmin = int(x * width)
    xmax = int((x + w) * width)
    ymin = int((1.0 - (y + h)) * height)  # top edge in top-left coords
    ymax = int((1.0 - y) * height)        # bottom edge in top-left coords
    return xmin, ymin, xmax, ymax


def _draw_overlay(
    image,
    observations: list[TextObservation],
    weights: list[float],
    scanner: FoodScanner,
    kept: set[str],
    cfg: ExperimentConfig,
):
    """Draw every OCR box; green + labelled when the line attributes to a food in
    the kept set (its own weighted score clears the threshold), gray otherwise.

    Attribution is per-line, so a food recovered only via a multi-line join may
    show no green box — the report's evidence column is the authoritative record.
    """
    overlay = image.copy()
    height, width = image.shape[:2]
    for obs, prominence in zip(observations, weights):
        text = obs.text.strip()
        if not text:
            continue
        x0, y0, x1, y1 = _obs_pixel_bbox(obs, width, height)
        hit = scanner.resolve_line(text, prominence, cfg.source, cfg.small_text_penalty)
        is_food = hit is not None and hit[0] in kept and hit[2] >= cfg.present_threshold
        color = (0, 180, 0) if is_food else (160, 160, 160)
        cv2.rectangle(overlay, (x0, y0), (x1, y1), color, 2 if is_food else 1)
        if is_food:
            cv2.putText(overlay, hit[1], (x0, max(0, y0 - 5)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 180, 0), 2)
    return overlay


# --------------------------------------------------------------------------- pipeline

def run(cfg: ExperimentConfig) -> list[ScanReportItem]:
    cfg.overlay_dir.mkdir(parents=True, exist_ok=True)
    cfg.report_path.parent.mkdir(parents=True, exist_ok=True)

    ocr = OCRService()
    canon = CanonicalizationService.from_supabase()
    scanner = FoodScanner(canon)

    image_paths = _list_images(cfg.input_dir)
    if not image_paths:
        print(f"No images found in {cfg.input_dir}.")
        return []

    print(f"Found {len(image_paths)} images.\n" + "-" * 50)
    items: list[ScanReportItem] = []

    for idx, img_path in enumerate(image_paths, 1):
        print(f"[{idx}/{len(image_paths)}] {img_path.name}")

        observations = ocr.read_observations(img_path)
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

        print(f"   {len(observations)} OCR lines -> {len(foods)} foods")
        for f in foods:
            ev = f.evidence[0] if f.evidence else ""
            print(f"     {f.score:.2f}  {f.display_name:<24} ({f.canonical_name})  <- '{ev[:30]}'")

        overlay_path: Optional[Path] = None
        if cfg.draw_overlay:
            image = cv2.imread(str(img_path))
            if image is not None:
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
    load_dotenv(EXPERIMENTS_ROOT / ".env")  # SUPABASE_URL + SUPABASE_KEY
    cfg = ExperimentConfig()
    items = run(cfg)
    if not items:
        return
    report = render_scan_report(items, cfg.report_path,
                                title="E2E Exp 2 — Whole-image Food Scan (no segmentation)")
    total = sum(len(i.foods) for i in items)
    print("\n" + "=" * 50)
    print(f"Scanned {len(items)} images, {total} foods identified. Report: {report}")


if __name__ == "__main__":
    main()
