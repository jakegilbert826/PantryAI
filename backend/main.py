"""
Pantry AI — local development FastAPI server.

Implements the contract documented in the Swift handoff. Persistence is a
simple JSON file at `./pantry_store.json`. Not for production; the goal is to
unblock device-side iteration without spinning up real infrastructure.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional
from uuid import UUID, uuid4

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

STORE = Path(os.environ.get("PANTRY_STORE", "pantry_store.json"))
app = FastAPI(title="Pantry AI", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class InventoryItem(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    name: str
    category: str
    brand: Optional[str] = None
    quantity: float = 1.0
    unit: Optional[str] = None
    last_scan_confidence: float = Field(alias="lastScanConfidence")
    last_scan_date: datetime = Field(alias="lastScanDate", default_factory=lambda: datetime.now(timezone.utc))
    decay_model_override: Optional[str] = Field(alias="decayModelOverride", default=None)
    image_url: Optional[str] = Field(alias="imageURL", default=None)

    class Config:
        populate_by_name = True


class UsageEvent(BaseModel):
    item_id: UUID
    quantity_used: float
    source: str = "manual"


def _load() -> List[dict]:
    if not STORE.exists():
        return []
    try:
        return json.loads(STORE.read_text())
    except json.JSONDecodeError:
        return []


def _save(items: List[dict]) -> None:
    STORE.write_text(json.dumps(items, default=str, indent=2))


@app.get("/api/v1/health")
def health():
    return {"status": "ok", "store": str(STORE.resolve())}


@app.get("/api/v1/inventory", response_model=List[InventoryItem])
def list_inventory():
    return _load()


@app.post("/api/v1/inventory/upsert", response_model=List[InventoryItem])
def upsert(items: List[InventoryItem]):
    existing = {item["name"].lower(): item for item in _load()}
    for incoming in items:
        existing[incoming.name.lower()] = json.loads(incoming.model_dump_json(by_alias=True))
    _save(list(existing.values()))
    return list(existing.values())


@app.delete("/api/v1/inventory/{item_id}")
def delete_item(item_id: UUID):
    items = _load()
    filtered = [i for i in items if i.get("id") != str(item_id)]
    if len(filtered) == len(items):
        raise HTTPException(404, "not found")
    _save(filtered)
    return {"ok": True}


@app.post("/api/v1/inventory/{item_id}/usage")
def log_usage(item_id: UUID, event: UsageEvent):
    # Usage events are persisted on-device — the backend just acknowledges so
    # the iOS app can fire-and-forget. Hook a real DB in when needed.
    return {"ok": True, "id": str(item_id)}


@app.get("/api/v1/recipes/suggestions")
def recipe_suggestions():
    # Real implementation would proxy to Gemini. The Swift app already calls
    # Gemini directly, so this endpoint is a stub for the eventual switch.
    return []


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
