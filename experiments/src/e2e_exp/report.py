"""
Self-contained HTML report renderer for crop → match experiments.

Renders one card per detected item: the cropped image, the OCR text that was
fed to the matcher, and a ranked table of canonical candidates. Images are
embedded as base64 so the report is a single portable file.
"""

from __future__ import annotations

import base64
import html
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


@dataclass
class MatchRow:
    """One canonical candidate for the table (rank order preserved by caller)."""
    canonical_name: str
    display_name: str
    score: float


@dataclass
class ReportItem:
    """Everything the report shows for a single cropped food item."""
    source_image: str
    crop_path: Path
    label: str
    confidence: float
    ocr_text: str
    candidates: Sequence[MatchRow]
    # Optional note describing an LLM fallback outcome for low-confidence crops.
    llm_note: str | None = None


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


def _candidates_table(candidates: Sequence[MatchRow]) -> str:
    if not candidates:
        return '<p class="empty">No canonical matches.</p>'
    rows = []
    for rank, c in enumerate(candidates, 1):
        rows.append(
            f"<tr>"
            f"<td class='rank'>{rank}</td>"
            f"<td>{html.escape(c.display_name)}"
            f"<span class='canon'>{html.escape(c.canonical_name)}</span></td>"
            f"<td class='score' style='color:{_score_color(c.score)}'>{c.score:.2f}</td>"
            f"</tr>"
        )
    return f"<table class='matches'>{''.join(rows)}</table>"


def _card(item: ReportItem) -> str:
    ocr = html.escape(item.ocr_text) if item.ocr_text else "<em>(no text)</em>"
    llm = (
        f"<div class='ocr'><span class='tag' style='background:#3a6ea5'>LLM</span>"
        f"{html.escape(item.llm_note)}</div>"
        if item.llm_note
        else ""
    )
    return f"""
    <div class="card">
      <div class="crop">
        <img src="{_img_data_uri(item.crop_path)}" alt="crop"/>
        <div class="meta">
          <span class="label">{html.escape(item.label)}</span>
          <span class="conf">{item.confidence:.2f}</span>
        </div>
        <div class="src">{html.escape(item.source_image)}</div>
      </div>
      <div class="detail">
        <div class="ocr"><span class="tag">OCR</span>{ocr}</div>
        {_candidates_table(item.candidates)}
        {llm}
      </div>
    </div>"""


_STYLE = """
* { box-sizing: border-box; }
body { font-family: -apple-system, Helvetica, Arial, sans-serif; margin: 0;
       background: #f4f5f7; color: #1c1c1e; }
header { padding: 20px 28px; background: #fff; border-bottom: 1px solid #e2e2e6; }
header h1 { margin: 0; font-size: 20px; }
header p { margin: 4px 0 0; color: #6b6b70; font-size: 13px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(360px, 1fr));
        gap: 16px; padding: 20px 28px; }
.card { display: flex; background: #fff; border: 1px solid #e2e2e6;
        border-radius: 10px; overflow: hidden; }
.crop { width: 150px; flex: none; padding: 10px; border-right: 1px solid #eee;
        display: flex; flex-direction: column; gap: 6px; }
.crop img { width: 100%; height: 130px; object-fit: contain; background: #fafafa;
            border-radius: 6px; }
.meta { display: flex; justify-content: space-between; font-size: 12px; }
.label { font-weight: 600; }
.conf { color: #6b6b70; }
.src { font-size: 10px; color: #9a9aa0; word-break: break-all; }
.detail { flex: 1; padding: 12px; min-width: 0; }
.ocr { font-size: 12px; margin-bottom: 10px; line-height: 1.4; }
.tag { display: inline-block; font-size: 10px; font-weight: 700; color: #fff;
       background: #5a5a5f; border-radius: 4px; padding: 1px 5px; margin-right: 6px; }
table.matches { width: 100%; border-collapse: collapse; font-size: 13px; }
table.matches td { padding: 4px 6px; border-top: 1px solid #f0f0f2; vertical-align: top; }
td.rank { color: #9a9aa0; width: 20px; }
td.score { text-align: right; font-variant-numeric: tabular-nums; font-weight: 600; width: 44px; }
.canon { display: block; font-size: 10px; color: #9a9aa0; }
.empty { color: #9a9aa0; font-size: 13px; font-style: italic; }
"""


def render_report(items: Sequence[ReportItem], output_path: str | Path, title: str = "Pipeline Results") -> Path:
    """Write all items to a single self-contained HTML file; return its path."""
    cards = "\n".join(_card(item) for item in items)
    doc = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"/>
<title>{html.escape(title)}</title><style>{_STYLE}</style></head>
<body>
  <header>
    <h1>{html.escape(title)}</h1>
    <p>{len(items)} detected items — each crop with its top canonical matches</p>
  </header>
  <div class="grid">{cards}</div>
</body></html>"""
    out = Path(output_path)
    out.write_text(doc, encoding="utf-8")
    return out
