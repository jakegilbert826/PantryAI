"""Shared fixtures: each test gets an isolated, temporary JSON store."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import main


@pytest.fixture()
def store_path(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Point the app's persistence at a throwaway file for the duration of a test."""
    path = tmp_path / "pantry_store.json"
    monkeypatch.setattr(main, "STORE", path)
    return path


@pytest.fixture()
def client(store_path: Path) -> TestClient:
    return TestClient(main.app)


@pytest.fixture()
def sample_item() -> dict:
    return {
        "id": "11111111-1111-1111-1111-111111111111",
        "name": "Rice",
        "category": "dry_goods",
        "quantity": 1.0,
        "lastScanConfidence": 0.9,
        "lastScanDate": "2026-01-01T00:00:00Z",
    }
