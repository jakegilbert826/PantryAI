"""
E2E experiment 4 — fork of exp_1 with a cheap LLM fallback for low-confidence crops.

Pipeline (identical to exp_1 through step 4):
  1. Segment each input image into food-item crops (SegmentationService).
  2. Save crops to a working output directory + a per-image QA overlay.
  3. OCR each crop on-device (OCRService).
  4. Resolve the OCR text to the top-N canonical matches (CanonicalizationService).
  5. NEW — collect every crop whose best canonical match is below the confidence
     threshold (default 40%) and send them as ONE batched Gemini 3.1 Flash Lite
     call, passing the full canonical-name vocabulary. The model either:
       - matches the crop to an existing canonical_name,
       - proposes a brand-new food_reference row (printed as a dict, NOT written
         to the DB), or
       - returns unknown, leaving the crop marked unknown.
  6. Render the HTML report, annotated with the LLM outcome per low-confidence crop.

Run from this directory:
    ../.venv/bin/python exp_4.py

Requires GEMINI_API_KEY in the environment (or .env). Without it, step 5 is
skipped and low-confidence crops are simply marked unknown.
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
from ocr import OCRService, prominence_weights                   # noqa: E402
from canonicalization import (                                   # noqa: E402
    CanonicalizationService,
    CoarseType,
    InflowSource,
    LineInput,
)
from constants import (                                          # noqa: E402
    MAX_COMBINE_LINES,
    MAX_COMBINE_SIZE,
    SMALL_TEXT_PENALTY,
)
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
    report_path: Path = DATA_ROOT / "work" / "exp_4_report.html"
    model_path: Path = DATA_ROOT / "models" / "yoloe-26n-seg.pt"
    # model_path: Path = DATA_ROOT / "models" / "yoloe-26n-seg-pf.pt"
    # classes: tuple[str, ...] = tuple()
    classes: tuple[str, ...] = ("product", "produce", "bottle", "bag", "packet", "object", "box", "cardboard box", "carton", "jar", "can", "tin", "canned food", "pouch", "plastic pouch", "sachet", "sack", "plastic bag", "clear plastic bag", "ziplock bag", "tub", "container", "fruit", "vegetable")
    confidence_threshold: float = 0.4
    top_n: int = 5
    source: InflowSource = InflowSource.PANTRY_SCAN
    # Per-line OCR resolution: forward at most this many of the most-prominent
    # lines (None = all), and how hard to penalize small text (0..1).
    top_n_lines: Optional[int] = None
    small_text_penalty: float = SMALL_TEXT_PENALTY
    # Multi-line name recombination (joins of the top-K prominent lines).
    max_combine_lines: int = MAX_COMBINE_LINES
    max_combine_size: int = MAX_COMBINE_SIZE
    # NEW — crops whose best deterministic match scores below this are sent to
    # the LLM fallback. "confidence less than 40%".
    llm_fallback_threshold: float = 0.40


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

    # Keep Vision's per-line structure (bbox prominence + reading order) instead
    # of collapsing it into one blob — see canon.resolve_top_n_lines for why.
    observations = ocr.read_observations(crop_path)
    weights = prominence_weights(observations)
    lines = [
        LineInput(obs.text.strip(), prominence, order=i)
        for i, (obs, prominence) in enumerate(zip(observations, weights))
        if obs.text.strip()
    ]
    # Optional hard cap on forwarded lines (top-N by prominence), order preserved.
    if cfg.top_n_lines is not None and len(lines) > cfg.top_n_lines:
        keep = {l.order for l in sorted(lines, key=lambda l: l.prominence, reverse=True)[:cfg.top_n_lines]}
        lines = [l for l in lines if l.order in keep]
    # Display string lists lines tallest-first.
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


def _box_key(item: ReportItem) -> str:
    """Stable id for a crop across the deterministic and LLM passes."""
    return item.crop_path.stem


def _llm_fallback(
    items: list[ReportItem],
    canon: CanonicalizationService,
    cfg: ExperimentConfig,
) -> None:
    """Step 5 — batch the low-confidence crops through Gemini and apply results.

    Low confidence = best deterministic candidate scores below the threshold
    (this also covers crops with no candidates at all). Mutates `items` in place,
    annotating each with the LLM outcome and, for matches, prepending the
    LLM-chosen canonical as the new top candidate. New food_reference rows are
    printed as dicts but never written to the DB.
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
            # Surface the LLM choice as the new top candidate for the report.
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

    # Step 5 — LLM fallback for everything the deterministic cascade was unsure of.
    _llm_fallback(items, canon, cfg)

    return items


def main() -> None:
    load_dotenv(EXPERIMENTS_ROOT / ".env")  # SUPABASE_URL + SUPABASE_KEY + GEMINI_API_KEY
    cfg = ExperimentConfig()
    items = run(cfg)
    if not items:
        return
    report = render_report(items, cfg.report_path, title="E2E Exp 4 — Crop → OCR → Canonical (+ LLM fallback)")
    print("\n" + "=" * 50)
    print(f"Processed {len(items)} items. Report: {report}")


if __name__ == "__main__":
    main()
