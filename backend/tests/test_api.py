"""End-to-end tests for the Pantry AI FastAPI dev server.

Each test runs against a fresh temp JSON store (see conftest.py), so they're
fully isolated and order-independent.
"""

from __future__ import annotations


def test_health_ok(client):
    resp = client.get("/api/v1/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert "store" in body


def test_inventory_starts_empty(client):
    resp = client.get("/api/v1/inventory")
    assert resp.status_code == 200
    assert resp.json() == []


def test_upsert_inserts_item(client, sample_item):
    resp = client.post("/api/v1/inventory/upsert", json=[sample_item])
    assert resp.status_code == 200
    returned = resp.json()
    assert len(returned) == 1
    assert returned[0]["name"] == "Rice"

    # And it's readable back via the list endpoint.
    listed = client.get("/api/v1/inventory").json()
    assert len(listed) == 1
    assert listed[0]["lastScanConfidence"] == 0.9


def test_upsert_dedupes_by_case_insensitive_name(client, sample_item):
    client.post("/api/v1/inventory/upsert", json=[sample_item])

    updated = dict(sample_item)
    updated["name"] = "RICE"          # same name, different case
    updated["quantity"] = 0.25
    client.post("/api/v1/inventory/upsert", json=[updated])

    listed = client.get("/api/v1/inventory").json()
    assert len(listed) == 1, "case-folded name should not create a duplicate"
    assert listed[0]["quantity"] == 0.25


def test_upsert_accepts_multiple_items(client, sample_item):
    second = dict(sample_item)
    second["id"] = "22222222-2222-2222-2222-222222222222"
    second["name"] = "Pasta"
    resp = client.post("/api/v1/inventory/upsert", json=[sample_item, second])
    assert len(resp.json()) == 2


def test_delete_existing_item(client, sample_item):
    client.post("/api/v1/inventory/upsert", json=[sample_item])
    resp = client.delete(f"/api/v1/inventory/{sample_item['id']}")
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}
    assert client.get("/api/v1/inventory").json() == []


def test_delete_missing_item_returns_404(client):
    resp = client.delete("/api/v1/inventory/33333333-3333-3333-3333-333333333333")
    assert resp.status_code == 404


def test_log_usage_acknowledges(client, sample_item):
    payload = {
        "item_id": sample_item["id"],
        "quantity_used": 0.3,
        "source": "manual",
    }
    resp = client.post(f"/api/v1/inventory/{sample_item['id']}/usage", json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True
    assert body["id"] == sample_item["id"]


def test_recipe_suggestions_stub_returns_empty_list(client):
    resp = client.get("/api/v1/recipes/suggestions")
    assert resp.status_code == 200
    assert resp.json() == []


def test_upsert_persists_to_disk(client, sample_item, store_path):
    client.post("/api/v1/inventory/upsert", json=[sample_item])
    assert store_path.exists()
    assert "Rice" in store_path.read_text()


def test_upsert_rejects_missing_required_field(client):
    # last_scan_confidence has no default — omitting it is a validation error.
    bad = {"name": "Mystery", "category": "dry_goods"}
    resp = client.post("/api/v1/inventory/upsert", json=[bad])
    assert resp.status_code == 422
