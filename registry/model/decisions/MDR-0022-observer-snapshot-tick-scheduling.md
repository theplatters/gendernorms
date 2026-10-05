---
id: MDR-0022
title: Tick scheduling with the fused observer snapshot
status: accepted
date: 2026-10-05
supersedes: MDR-0010
superseded_by: ""
---

## Context

`MDR-0010` scheduled the `go` tick loop as `step_model!` with the
statistics slot running the `update-statistics` core of `MDR-0007`:
`update_old_working_time_and_transfer!` plus the working-time-only
`update_global_working_times!`, then `update_preferences`. That record
argued the statistics/adaptation order was behaviorally inert because
the two steps touch disjoint state. The observer metrics package
(`MDR-0019`, `MDR-0020`, `MDR-0021`) adds per-tick preference,
utility, and transfer aggregates to the statistics slot and makes the
slot's position observationally significant: the preference means must
be observed BEFORE `update_preferences` adapts the agents, and the
committed utilities are captured during bargaining and must not be
re-evaluated later in the tick (the lag copy has already rewritten the
`old-*` norm source state by then).

## Decision

`step_model!(::Type{GenderNormsModel}, world, config, tick)` keeps the
six outer operations of `MDR-0010`, with slot 5 replaced by the fused
observer snapshot:

1. `update_shocks!(world, tick)` (shock block, `MDR-0009`).
2. `calculate_norm_perception!(world, config.utility)`.
3. `set_theta!(world, config.utility)`; this slot now also captures the
   committed-bundle utilities into `CommittedUtility` (`MDR-0019`)
   inside the existing per-household commit step.
4. `update_old_working_time_and_transfer!(world)` (lag copy).
5. `update_observer_stats!(world)` (was `update_global_working_times!`):
   one fused serial snapshot writing `WorkingTimeStats`,
   `PreferenceStats`, `UtilityStats`, and `TransferStats` at the tick's
   single observation point.
6. `update_preferences(world)`.

Inherited scheduling guarantees of `MDR-0010` are restated unchanged:
tick counting matches the NetLogo `ticks` reporter at `go` entry (the
first call processes tick 0); `calculate_norm_perception!` runs once
per tick before bargaining and reads only lagged `old-*` values
finalized by the previous tick; quirk 11 stays deferred under
`TASK-0010`; `update_wages!` stays unscheduled (`MDR-0009`); and the
NetLogo source order (statistics before preferences) is kept over the
ODD table order.

The fused snapshot runs two serial gender-filtered `Ark.Query`
reductions in the historical order (women first, then men) with
sequential scalar accumulators in the existing deterministic query
batch/index order, so the working-time accumulation is bitwise
identical to the standalone `update_global_working_times!` on valid
full-model worlds. Empty genders throw `ArgumentError` naming the
missing sex before any aggregate is published (the `MDR-0007`
convention). `update_global_working_times!` stays unchanged as a
standalone reducer for minimal worlds and existing callers, but the
tick must not call both.

## Consequences

- The statistics/adaptation ordering is no longer inert: it is an
  observational contract (the `preference_men`/`preference_women`
  series are pre-adaptation; `MDR-0020`). Moving the snapshot after
  `update_preferences`, or evaluating utility after the lag copy, would
  silently change the logged metrics; tests pin the ordering.
- All eight metrics (`working_time_*`, `preference_*`, `utility_*`,
  `transfer_mean`) are observed at one point per tick after
  bargaining/shocks and before preference adaptation, so they describe
  the state the tick's decisions were made under.
- `registry/model/processes.md` restate the tick list and cite this
  record; the benchmark drivers that mirror `step_model!` by hand
  (`benchmark/bargaining_kernel.jl`) must follow the revised slot 5.
- This record supersedes `MDR-0010`; `MDR-0010` becomes `superseded`
  and links here. Its scheduling substance is inherited, not reversed.
