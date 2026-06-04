create type measure_type as enum ('weight', 'volume', 'count', 'bunch');
create type measure_unit as enum ('g', 'kg', 'ml', 'l', 'unit', 'bunch');
create type container_type as enum ('can', 'bottle', 'bag', 'box', 'punnet', 'jar');
create type nominal_unit as enum ('g', 'ml');
create type storage_location as enum ('fridge', 'freezer', 'pantry');
create type packaging_category as enum ('fresh', 'canned', 'dried', 'frozen', 'beverage', 'condiment');
create type stepper_type as enum ('container', 'count', 'weight_volume');
create type preferred_unit as enum ('container', 'measure');

create table food_reference (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null unique,
  display_name text not null,
  plural_name text,
  default_measure_type measure_type not null,
  default_measure_unit measure_unit not null,
  default_container_type container_type,
  default_container_nominal_size double precision,
  default_container_nominal_unit nominal_unit,
  default_storage_location storage_location not null,
  default_packaging_category packaging_category not null,
  decay_rate_days double precision not null,
  decay_rate_opened_days double precision,
  stepper_type stepper_type not null,
  default_preferred_unit preferred_unit not null
);
