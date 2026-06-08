-- food_reference (design §7.1) — the canonical, v3-from-the-start schema.
--
-- The original v0 table (synthetic `id`, `decay_rate_days`, `default_measure_type`,
-- …) was discarded; there was no production data worth migrating, so the table is
-- created directly in its final form rather than altered. Applied 2026-06-08 via
-- `supabase db push`; the Swift `FoodReference` decoder maps directly to these
-- columns (the old `decay_rate_*` compat remap has been removed).
--
-- Key points:
--   • PK = canonical_name (no synthetic id)
--   • measure_type is derived in-app from the canonical unit (not stored)
--   • default_container_size in canonical units; drives quantity estimates
--   • half_life_days NULL = infinite / shelf-stable; opened_half_life_days finite
--   • default_input_mode merges the old stepper_type + default_preferred_unit
--   • substitution_group = symmetric interchangeable cluster
--   • canonical units only: measure_unit enum is ('g','ml','unit')

create type measure_unit       as enum ('g', 'ml', 'unit');
create type container_type     as enum ('can', 'bottle', 'bag', 'box', 'punnet', 'jar', 'carton');
create type storage_location   as enum ('fridge', 'freezer', 'pantry');
create type packaging_category as enum ('fresh', 'canned', 'dried', 'frozen', 'beverage', 'condiment');
create type input_mode         as enum ('container', 'count', 'weight_volume');

create table food_reference (
  canonical_name             text primary key,
  display_name               text not null,
  plural_name                text,
  default_measure_unit       measure_unit not null,            -- measure_type derived in app
  default_storage_location   storage_location not null,
  default_packaging_category packaging_category not null,
  default_container_type     container_type,
  default_container_size     double precision,                 -- canonical units; drives estimates
  half_life_days             double precision,                 -- sealed; NULL = infinite (shelf-stable)
  opened_half_life_days      double precision,                 -- applies once opened
  default_input_mode         input_mode not null,
  substitution_group         text                              -- shared group ⇒ interchangeable (symmetric)
  -- macro columns (kcal, protein_g, … per 100g) added later
);

-- Asymmetric substitutions: (from, to) means "having `from` satisfies a recipe
-- requirement for `to`". Symmetric N-way clusters use `substitution_group` above.
create table substitution_directed (
  from_canonical text references food_reference(canonical_name),
  to_canonical   text references food_reference(canonical_name),
  primary key (from_canonical, to_canonical)
);
