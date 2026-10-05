---
id: MDR-0010
title: Schedule the go tick loop
status: superseded
date: 2026-09-23
supersedes: ""
superseded_by: MDR-0022
---

## Context

`to go` in `gender_model_shocks_preferences.nlogox` (line 370 ff.) runs,
in order: the shock block (`if (ticks = shock-start) [start-shock]`,
`if (ticks > shock-start) [end-shock]`), `set-theta`,
`update-statistics`, `update-preferences`, `tick`, then sets the
`run-time` timer. The ODD section Process overview and scheduling
table instead orders `update-preferences` before
`update-statistics`; the port follows the NetLogo source order (per
`MDR-0001` the NetLogo source is the tiebreaker where the ODD is
ambiguous, and here the two steps touch disjoint state, so either
order satisfies the ODD). `update-statistics` copies
`WorkingTime`/`TransferToWoman` into lagged `old-*` values and
global means, while `update-preferences` adapts
`PreferencePrivate`, so the order is behaviorally inert. Norm
perception uses the lagged `old-*` values, so intra-tick ordering
does not enter norms.

In NetLogo, norm perception happens inside `calculate-utility`, which
`set-theta`/`choose-bundle` call many times per tick; ODD quirk 11
records that the stored `perception-norm-division-of-labor` /
`norm-parameter` values therefore reflect the last counterfactual
evaluation rather than the committed bundle. `MDR-0004` ported norm
perception as the standalone `calculate_norm_perception!`; restoring
quirk 11 is deferred under `TASK-0010`.

All subsystems are ported (`MDR-0004`, `MDR-0005`, `MDR-0007`,
`MDR-0009`) but unscheduled (`TASK-0010`). The run pipeline (`ADR-0012`)
needs a per-tick step.

## Decision

- `step_model!(::Type{GenderNormsModel}, world, config, tick)` is the
  port of one `go` call and runs, in this order:
  `update_shocks!(world, tick)` (shock block, `MDR-0009`),
  `calculate_norm_perception!(world, config.utility)`,
  `set_theta!(world, config.utility)`,
  `update_old_working_time_and_transfer!(world)` and
  `update_global_working_times!(world)` (the `update-statistics` core,
  `MDR-0007`), `update_preferences(world)`.
- `calculate_norm_perception!` runs once per tick before bargaining. It
  reads only lagged `old-*` values and the network, which the previous
  tick's `update-statistics` finalized, so it sees exactly the inputs
  NetLogo's on-demand `calculate-utility` saw at `set-theta` time. Quirk
  11 (overwriting by counterfactual evaluations) stays deferred under
  `TASK-0010`.
- `update_wages!` stays unscheduled: NetLogo `go` never calls
  `update-wages` (`MDR-0009`).
- Tick counting follows the NetLogo `ticks` reporter at `go` entry: the
  first `go` call processes tick 0, `runtime.ticks = N` executes ticks
  `0..N-1`, and `update_shocks!(world, tick)` therefore matches
  `tick == shock-start` exactly as in NetLogo.

## Consequences

- The Julia model is now runnable end to end;
  `registry/model/processes.md` gains the `go` row (implementation work
  package).
- `TASK-0010` narrows to restoring ODD quirk 11 and implementing
  `src/main.jl`.
- The statistics timer (`run-time`) and `print-agent-positions` output
  remain unported (`TASK-0001`); the pipeline records wall-clock
  start/end times instead.
