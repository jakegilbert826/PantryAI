"""
Open Food Facts barcode lookup.

Given a decoded barcode value, fetch the matching product from the free Open
Food Facts database and parse out a human-readable food name to feed downstream
into the canonicalization cascade (and, if that is low-confidence, the LLM
fallback). Open Food Facts is a public, no-key REST API, which fits the
zero-cost constraint — no per-call billing.

Nothing here writes anywhere. On any miss / network error it returns None so the
caller can fall back to OCR.

Usage:
    from openfoodfacts import OpenFoodFactsClient
    off = OpenFoodFactsClient()
    product = off.lookup("3017620422003")     # Optional[OFFProduct]
    name = product.best_name if product else None
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import requests

# v2 product endpoint; request only the fields we use to keep the payload small.
_ENDPOINT = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
_FIELDS = "code,product_name,product_name_en,generic_name,brands,quantity,categories"
# OFF requires a descriptive User-Agent in the form "AppName/Version (contact)";
# requests without a contact are 403'd by their nginx/Cloudflare layer.
_USER_AGENT = "PantryAI-Experiments/1.0 (jakegilbert826@gmail.com)"
_TIMEOUT_S = 15


@dataclass
class OFFProduct:
    """The slice of an Open Food Facts product we use for canonicalization."""
    barcode: str
    product_name: Optional[str]
    generic_name: Optional[str]
    brands: Optional[str]
    quantity: Optional[str]
    categories: Optional[str]

    @property
    def best_name(self) -> Optional[str]:
        """The most specific food name available, for the canonicalizer.

        Prefer the product name; fall back to the generic name (often the bare
        food, e.g. "Chickpeas"); finally the leaf category. Brand is intentionally
        left out of the canonicalization text — the cascade matches on the food,
        not the brand — but is kept on the struct as a `brand_hint`.
        """
        for candidate in (self.product_name, self.generic_name):
            if candidate and candidate.strip():
                return candidate.strip()
        if self.categories:
            leaf = self.categories.split(",")[-1].strip()
            if leaf:
                return leaf
        return None

    @property
    def brand_hint(self) -> Optional[str]:
        if self.brands and self.brands.strip():
            return self.brands.split(",")[0].strip()
        return None


class OpenFoodFactsClient:
    def __init__(self, session: Optional[requests.Session] = None):
        self._session = session or requests.Session()
        # Assign, don't setdefault: Session seeds a default "python-requests" UA,
        # which OFF 403s — we must overwrite it with our descriptive UA.
        self._session.headers["User-Agent"] = _USER_AGENT

    def lookup(self, barcode: str) -> Optional[OFFProduct]:
        """Fetch one product by barcode. Returns None on miss/error.

        OFF responds with `status: 1` and a `product` object on a hit, or
        `status: 0` when the barcode is unknown.
        """
        barcode = (barcode or "").strip()
        if not barcode:
            return None
        url = _ENDPOINT.format(barcode=barcode)
        try:
            resp = self._session.get(url, params={"fields": _FIELDS}, timeout=_TIMEOUT_S)
            resp.raise_for_status()
            data = resp.json()
        except (requests.RequestException, ValueError) as exc:
            print(f"[off] lookup failed for {barcode} ({exc!r})")
            return None

        if data.get("status") != 1 or not isinstance(data.get("product"), dict):
            return None

        p = data["product"]
        return OFFProduct(
            barcode=barcode,
            product_name=p.get("product_name") or p.get("product_name_en"),
            generic_name=p.get("generic_name"),
            brands=p.get("brands"),
            quantity=p.get("quantity"),
            categories=p.get("categories"),
        )
