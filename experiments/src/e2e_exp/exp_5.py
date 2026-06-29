"""
E2E experiment 5 — barcode-first, OCR-second resolution.

Fork of exp_4 that adds a global barcode pass in front of the OCR cascade. The
insight: when a product's barcode is visible it is a near-perfect identity key
(L1), so there is no need to OCR-and-fuzzy-match that crop at all.

Pipeline:
  1. Segment the image into food-item crops (SegmentationService / YOLOE).
  2. Scan the WHOLE image once for barcodes (BarcodeService), keeping each
     barcode's pixel bbox.
  3. Spatially join barcodes to crops (associate_barcodes_to_crops) — tolerant
     enough that a barcode on the side of a product still binds to the crop whose
     front face was detected (overlap-over-barcode-area + expanded-box center).
  4. For each crop:
       - if a barcode is associated:
           → look the barcode up on Open Food Facts, take the product name,
             canonicalize it (alias → lexical → fuzzy). Mark resolved via barcode;
             SKIP OCR entirely. (If OFF has no record, fall back to the OCR path.)
       - else:
           → OCR → per-line canonicalization (same as exp_4).
  5. LLM fallback (one batched Gemini call) for everything still low-confidence —
     this covers OCR crops AND barcode crops whose OFF name didn't canonicalize.
  6. Render the HTML report, annotated with barcode / OCR / LLM provenance.

Run from this directory:
    ../.venv/bin/python exp_5.py

Requires SUPABASE_URL / SUPABASE_KEY (canonical vocab) and, for step 5,
GEMINI_API_KEY in the environment (or .env). Open Food Facts needs no key.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
from dotenv import load_dotenv

# Make the sibling service packages importable regardless of CWD.
SRC_ROOT = Path(__file__).resolve().parent.parent          # .../experiments/src
EXPERIMENTS_ROOT = SRC_ROOT.parent                          # .../experiments
DATA_ROOT = EXPERIMENTS_ROOT / "data"
for service_dir in ("segmentation_service", "ocr_service", "canonicalization_service", "barcode_service"):
    sys.path.insert(0, str(SRC_ROOT / service_dir))

from segmentation import Detection, SegmentationService          # noqa: E402
from ocr import OCRService, prominence_weights                   # noqa: E402
from canonicalization import (                                   # noqa: E402
    CanonicalizationService,
    Candidate,
    CoarseType,
    InflowSource,
    LineInput,
)
from constants import (                                          # noqa: E402
    MAX_COMBINE_LINES,
    MAX_COMBINE_SIZE,
    SMALL_TEXT_PENALTY,
)
from barcode import BarcodeService, BarcodeDetection, associate_barcodes_to_crops  # noqa: E402
from openfoodfacts import OpenFoodFactsClient                    # noqa: E402
from report import MatchRow, ReportItem, render_report           # noqa: E402
from gemini_resolver import (                                    # noqa: E402
    GeminiResolver,
    LLMBox,
    LLMStatus,
)


# --------------------------------------------------------------------------- config

@dataclass
class ExperimentConfig:
    input_dir: Path = DATA_ROOT / "cv_input"
    crops_dir: Path = DATA_ROOT / "work" / "crops"
    report_path: Path = DATA_ROOT / "work" / "exp_5_report.html"
    model_path: Path = DATA_ROOT / "models" / "yoloe-26n-seg.pt"
    # model_path: Path = DATA_ROOT / "models" / "yoloe-26n-seg-pf.pt"
    # classes: tuple[str, ...] = tuple()
    classes: tuple[str, ...] = ("product", "produce", "bottle", "bag", "packet", "object", "box", "cardboard box", "carton", "jar", "can", "tin", "canned food", "pouch", "plastic pouch", "sachet", "sack", "plastic bag", "clear plastic bag", "ziplock bag", "tub", "container", "fruit", "vegetable")
    confidence_threshold: float = 0.2
    top_n: int = 5
    source: InflowSource = InflowSource.PANTRY_SCAN
    # Per-line OCR resolution (same knobs as exp_4).
    top_n_lines: Optional[int] = None
    small_text_penalty: float = SMALL_TEXT_PENALTY
    max_combine_lines: int = MAX_COMBINE_LINES
    max_combine_size: int = MAX_COMBINE_SIZE
    # LLM fallback: crops whose best deterministic match is below this go to Gemini.
    llm_fallback_threshold: float = 0.40
    # Barcode → crop spatial join tolerance. A barcode binds to a crop when the
    # barcode center is inside the crop box grown by `barcode_margin_frac`, OR at
    # least `barcode_overlap_floor` of the barcode area overlaps the crop.
    barcode_margin_frac: float = 0.15
    barcode_overlap_floor: float = 0.30


# Map coarse detector labels → canonicalization CoarseType (enables veto + boost).
_LABEL_TO_COARSE: dict[str, CoarseType] = {
    "produce": CoarseType.PRODUCE,
}


def _coarse_type_for(label: str) -> Optional[CoarseType]:
    return _LABEL_TO_COARSE.get(label.lower())


def _box_key(item: ReportItem) -> str:
    """Stable id for a crop across the deterministic and LLM passes."""
    return item.crop_path.stem


def _save_crop(det: Detection, source_name: str, crops_dir: Path) -> Path:
    crop_path = crops_dir / f"{Path(source_name).stem}_box_{det.box_id}.jpg"
    cv2.imwrite(str(crop_path), det.crop)
    return crop_path


# --------------------------------------------------------------------------- OCR path

def _process_detection(
    det: Detection,
    source_name: str,
    crops_dir: Path,
    ocr: OCRService,
    canon: CanonicalizationService,
    cfg: ExperimentConfig,
) -> ReportItem:
    """OCR → per-line canonicalization for a crop with no associated barcode.
    (Identical to exp_4's OCR path.)"""
    crop_path = _save_crop(det, source_name, crops_dir)

    observations = ocr.read_observations(crop_path)
    weights = prominence_weights(observations)
    lines = [
        LineInput(obs.text.strip(), prominence, order=i)
        for i, (obs, prominence) in enumerate(zip(observations, weights))
        if obs.text.strip()
    ]
    if cfg.top_n_lines is not None and len(lines) > cfg.top_n_lines:
        keep = {l.order for l in sorted(lines, key=lambda l: l.prominence, reverse=True)[:cfg.top_n_lines]}
        lines = [l for l in lines if l.order in keep]
    ocr_text = " | ".join(l.text for l in sorted(lines, key=lambda l: l.prominence, reverse=True))

    candidates = canon.resolve_top_n_lines(
        lines,
        n=cfg.top_n,
        source=cfg.source,
        coarse_type=_coarse_type_for(det.label),
        small_text_penalty=cfg.small_text_penalty,
        max_combine_lines=cfg.max_combine_lines,
        max_combine_size=cfg.max_combine_size,
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


# --------------------------------------------------------------------------- barcode path

def _process_barcode_detection(
    det: Detection,
    barcode_value: str,
    source_name: str,
    crops_dir: Path,
    off: OpenFoodFactsClient,
    canon: CanonicalizationService,
    cfg: ExperimentConfig,
) -> Optional[ReportItem]:
    """Resolve a crop via its barcode: barcode → Open Food Facts name →
    canonicalization. OCR is skipped. Returns None when OFF has no usable record
    so the caller can fall back to the OCR path.

    The OFF product name is placed in `ocr_text` so the shared LLM fallback can
    pick this crop up if the name didn't canonicalize confidently.
    """
    crop_path = _save_crop(det, source_name, crops_dir)
    product = off.lookup(barcode_value)
    name = product.best_name if product else None
    if not name:
        return None  # no OFF match → let the caller OCR this crop instead

    candidates = canon.resolve_top_n(
        name,
        n=cfg.top_n,
        source=InflowSource.BARCODE,
        coarse_type=_coarse_type_for(det.label),
        brand_hint=product.brand_hint,
    )
    rows = [MatchRow(c.canonical_name, c.display_name, c.score) for c in candidates]

    top = rows[0] if rows else None
    if top is not None:
        note = f"OFF '{name}' → {top.display_name} ({top.canonical_name}) @ {top.score:.2f}"
    else:
        note = f"OFF '{name}' → no canonical match (LLM fallback)"

    return ReportItem(
        source_image=source_name,
        crop_path=crop_path,
        label=det.label,
        confidence=det.confidence,
        ocr_text=name,            # OFF name feeds the LLM fallback if low-confidence
        candidates=rows,
        barcode=barcode_value,
        barcode_note=note,
    )


# --------------------------------------------------------------------------- orphan barcodes

def _process_orphan_barcode(
    bc: BarcodeDetection,
    image: np.ndarray,
    source_name: str,
    crops_dir: Path,
    off: OpenFoodFactsClient,
    canon: CanonicalizationService,
    cfg: ExperimentConfig,
) -> Optional[ReportItem]:
    """Resolve a barcode that didn't match any YOLOE crop.

    Hard rule: if OFF has a usable record, this item always makes it to the
    output regardless of whether YOLOE detected the product. The barcode's own
    bbox (padded slightly) is saved as the representative crop image.
    Returns None if OFF has no record for this barcode.
    """
    product = off.lookup(bc.value)
    name = product.best_name if product else None
    if not name:
        return None

    h, w = image.shape[:2]
    xmin, ymin, xmax, ymax = bc.bbox
    pad = 20
    crop_img = image[
        max(0, ymin - pad):min(h, ymax + pad),
        max(0, xmin - pad):min(w, xmax + pad),
    ]
    crop_path = crops_dir / f"{Path(source_name).stem}_barcode_{bc.value}.jpg"
    cv2.imwrite(str(crop_path), crop_img)

    candidates = canon.resolve_top_n(
        name,
        n=cfg.top_n,
        source=InflowSource.BARCODE,
        coarse_type=None,
        brand_hint=product.brand_hint,
    )
    rows = [MatchRow(c.canonical_name, c.display_name, c.score) for c in candidates]
    top = rows[0] if rows else None
    note = (
        f"OFF '{name}' → {top.display_name} ({top.canonical_name}) @ {top.score:.2f} [no YOLOE crop]"
        if top else
        f"OFF '{name}' → no canonical match [no YOLOE crop]"
    )

    return ReportItem(
        source_image=source_name,
        crop_path=crop_path,
        label="barcode",
        confidence=1.0,
        ocr_text=name,
        candidates=rows,
        barcode=bc.value,
        barcode_note=note,
    )


# --------------------------------------------------------------------------- LLM fallback

def _llm_fallback(
    items: list[ReportItem],
    canon: CanonicalizationService,
    cfg: ExperimentConfig,
) -> None:
    """Batch every still-low-confidence crop through Gemini (one call).

    Low confidence = best deterministic candidate below the threshold (covers
    crops with no candidates, OCR crops, and barcode crops whose OFF name didn't
    canonicalize). Mutates `items` in place. (Same behaviour as exp_4.)
    """
    low_conf = [
        it for it in items
        if not it.candidates or it.candidates[0].score < cfg.llm_fallback_threshold
    ]
    if not low_conf:
        print("\nNo low-confidence crops — LLM fallback not needed.")
        return

    resolver = GeminiResolver()
    canonical_names = [ref.canonical_name for ref in canon.references]
    display_by_canonical = {ref.canonical_name: ref.display_name for ref in canon.references}

    boxes = [
        LLMBox(box_id=_box_key(it), ocr_text=it.ocr_text, hint=it.label)
        for it in low_conf
    ]

    print(
        f"\n{'=' * 50}\nLLM fallback: {len(boxes)} low-confidence crops "
        f"(< {cfg.llm_fallback_threshold:.0%}) -> 1 batched {resolver.model} call"
        f" over {len(canonical_names)} canonical names."
    )

    resolutions = resolver.resolve_batch(boxes, canonical_names)

    for it in low_conf:
        res = resolutions.get(_box_key(it))
        if res is None or res.status is LLMStatus.UNKNOWN:
            it.llm_note = "unknown — left unresolved"
            print(f"   {_box_key(it):<28} ocr='{it.ocr_text[:34]}'  -> UNKNOWN")
            continue

        if res.status is LLMStatus.MATCHED:
            display = display_by_canonical.get(res.canonical_name, res.canonical_name)
            it.candidates = [MatchRow(res.canonical_name, display, res.confidence), *it.candidates]
            it.llm_note = f"matched → {display} ({res.canonical_name}) @ {res.confidence:.2f}"
            print(f"   {_box_key(it):<28} ocr='{it.ocr_text[:34]}'  -> MATCH {res.canonical_name} ({res.confidence:.2f})")

        elif res.status is LLMStatus.NEW:
            entry = res.new_entry.as_dict()
            it.llm_note = (
                f"NEW food_reference proposed: {res.new_entry.display_name} "
                f"({res.new_entry.canonical_name}) @ {res.confidence:.2f}"
            )
            print(f"   {_box_key(it):<28} ocr='{it.ocr_text[:34]}'  -> NEW food_reference (not written to DB):")
            print(f"      {entry}")

        elif res.status is LLMStatus.NOT_FOOD:
            it.llm_note = f"not food — skipped @ {res.confidence:.2f}"
            print(f"   {_box_key(it):<28} ocr='{it.ocr_text[:34]}'  -> NOT FOOD ({res.confidence:.2f})")


# --------------------------------------------------------------------------- run

def run(cfg: ExperimentConfig) -> list[ReportItem]:
    cfg.crops_dir.mkdir(parents=True, exist_ok=True)

    segmenter = SegmentationService(
        cfg.model_path, classes=cfg.classes, confidence_threshold=cfg.confidence_threshold
    )
    barcode_svc = BarcodeService()
    ocr = OCRService()
    off = OpenFoodFactsClient()
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

        # Barcode scan always runs — orphan barcodes with an OFF match must reach
        # the output even when YOLOE found nothing.
        barcodes = barcode_svc.scan_grid(image, grid_n=2)

        if not detections:
            print("   no items detected")
            for bc in barcodes:
                if not bc.spatial_reliable:
                    continue
                item = _process_orphan_barcode(bc, image, img_path.name, cfg.crops_dir, off, canon, cfg)
                if item is not None:
                    top = item.candidates[0] if item.candidates else None
                    best = f"{top.display_name} ({top.score:.2f})" if top else "—"
                    print(f"   orphan barcode {bc.value}  -> {best}")
                    items.append(item)
            continue

        assoc = associate_barcodes_to_crops(
            barcodes, detections,
            margin_frac=cfg.barcode_margin_frac,
            overlap_floor=cfg.barcode_overlap_floor,
        )
        print(f"   {len(barcodes)} barcode(s) decoded, {len(assoc)} joined to crops")

        overlay = segmenter.draw_overlay(image, detections)
        overlay = barcode_svc.draw_overlay(overlay, barcodes)
        cv2.imwrite(str(cfg.crops_dir / f"QA_OVERLAY_{img_path.name}"), overlay)

        for det in detections:
            bc = assoc.get(det.box_id)
            if bc is not None:
                item = _process_barcode_detection(
                    det, bc.value, img_path.name, cfg.crops_dir, off, canon, cfg
                )
                if item is None:
                    # OFF had no record — fall back to OCR but keep the barcode note.
                    item = _process_detection(det, img_path.name, cfg.crops_dir, ocr, canon, cfg)
                    item.barcode = bc.value
                    item.barcode_note = "no Open Food Facts match — OCR fallback"
                route = f"BARCODE {bc.value}"
            else:
                item = _process_detection(det, img_path.name, cfg.crops_dir, ocr, canon, cfg)
                route = f"ocr='{item.ocr_text[:34]}'"

            top = item.candidates[0] if item.candidates else None
            best = f"{top.display_name} ({top.score:.2f})" if top else "—"
            print(f"   box {det.box_id:>2} [{det.label}]  {route}  -> {best}")
            items.append(item)

        # Hard rule: barcodes not joined to any crop but resolved via OFF always
        # make it to the output. The barcode's own bbox is used as the crop image.
        matched_payloads = {bc.value for bc in assoc.values()}
        for bc in barcodes:
            if bc.value in matched_payloads or not bc.spatial_reliable:
                continue
            item = _process_orphan_barcode(bc, image, img_path.name, cfg.crops_dir, off, canon, cfg)
            if item is not None:
                top = item.candidates[0] if item.candidates else None
                best = f"{top.display_name} ({top.score:.2f})" if top else "—"
                print(f"   orphan barcode {bc.value}  -> {best}")
                items.append(item)

    # LLM fallback for everything the deterministic cascade was unsure of.
    _llm_fallback(items, canon, cfg)

    return items


def main() -> None:
    load_dotenv(EXPERIMENTS_ROOT / ".env")  # SUPABASE_URL + SUPABASE_KEY + GEMINI_API_KEY
    cfg = ExperimentConfig()
    items = run(cfg)
    if not items:
        return
    report = render_report(
        items, cfg.report_path,
        title="E2E Exp 5 — Barcode-first → OFF → Canonical (+ OCR / LLM fallback)",
    )
    print("\n" + "=" * 50)
    print(f"Processed {len(items)} items. Report: {report}")


if __name__ == "__main__":
    main()
