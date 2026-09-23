---
id: MDR-0008
title: Remove the unused GlobalStats carrier
status: accepted
date: 2026-09-21
supersedes: ""
superseded_by: ""
---

## Context

`GlobalStats` in `src/resources/properties.jl` (fields `mean_men` /
`mean_women` / `mean_transfer`, `hist_men` / `hist_women`, `wage_gap` /
`run_time`) was the partial port of the NetLogo observer globals
(`global-mean-working-time-men` / `global-mean-working-time-women`,
`global-mean-transfer`, the `history-*` series, `run-time`, and
`current_wage_gap` in `gender_model_shocks_preferences.nlogox`). It was
never read or written by any code in `src/`: it was only defined, while
`MDR-0007` made `WorkingTimeStats` in `src/resources/observers.jl` the
computed observer for the statistics core. ODD Details > Submodels >
Statistics (`update-statistics`) still lists these observers, and open
`TASK-0001` tracks the full Statistics port.

## Decision

Delete the dead `GlobalStats` struct (already done in
`src/resources/properties.jl`); revert the
`registry/model/entities.md` observer rows to carrier-less truth (the
global means keep their `WorkingTimeStats` mapping; histories, the
stored transfer mean, run time, and the wage gap map to no Julia
symbol); the one `MDR-0007` sentence naming `GlobalStats.hist_men` /
`hist_women` as the reserved history carrier is corrected to point at
this record.

## Consequences

Histories and moving averages, the stored transfer mean, run time, and
the wage-gap observer now have no Julia carrier (`not ported` in
`registry/model/entities.md`); any future history work under open
`TASK-0001` must introduce its own carrier plus a record. The `MDR-0007`
core scope (lag copy plus `WorkingTimeStats` means) is unchanged.
