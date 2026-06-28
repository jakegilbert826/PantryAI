"""
Cheap batched LLM fallback for low-confidence canonicalization.

When the deterministic alias → lexical → fuzzy cascade resolves a crop with low
confidence, we hand the OCR text to a small/fast LLM (Gemini 3.1 Flash Lite)
together with the full list of canonical names from the food_reference table and
ask it to pick exactly one — or, if the food genuinely isn't in the table, to
propose a new food_reference row. It can also flag an item as non-food (e.g.
vitamins, cleaning products commonly found in a kitchen cupboard) so it isn't
forced into the food vocabulary. All low-confidence boxes go out in ONE call to
keep the cost down (the canonical vocabulary is sent once, not per box).

This module is provider-specific (Google Gemini) and uses the REST API directly
via `requests` so it needs no extra SDK. Set GEMINI_API_KEY in the environment
(or .env). Nothing here writes to the database — proposed new rows are returned
to the caller, which prints them.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from enum import Enum
from typing import Optional

import requests

# The user asked specifically for Gemini 3.1 Flash Lite. Kept as a constant so a
# different cheap model can be swapped in without touching the call site.
GEMINI_MODEL = "gemini-3.1-flash-lite"
# GEMINI_MODEL = "gemini-3.1-pro-preview"
_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
_TIMEOUT_S = 60


class LLMStatus(str, Enum):
    MATCHED = "matched"     # resolved to an existing canonical_name
    NEW = "new"             # a real food, but not in food_reference -> propose a row
    NOT_FOOD = "not_food"   # confidently identified as a non-food item (e.g. vitamins, cleaning products)
    UNKNOWN = "unknown"     # could not resolve with any confidence


@dataclass
class LLMBox:
    """One low-confidence crop to resolve. `hint` carries the coarse detector
    label (e.g. 'produce'/'product') so the model can use packaging context."""
    box_id: str
    ocr_text: str
    hint: Optional[str] = None


@dataclass
class NewFoodReference:
    """A proposed food_reference row for a food the LLM recognized but that is
    absent from the table. Mirrors the columns of FoodReference. Printed by the
    caller; NOT persisted."""
    canonical_name: str
    display_name: str
    plural_name: Optional[str]
    default_packaging_category: str
    default_container_type: Optional[str]

    def as_dict(self) -> dict:
        return {
            "canonical_name": self.canonical_name,
            "display_name": self.display_name,
            "plural_name": self.plural_name,
            "default_packaging_category": self.default_packaging_category,
            "default_container_type": self.default_container_type,
        }


@dataclass
class LLMResolution:
    box_id: str
    status: LLMStatus
    confidence: float
    canonical_name: Optional[str] = None       # set when status == MATCHED
    new_entry: Optional[NewFoodReference] = None  # set when status == NEW


# --------------------------------------------------------------------------- prompt

_SYSTEM = (
    "You are a grocery product canonicalizer. You receive noisy OCR text read off "
    "a single food item's packaging and a fixed vocabulary of canonical food names. "
    "For each item decide ONE of:\n"
    "  - matched: the item clearly corresponds to one canonical_name in the vocabulary. "
    "Return that exact canonical_name.\n"
    "  - new: you can confidently identify the food, but NO canonical_name in the "
    "vocabulary fits. Propose a new food_reference row.\n"
    "  - not_food: you can confidently tell the item is NOT a food or drink at all "
    "(e.g. vitamins, supplements, medicines, cleaning products, pet food, toiletries) "
    "— common in a kitchen cupboard. Do not force it into the food vocabulary.\n"
    "  - unknown: the OCR is too garbled / generic to identify the item at all.\n"
    "Only use canonical_name values that appear verbatim in the provided vocabulary "
    "when status is matched. Try hard to make a guess and leave few unknown, but use "
    "not_food rather than guessing a food when the item is clearly non-food."
)

# Structured output: an array of per-box decisions. Gemini honors responseSchema.
_RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "resolutions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "box_id": {"type": "string"},
                    "status": {"type": "string", "enum": ["matched", "new", "not_food", "unknown"]},
                    "confidence": {"type": "number"},
                    "canonical_name": {"type": "string"},
                    "new_entry": {
                        "type": "object",
                        "properties": {
                            "canonical_name": {"type": "string"},
                            "display_name": {"type": "string"},
                            "plural_name": {"type": "string"},
                            "default_packaging_category": {"type": "string"},
                            "default_container_type": {"type": "string"},
                        },
                        "required": ["canonical_name", "display_name", "default_packaging_category"],
                    },
                },
                "required": ["box_id", "status", "confidence"],
            },
        }
    },
    "required": ["resolutions"],
}


def _build_user_payload(boxes: list[LLMBox], canonical_names: list[str]) -> str:
    items = [
        {"box_id": b.box_id, "ocr_text": b.ocr_text, "container_hint": b.hint or ""}
        for b in boxes
    ]
    return json.dumps(
        {
            "vocabulary_canonical_names": canonical_names,
            "items": items,
            "instructions": (
                "Return a resolution for every box_id. For 'new', "
                "default_packaging_category is one of fresh/canned/bottled/boxed/bagged "
                "and default_container_type is one of can/bottle/jar/carton/box/bag/"
                "punnet or null for fresh produce."
            ),
        },
        ensure_ascii=False,
    )


# --------------------------------------------------------------------------- call

class GeminiResolver:
    def __init__(self, api_key: Optional[str] = None, model: str = GEMINI_MODEL):
        self.api_key = api_key or os.environ.get("GEMINI_API_KEY")
        self.model = model

    @property
    def available(self) -> bool:
        return bool(self.api_key)

    def resolve_batch(
        self,
        boxes: list[LLMBox],
        canonical_names: list[str],
    ) -> dict[str, LLMResolution]:
        """One LLM call for all low-confidence boxes. Returns {box_id: resolution}.

        On any failure (missing key, HTTP error, malformed output) every box is
        returned as UNKNOWN so the pipeline degrades gracefully instead of crashing.
        """
        if not boxes:
            return {}
        if not self.available:
            print("[gemini] GEMINI_API_KEY not set — marking low-confidence boxes unknown.")
            return {b.box_id: LLMResolution(b.box_id, LLMStatus.UNKNOWN, 0.0) for b in boxes}

        body = {
            "system_instruction": {"parts": [{"text": _SYSTEM}]},
            "contents": [{"role": "user", "parts": [{"text": _build_user_payload(boxes, canonical_names)}]}],
            "generationConfig": {
                "temperature": 0.0,
                "responseMimeType": "application/json",
                "responseSchema": _RESPONSE_SCHEMA,
            },
        }
        url = _ENDPOINT.format(model=self.model)
        try:
            resp = requests.post(
                url,
                params={"key": self.api_key},
                json=body,
                timeout=_TIMEOUT_S,
            )
            resp.raise_for_status()
            text = resp.json()["candidates"][0]["content"]["parts"][0]["text"]
            parsed = json.loads(text)
        except (requests.RequestException, KeyError, ValueError, IndexError) as exc:
            print(f"[gemini] call failed ({exc!r}) — marking low-confidence boxes unknown.")
            return {b.box_id: LLMResolution(b.box_id, LLMStatus.UNKNOWN, 0.0) for b in boxes}

        return self._parse(parsed, boxes, set(canonical_names))

    @staticmethod
    def _parse(
        parsed: dict,
        boxes: list[LLMBox],
        vocab: set[str],
    ) -> dict[str, LLMResolution]:
        out: dict[str, LLMResolution] = {
            b.box_id: LLMResolution(b.box_id, LLMStatus.UNKNOWN, 0.0) for b in boxes
        }
        for r in parsed.get("resolutions", []):
            box_id = str(r.get("box_id", ""))
            if box_id not in out:
                continue
            status_raw = str(r.get("status", "unknown")).lower()
            conf = float(r.get("confidence", 0.0) or 0.0)
            try:
                status = LLMStatus(status_raw)
            except ValueError:
                status = LLMStatus.UNKNOWN

            if status is LLMStatus.MATCHED:
                canonical = r.get("canonical_name")
                # Guard against hallucinated names not in the real vocabulary.
                if canonical in vocab:
                    out[box_id] = LLMResolution(box_id, LLMStatus.MATCHED, conf, canonical_name=canonical)
                else:
                    out[box_id] = LLMResolution(box_id, LLMStatus.UNKNOWN, 0.0)
            elif status is LLMStatus.NEW:
                ne = r.get("new_entry") or {}
                if ne.get("canonical_name") and ne.get("display_name"):
                    out[box_id] = LLMResolution(
                        box_id,
                        LLMStatus.NEW,
                        conf,
                        new_entry=NewFoodReference(
                            canonical_name=ne["canonical_name"],
                            display_name=ne["display_name"],
                            plural_name=ne.get("plural_name"),
                            default_packaging_category=ne.get("default_packaging_category", ""),
                            default_container_type=ne.get("default_container_type") or None,
                        ),
                    )
                else:
                    out[box_id] = LLMResolution(box_id, LLMStatus.UNKNOWN, 0.0)
            elif status is LLMStatus.NOT_FOOD:
                out[box_id] = LLMResolution(box_id, LLMStatus.NOT_FOOD, conf)
            else:
                out[box_id] = LLMResolution(box_id, LLMStatus.UNKNOWN, conf)
        return out
