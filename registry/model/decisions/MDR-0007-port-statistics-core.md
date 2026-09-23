---
id: MDR-0007
title: Port the lightweight core of update-statistics
status: accepted
date: 2026-09-21
supersedes: ""
superseded_by: ""
---

## Context

NetLogo `update-statistics` in `gender_model_shocks_preferences.nlogox`
(lines 786-833) runs every `go` tick after `set-theta` mutates
`current-working-time` and before `update-preferences` reads it. The ODD
section Statistics (`update-statistics`) specifies it: copy `current-*` to
`old-*`, recompute the global means, push them onto 10-element histories,
and report their moving averages `average-mean-working-time-{women,men}`;
`global-mean-transfer` is the contemporaneous mean over women. It also
updates shock-propagation and household-type subgroup means and sets
`run-time = timer` in `go` after `tick`.

The Julia stub in `src/systems/statistics.jl` is broken twice: it writes
`working_time.old .= working_time.current` into the immutable scalar
structs `WorkingTime` and `TransferToWoman` in `src/components.jl`, and it
calls the nonexistent `Ark.get_resource!` (Ark 0.5.1 exposes only
`Ark.get_resource`, `Ark.has_resource`, `Ark.add_resource!`, and
`Ark.set_resource!`). `Ark.Query` yields per-batch column views, so mean
loops must read columns by index (see `ADR-0007` for the sanctioned
in-place column writes). The existing `WorkingTimeStats` resource in
`src/resources/observers.jl` carries exactly `men`, `women`, and `gap`;
there is no transfer field, and the lagged transfer mean stays available
on demand via `norm_global_means` (see `MDR-0004`). `TASK-0001` tracks the
full Statistics port.

## Decision

Port only the lightweight, parallelizable core of `update-statistics`
into `src/systems/statistics.jl`:

- `update_old_working_time_and_transfer!(world)` copies `current` to
  `old` for `WorkingTime` and `TransferToWoman` over all turtles in one
  `Ark.Query` pass with an inner index loop, rebinding the immutable
  structs in place through the column views (see `ADR-0007`).
- `update_global_working_times!(world)` keeps two separate gender
  `Ark.Query` loops (women, then men), each an independent reduction with
  sequential function-local `total`/`count` accumulators; the loops are independent and allocation-free, so they parallelize trivially if ever needed, with column reads only, then
  performs a single resource write of the contemporaneous means into the
  existing `WorkingTimeStats` resource with `gap = men - women`. `gap` is
  a Julia-side helper with no NetLogo global of that name (see
  `registry/model/entities.md`).
- Read the resource with the non-bang `Ark.get_resource(world,
  WorkingTimeStats)` used by every other system (see `ADR-0010`); the
  resource is never created inside the hot loop, so callers and tests must
  `Ark.add_resource!(world, WorkingTimeStats(...))` at setup first.
- NetLogo assumes non-empty breeds and calls unguarded `mean`. The Julia
  port instead throws `ArgumentError` naming the empty gender, mirroring
  the `generate_social_network` style in
  `src/systems/initialisation.jl`, so an empty breed can never pass as a
  silent `NaN`.

Explicitly defer the rest, with reasons, keeping `TASK-0001` open: the
10-element histories and moving averages (sequential vector mutation,
allocation, not parallel-friendly; the former `GlobalStats.hist_men` /
`hist_women` carrier in `src/resources/properties.jl` was removed, see
`MDR-0008`, so future history work must introduce a new carrier),
`global-mean-transfer` (no field in `WorkingTimeStats`), all 12
shock-propagation and household-type subgroup means (observer agentsets
unported; they would need network plus employment-state membership
tracking), and the `run-time` timer.

## Consequences

`WorkingTimeStats` becomes computed instead of declared-only: the lag
copy preserves the `set-theta` -> `update-statistics` ->
`update-preferences` ordering contract, and the means give an
allocation-free, embarrassingly parallel observer core (no `Dict`s, no
materialized entity lists, no network access, no per-agent
`get_components`/`set_components!` in the mean loops). Histories,
subgroup means, transfer storage, and `run-time` remain open under
`TASK-0001`. Tests must add the `WorkingTimeStats` resource before
calling `update_global_working_times!`, matching the `ADR-0010` setup
pattern. Nothing yet calls these functions, and the `set-theta` ->
`update-statistics` -> `update-preferences` tick ordering is a documented
contract until a scheduler/`go` loop is ported (tracked by open
`TASK-0001`/`TASK-0010`).
