"""
Self-contained HTML report for exp_2 (whole-image food scan) — LOCAL to this
experiment.

Cannot reuse e2e_exp/report.py: that renderer is crop-oriented (one card per
detected crop, keyed on `crop_path`). exp_2 has no crops — one card per source
image, showing the full frame and the ranked set of foods its text mentions,
each with the evidence fragments that triggered it. Same visual language as
report.py so the two are easy to read side by side.
"""

from __future__ import annotations

import base64
import html
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence

from exp2_foodscan import FoodHit


@dataclass
class ScanReportItem:
    """Everything the report shows for a single scanned image."""
    source_image: str
    image_path: Path
    ocr_line_count: int
    overlay_path: Path | None = None
    foods: Sequence[FoodHit] = field(default_factory=list)


def _img_data_uri(path: Path) -> str:
    data = base64.b64encode(Path(path).read_bytes()).decode("ascii")
    suffix = Path(path).suffix.lstrip(".").lower() or "jpeg"
    mime = "jpeg" if suffix in ("jpg", "jpeg") else suffix
    return f"data:image/{mime};base64,{data}"


def _score_color(score: float) -> str:
    if score >= 0.8:
        return "#1b7f3b"
    if score >= 0.5:
        return "#b8860b"
    return "#a33"


def _foods_table(foods: Sequence[FoodHit]) -> str:
    if not foods:
        return '<p class="empty">No foods identified in the text.</p>'
    rows = []
    for rank, f in enumerate(foods, 1):
        evidence = " · ".join(html.escape(e) for e in f.evidence) or "<em>—</em>"
        rows.append(
            f"<tr>"
            f"<td class='rank'>{rank}</td>"
            f"<td>{html.escape(f.display_name)}"
            f"<span class='canon'>{html.escape(f.canonical_name)}</span></td>"
            f"<td class='score' style='color:{_score_color(f.score)}'>{f.score:.2f}</td>"
            f"<td class='evidence'>{evidence}</td>"
            f"</tr>"
        )
    return (
        "<table class='foods'>"
        "<tr class='head'><td class='rank'>#</td><td>Food</td>"
        "<td class='score'>Score</td><td class='evidence'>Evidence (OCR text)</td></tr>"
        f"{''.join(rows)}</table>"
    )


def _card(item: ScanReportItem) -> str:
    img = item.overlay_path if item.overlay_path else item.image_path
    return f"""
    <div class="card">
      <div class="frame">
        <img src="{_img_data_uri(img)}" alt="frame"/>
        <div class="src">{html.escape(item.source_image)}</div>
        <div class="meta">{item.ocr_line_count} OCR lines · {len(item.foods)} foods</div>
      </div>
      <div class="detail">
        {_foods_table(item.foods)}
      </div>
    </div>"""


_STYLE = """
* { box-sizing: border-box; }
body { font-family: -apple-system, Helvetica, Arial, sans-serif; margin: 0;
       background: #f4f5f7; color: #1c1c1e; }
header { padding: 20px 28px; background: #fff; border-bottom: 1px solid #e2e2e6; }
header h1 { margin: 0; font-size: 20px; }
header p { margin: 4px 0 0; color: #6b6b70; font-size: 13px; }
.grid { display: grid; grid-template-columns: 1fr; gap: 16px; padding: 20px 28px; }
.card { display: flex; background: #fff; border: 1px solid #e2e2e6;
        border-radius: 10px; overflow: hidden; }
.frame { width: 340px; flex: none; padding: 12px; border-right: 1px solid #eee;
         display: flex; flex-direction: column; gap: 6px; }
.frame img { width: 100%; object-fit: contain; background: #fafafa; border-radius: 6px; }
.src { font-size: 11px; color: #9a9aa0; word-break: break-all; }
.meta { font-size: 12px; color: #6b6b70; }
.detail { flex: 1; padding: 14px; min-width: 0; }
table.foods { width: 100%; border-collapse: collapse; font-size: 13px; }
table.foods td { padding: 5px 8px; border-top: 1px solid #f0f0f2; vertical-align: top; }
tr.head td { border-top: none; color: #9a9aa0; font-size: 11px; font-weight: 600;
             text-transform: uppercase; letter-spacing: .03em; }
td.rank { color: #9a9aa0; width: 24px; }
td.score { text-align: right; font-variant-numeric: tabular-nums; font-weight: 600; width: 52px; }
td.evidence { color: #6b6b70; font-size: 12px; }
.canon { display: block; font-size: 10px; color: #9a9aa0; }
.empty { color: #9a9aa0; font-size: 13px; font-style: italic; }
"""


def render_scan_report(items: Sequence[ScanReportItem], output_path: str | Path,
                       title: str = "Whole-image Food Scan") -> Path:
    """Write all scanned images to a single self-contained HTML file."""
    cards = "\n".join(_card(item) for item in items)
    total = sum(len(i.foods) for i in items)
    doc = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"/>
<title>{html.escape(title)}</title><style>{_STYLE}</style></head>
<body>
  <header>
    <h1>{html.escape(title)}</h1>
    <p>{len(items)} images — {total} foods identified from text alone (no segmentation)</p>
  </header>
  <div class="grid">{cards}</div>
</body></html>"""
    out = Path(output_path)
    out.write_text(doc, encoding="utf-8")
    return out
