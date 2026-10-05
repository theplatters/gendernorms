---
id: ADR-0026
title: Committed observer snapshots in the tick pipeline
status: accepted
date: 2026-10-05
supersedes: ""
superseded_by: ""
---

## Context

The observer metrics package (`MDR-0019`, `MDR-0020`, `MDR-0021`,
`MDR-0022`) makes preference, utility, and transfer observable per tick
through the run pipeline's `model_metrics`, from where they flow to
`logging.metrics`, `runs/*/run.toml`, and the dashboard (`ADR-0012`,
`ADR-0025`). The model semantics are decided by the MDRs; this record
fixes the structural shape: how the committed utilities enter the ECS
state without disturbing the deterministic parallel bargaining region,
where the aggregates live, and how the reductions stay bitwise stable
and allocation-free.

Constraints: `set_theta!` and `calculate_norm_perception!` run
disjoint per-household/per-agent work on bounded worker tasks
(`ADR-0023`, `ADR-0024`) whose output must stay bit-identical across
thread counts and chunk sizes (pinned by `test/test_threading.jl` and
`test/threading_driver.jl`); the solver APIs are frozen by `MDR-0013`
and `ADR-0018`/`ADR-0022`; and tick performance may not degrade by
more than 5% (`MDR-0011` methodology, `benchmark/bargaining_kernel.jl`).

## Decision

1. **ECS commit capture in `set_theta!`.** The two committed-bundle
   utilities are evaluated inside `set_theta!`'s existing
   `process_chunk!` immediately after `bargain_transfer` returns, from
   the already-prepared `pw`/`pm` parameters via `individual_utility`
   (unchanged solver API, single source of truth with the labour
   solver). The woman's value is written through her `Ark.Query` column
   and the man's value is included in the existing `Ark.set_components!`
   commit tuple, alongside the hours and transfer writes they already
   receive. There is no shared accumulation, no new task, lock, or
   atomic, no stored payoff parameter, and no norm recomputation in the
   parallel region; `set_theta!` keeps its public signature. The
   `CommittedUtility` component is registered on every agent at setup
   before the first step, so the parallel loop only updates existing
   columns and never migrates an archetype.
2. **Separate observer resources.** `PreferenceStats(men, women)`,
   `UtilityStats(men, women)`, and `TransferStats(mean)` are separate
   mutable resources beside `WorkingTimeStats` in
   `src/resources/observers.jl` (one observer group per resource, the
   `MDR-0008` rule), added at setup and initialized to `NaN` =
   "not yet observed".
3. **Fused serial reductions.** `update_observer_stats!(world)` in
   `src/systems/statistics.jl` replaces `update_global_working_times!`
   in the tick as slot 5 of `step_model!` (`MDR-0022`): two serial
   gender-filtered `Ark.Query` reductions in the historical women-then-
   men order with sequential scalar accumulators in the existing
   deterministic query batch/index order, writing all four resources at
   the end, and the `MDR-0007` empty-gender `ArgumentError` (naming the
   missing sex, thrown before publishing any aggregate). The fused
   working-time accumulation preserves the standalone reducer's
   addition order exactly (bitwise-identical `working_time_*` means on
   valid full-model worlds). `update_global_working_times!` is kept
   unchanged as a standalone for minimal worlds and existing callers;
   the tick must not call both.
4. **Unchanged solver and pipeline APIs.** `individual_utility`,
   `BestResponseObjective`, `bargain_transfer`, and `payoff_params` are
   untouched; `model_metrics(::Type{GenderNormsModel})` is extended to
   the eight names with closures reading the resources, so explicit
   `[logging].metrics` subsets and the omitted-logging-defaults-to-all
   behavior of `ADR-0012` keep working unchanged.
5. **Dashboard consumption.** The dashboard (`ADR-0025`) consumes the
   new metrics through its metric-agnostic path representation and
   worker IPC; no core change is made for it and the panel/UI work of
   exposing the new names stays in `TASK-0028`. This record extends
   `ADR-0025`'s metric consumption only; the worker isolation and the
   prohibition on reading a stepping world are unchanged.
6. **Performance and determinism requirements.** `update_observer_stats!`
   must allocate 0 bytes (warmed, function-local; multiple archetypes
   incl. tagged/untagged agents) and the concrete `individual_utility`
   evaluation must allocate 0; the two utility calls per household live
   inside the timed `set_theta!` region, so the kernel and end-to-end
   medians of `benchmark/bargaining_kernel.jl` `ws_500` (warmed, 15
   reps) may not degrade by more than 5%. Threading snapshots in
   `test/test_threading.jl` and `test/threading_driver.jl` are extended
   with `CommittedUtility` and the new aggregates so the bitwise
   serial/parallel/auto and `-t 1` vs `-t 4` identities cover them.

## Consequences

- Files touched: `src/components.jl` (`CommittedUtility`),
  `src/resources/observers.jl` (three new resources),
  `src/systems/initialisation.jl` (NaN init on every agent),
  `src/systems/household_bargaining.jl` (commit capture in
  `process_chunk!`), `src/systems/statistics.jl`
  (`update_observer_stats!`), `src/runtime/gender_norms_model.jl`
  (setup resources, slot 5, eight metrics). No new source files, so the
  include list is unchanged.
- Per-agent writes stay disjoint and the reductions are serial and
  ordered, so thread bit-identity is preserved by construction and
  pinned by the extended snapshots.
- The allocation discipline of `MDR-0002`/`ADR-0018` (closure-free,
  isbits, no boxing) now covers the observer capture as well: the two
  utility evaluations construct the prepared objective exactly as the
  solver does and store one `Float64` per partner.
- Benchmark drivers that hand-mirror the tick (`benchmark/bargaining_kernel.jl`)
  must follow the revised slot 5; `benchmark/run_benchmarks.jl` drives
  `step_model!` itself and stays in sync automatically.
