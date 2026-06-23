-- canonical_alias (ADR-002a §"Alias flywheel") — the single most important
-- compounding asset of the canonicalization spine.
--
-- A normalized surface form → canonical_name mapping. Two roles:
--   • seed: synonyms / merchant abbreviations / brand names pre-loaded so the
--     alias layer (cascade L2) has a real lead layer from the first scan.
--   • learned: every HITL confirmation upserts a row here (write-on-confirm), so
--     a receipt correction makes the CV path smarter and vice-versa.
--
-- The device fetches this table alongside food_reference at boot and folds it
-- into the in-memory CanonicalIndex; corrections are POSTed back here.
--
-- raw_normalized is produced by the on-device TextNormalizer.base(_:) (lowercase,
-- diacritic-folded, pack-size-stripped, single-spaced) so the key matches the
-- hot-path lookup byte-for-byte. source/count/confidence drive learning and the
-- HITL auto-accept threshold.

create type alias_source as enum (
  'pantryScan', 'barcode', 'receiptOCR', 'emailReceipt', 'chat', 'manual'
);

create table canonical_alias (
  raw_normalized text not null,
  canonical_name text not null references food_reference(canonical_name) on delete cascade,
  source         alias_source,
  count          integer not null default 1,           -- times this mapping was confirmed
  confidence     double precision not null default 0.95,
  updated_at     timestamptz not null default now(),
  primary key (raw_normalized, canonical_name)
);

-- One surface form usually resolves to one PK; this index serves the device's
-- "all aliases" sync pull and ad-hoc lookups by canonical.
create index canonical_alias_by_canonical on canonical_alias (canonical_name);

-- Write-on-confirm upsert: bump count, keep the strongest confidence, refresh ts.
-- The device calls this via PostgREST (rest/v1/rpc/upsert_canonical_alias).
create or replace function upsert_canonical_alias(
  p_raw text,
  p_canonical text,
  p_source alias_source,
  p_confidence double precision
) returns void as $$
  insert into canonical_alias (raw_normalized, canonical_name, source, count, confidence, updated_at)
  values (p_raw, p_canonical, p_source, 1, p_confidence, now())
  on conflict (raw_normalized, canonical_name) do update
    set count      = canonical_alias.count + 1,
        confidence = greatest(canonical_alias.confidence, excluded.confidence),
        source     = coalesce(excluded.source, canonical_alias.source),
        updated_at = now();
$$ language sql;
