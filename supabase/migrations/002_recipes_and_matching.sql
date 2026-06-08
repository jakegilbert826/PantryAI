-- recipe + recipe_ingredient + match_recipes RPC (design §7.2 / §8) — applied 2026-06-08.
--
-- Phase 7 of the v3 plan. Deterministic, zero-cost recipe matching: recipes and
-- the pantry share the `canonical_name` vocabulary, so coverage is exact set
-- arithmetic — no embeddings, no LLM, no per-query cost.
--
-- Depends on migration 001 (`food_reference` PK = canonical_name, the
-- `substitution_directed` table, and the `measure_unit` enum). Recipes stay
-- remote; only match *results* are cached on device.

-- §7.2 recipe catalogue (no embeddings in v1)
create table recipe (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  image_url       text,
  instructions_md text,
  servings        int,
  cuisine         text,
  total_time_min  int
);

create table recipe_ingredient (
  recipe_id      uuid references recipe(id) on delete cascade,
  canonical_name text references food_reference(canonical_name),
  quantity       double precision,
  measure_unit   measure_unit,              -- canonical only ('g','ml','unit')
  is_optional    boolean default false,
  is_core        boolean default true,
  primary key (recipe_id, canonical_name)
);

create index recipe_ingredient_canonical_idx on recipe_ingredient (canonical_name);

-- §8 match_recipes — rank recipes by core-ingredient coverage.
--
-- Substitution expansion happens HERE (server-side), where the substitution
-- tables live, so the device only ever sends the raw available canonical names:
--   (1) symmetric `substitution_group`: any food sharing a group with an
--       available item counts as available;
--   (2) directed `substitution_directed`: having `from` satisfies a requirement
--       for `to`.
-- Coverage is over *core, non-optional* ingredients. Ranked by coverage desc,
-- tie-break fewest missing core, then name.
create or replace function match_recipes(available text[])
returns table (
  recipe_id      uuid,
  name           text,
  image_url      text,
  servings       int,
  cuisine        text,
  total_time_min int,
  core_total     int,
  core_matched   int,
  coverage       double precision,
  missing_core   text[]
)
language sql
stable
as $$
  with avail_raw as (
    select distinct unnest(available) as canonical_name
  ),
  avail as (
    select canonical_name from avail_raw
    union
    select fr_other.canonical_name
    from avail_raw a
    join food_reference fr_have  on fr_have.canonical_name = a.canonical_name
    join food_reference fr_other on fr_other.substitution_group = fr_have.substitution_group
    where fr_have.substitution_group is not null
    union
    select sd.to_canonical
    from avail_raw a
    join substitution_directed sd on sd.from_canonical = a.canonical_name
  ),
  core as (
    select ri.recipe_id,
           ri.canonical_name,
           (av.canonical_name is not null) as matched
    from recipe_ingredient ri
    left join avail av on av.canonical_name = ri.canonical_name
    where ri.is_core = true and coalesce(ri.is_optional, false) = false
  ),
  agg as (
    select recipe_id,
           count(*)::int                        as core_total,
           count(*) filter (where matched)::int as core_matched,
           array_remove(
             array_agg(case when not matched then canonical_name end),
             null
           )                                     as missing_core
    from core
    group by recipe_id
  )
  select r.id, r.name, r.image_url, r.servings, r.cuisine, r.total_time_min,
         agg.core_total,
         agg.core_matched,
         (agg.core_matched::double precision / nullif(agg.core_total, 0)) as coverage,
         agg.missing_core
  from agg
  join recipe r on r.id = agg.recipe_id
  where agg.core_matched > 0
  order by coverage desc, cardinality(agg.missing_core) asc, r.name asc;
$$;
