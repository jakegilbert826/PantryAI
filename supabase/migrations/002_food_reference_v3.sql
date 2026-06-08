-- food_reference v3 migration (design §7.1) — PENDING / NOT YET APPLIED.
--
-- The remote table is still on the v0 columns from 001 (`id`, `decay_rate_days`,
-- `default_measure_type`, …). The Swift `FoodReference` struct already uses the
-- v3 property names but decodes the v0 columns (see FoodReference.swift / design
-- §11.1). Run this migration to move the remote schema to v3, then drop the
-- backward-compat CodingKeys remaps in FoodReference.swift.
--
-- Changes vs v0:
--   • PK = canonical_name (drop synthetic `id`)
--   • drop default_measure_type (derived in-app from the canonical unit)
--   • drop default_container_nominal_unit; add default_container_size (canonical units)
--   • rename decay_rate_days        → half_life_days        (NULL = infinite / shelf-stable)
--   • rename decay_rate_opened_days → opened_half_life_days
--   • merge stepper_type + default_preferred_unit → default_input_mode
--   • add substitution_group
--   • canonical units only: measure_unit enum is ('g','ml','unit')

create type measure_unit_v3      as enum ('g', 'ml', 'unit');
create type container_type_v3    as enum ('can', 'bottle', 'bag', 'box', 'punnet', 'jar', 'carton');
create type storage_location_v3  as enum ('fridge', 'freezer', 'pantry');
create type packaging_category_v3 as enum ('fresh', 'canned', 'dried', 'frozen', 'beverage', 'condiment');
create type input_mode_v3        as enum ('container', 'count', 'weight_volume');

create table food_reference_v3 (
  canonical_name             text primary key,
  display_name               text not null,
  plural_name                text,
  default_measure_unit       measure_unit_v3 not null,         -- measure_type derived in app
  default_storage_location   storage_location_v3 not null,
  default_packaging_category packaging_category_v3 not null,
  default_container_type     container_type_v3,
  default_container_size     double precision,                 -- canonical units; drives estimates
  half_life_days             double precision,                 -- sealed; NULL = infinite (shelf-stable)
  opened_half_life_days      double precision,                 -- applies once opened
  default_input_mode         input_mode_v3 not null,
  substitution_group         text                              -- shared group ⇒ interchangeable (symmetric)
  -- macro columns (kcal, protein_g, … per 100g) added later
);

-- Asymmetric substitutions: (from, to) means "having `from` satisfies a recipe
-- requirement for `to`". Symmetric N-way clusters use `substitution_group` above.
create table substitution_directed (
  from_canonical text references food_reference_v3(canonical_name),
  to_canonical   text references food_reference_v3(canonical_name),
  primary key (from_canonical, to_canonical)
);
