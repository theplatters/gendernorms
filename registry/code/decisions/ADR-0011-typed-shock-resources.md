---
id: ADR-0011
title: Model shock modes as typed resources with dispatch
status: accepted
date: 2026-09-21
supersedes: ""
superseded_by: ""
---

# ADR-0011: Model shock modes as typed resources with dispatch

## Context

The unwired `src/resources/shock.jl` declared a single `ShockConfig`
keyed by an undefined `ShockType` enum with a `SHOCK_NO` default,
mirroring the NetLogo `shock` chooser string (`wage`, `preference`,
`both`, `no`). That shape cannot express the reference semantics
cleanly: each shock mode owns a different parameter set (per-sex
preference deltas versus affected-share draws), the `perc_*` values are
one-shot `setup` draws rather than persistent configuration, and the
tick scheduler must run zero, one, or both recovery processes depending
on which modes are active. `ADR-0010` keys world resources by their
exact concrete type, and the tick path must stay allocation-free with
`Ark.Query` column loops (see `ADR-0007`).

## Decision

Replace the enum-and-config shape with enum-free dispatch over concrete
resources, as ported under `MDR-0009`:

- `abstract type Shock` in `src/resources/shock.jl` is the dispatch
  root only and is never used as a field or resource type. The concrete
  resources `WageShock`, `PreferenceShock`, and `WageGrowth` each carry
  exactly their own fields (`start`/`depreciation`, plus `delta_men`/
  `delta_woman` for preferences, plus `rate` for wage growth). There is
  no enum, no `ShockConfig`, and no `perc` or `lambda` field.
- The affected sets are the empty tag component `DirectlyAffected` in
  `src/components.jl`, added with `Ark.add_components!` at setup,
  instead of a `BitVector`, an entity list, or a second resource. Tag
  membership is queried with the `with` filter of `Ark.Query`, so the
  targeted wage cut needs no materialised agentset.
- Behaviour lives in the systems layer in `src/systems/shocks.jl`:
  `select_affected!` (setup only, may allocate), the allocation-free
  tick path `start_shock!`/`recover_shock!`/`update_shocks!`, and the
  ported-but-unscheduled `update_wages!`. The constant `WAGE_CUT`
  names the 0.6 reference factor.
- Scheduling is resource presence: `update_shocks!` branches on
  `Ark.has_resource(world, WageShock)` and `Ark.has_resource(world,
  PreferenceShock)` and dispatches on `tick == start` versus
  `tick > start`. Neither resource present is the `"no"` no-op; both
  present runs both, wage first, then preference.

## Consequences

- `ADR-0010` exact-type lookup still holds: each shock mode is its own
  concrete resource type, so `Ark.get_resource` and
  `Ark.has_resource` resolve without a specification argument or a
  type parameter.
- `src/resources/shock.jl` becomes wired and is included in
  `src/GenderNorms.jl` after `src/resources/properties.jl`;
  `src/systems/shocks.jl` is included after
  `src/systems/statistics.jl`, keeping the `components` -> `resources`
  -> `systems` layering of `ADR-0002` with no include cycles.
- The abstract `Shock` type never appears as a struct field, so the
  no-abstract-field-types rule keeps every field concrete while
  dispatch stays open to future shock modes.
- The `Excluded from module:` note for `src/resources/shock.jl` in
  `registry/code/architecture.md` is removed; both files gain file-map
  rows and helper entries.

## References

- `src/components.jl`, `src/resources/shock.jl`,
  `src/systems/shocks.jl`, `src/GenderNorms.jl`
- `registry/model/decisions/MDR-0009-typed-shocks.md`
- `registry/code/decisions/ADR-0002-layered-package-structure.md`
- `registry/code/decisions/ADR-0007-set-theta-query-extraction.md`
- `registry/code/decisions/ADR-0010-world-owned-model-properties.md`
