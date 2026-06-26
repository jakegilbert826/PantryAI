"""
E2E experiment 1 — image directory → segmentation → OCR → canonicalization.

Pipeline:
  1. Segment each input image into food-item crops (SegmentationService).
  2. Save crops to a working output directory + a per-image QA overlay.
  3. OCR each crop on-device (OCRService).
  4. Resolve the OCR text to the top-N canonical matches (CanonicalizationService).
  5. Render a single self-contained HTML report pairing each crop with its
     ranked canonical candidates.

Run from this directory:
    ../.venv/bin/python exp_1.py
"""

from __future__ import annotations

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
for service_dir in ("segmentation_service", "ocr_service", "canonicalization_service"):
    sys.path.insert(0, str(SRC_ROOT / service_dir))

from segmentation import Detection, SegmentationService          # noqa: E402
from ocr import OCRService                                       # noqa: E402
from canonicalization import (                                   # noqa: E402
    CanonicalizationService,
    CoarseType,
    InflowSource,
)
from report import MatchRow, ReportItem, render_report           # noqa: E402


# --------------------------------------------------------------------------- config

@dataclass
class ExperimentConfig:
    input_dir: Path = DATA_ROOT / "cv_input"
    crops_dir: Path = DATA_ROOT / "work" / "crops"
    report_path: Path = DATA_ROOT / "work" / "exp_1_report.html"
    model_path: Path = DATA_ROOT / "models" / "yoloe-26n-seg.pt"
    classes: tuple[str, ...] = ("product", "produce")
    confidence_threshold: float = 0.2
    top_n: int = 5
    source: InflowSource = InflowSource.PANTRY_SCAN


# Map coarse detector labels → canonicalization CoarseType (enables veto + boost).
_LABEL_TO_COARSE: dict[str, CoarseType] = {
    "produce": CoarseType.PRODUCE,
}


def _coarse_type_for(label: str) -> Optional[CoarseType]:
    return _LABEL_TO_COARSE.get(label.lower())


# --------------------------------------------------------------------------- pipeline

def _process_detection(
    det: Detection,
    source_name: str,
    crops_dir: Path,
    ocr: OCRService,
    canon: CanonicalizationService,
    cfg: ExperimentConfig,
) -> ReportItem:
    crop_path = crops_dir / f"{Path(source_name).stem}_box_{det.box_id}.jpg"
    cv2.imwrite(str(crop_path), det.crop)

    ocr_lines = ocr.read_text(crop_path)
    ocr_text = " ".join(ocr_lines)

    candidates = canon.resolve_top_n(
        ocr_text,
        n=cfg.top_n,
        source=cfg.source,
        coarse_type=_coarse_type_for(det.label),
    )
    rows = [MatchRow(c.canonical_name, c.display_name, c.score) for c in candidates]

    return ReportItem(
        source_image=source_name,
        crop_path=crop_path,
        label=det.label,
        confidence=det.confidence,
        ocr_text=ocr_text,
        candidates=rows,
    )


def run(cfg: ExperimentConfig) -> list[ReportItem]:
    cfg.crops_dir.mkdir(parents=True, exist_ok=True)

    segmenter = SegmentationService(
        cfg.model_path, classes=cfg.classes, confidence_threshold=cfg.confidence_threshold
    )
    ocr = OCRService()
    canon = CanonicalizationService.from_supabase()

    image_paths = segmenter.list_images(cfg.input_dir)
    if not image_paths:
        print(f"No images found in {cfg.input_dir}.")
        return []

    print(f"Found {len(image_paths)} images.\n" + "-" * 50)
    items: list[ReportItem] = []

    for idx, img_path in enumerate(image_paths, 1):
        print(f"[{idx}/{len(image_paths)}] {img_path.name}")
        image = segmenter.read(img_path)
        detections = segmenter.segment_array(image, source=str(img_path))

        if not detections:
            print("   no items detected")
            continue

        overlay = segmenter.draw_overlay(image, detections)
        cv2.imwrite(str(cfg.crops_dir / f"QA_OVERLAY_{img_path.name}"), overlay)

        for det in detections:
            item = _process_detection(det, img_path.name, cfg.crops_dir, ocr, canon, cfg)
            top = item.candidates[0] if item.candidates else None
            best = f"{top.display_name} ({top.score:.2f})" if top else "—"
            print(f"   box {det.box_id:>2} [{det.label}]  ocr='{item.ocr_text[:40]}'  -> {best}")
            items.append(item)

    return items


def main() -> None:
    load_dotenv(EXPERIMENTS_ROOT / ".env")  # SUPABASE_URL + SUPABASE_KEY
    cfg = ExperimentConfig()
    items = run(cfg)
    if not items:
        return
    report = render_report(items, cfg.report_path, title="E2E Exp 1 — Crop → OCR → Canonical")
    print("\n" + "=" * 50)
    print(f"Processed {len(items)} items. Report: {report}")


if __name__ == "__main__":
    main()
