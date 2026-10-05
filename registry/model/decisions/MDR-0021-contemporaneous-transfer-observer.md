---
id: MDR-0021
title: Contemporaneous transfer mean over women with a TransferStats observer
status: accepted
date: 2026-10-05
supersedes: ""
superseded_by: ""
---

## Context

NetLogo `update-statistics` stores `global-mean-transfer`, the
contemporaneous mean of `current-transfer-to-woman` over the women
(ODD section Statistics (`update-statistics`): "`global-mean-transfer`
is the contemporaneous mean over women"). `MDR-0007` ported only the
lightweight statistics core and explicitly deferred `global-mean-transfer`
because `WorkingTimeStats` has no transfer field; `MDR-0008` then
recorded the stored transfer mean as carrier-less and `not ported`, and
`TASK-0001` kept its storage clause open. The lagged transfer mean used
by norm perception (`norm_global_means` of `MDR-0004`) is a different
quantity (mean of `TransferToWoman.old`) and stays on demand only.

## Decision

Add the mutable resource `TransferStats(mean)` in
`src/resources/observers.jl`, the mean of `TransferToWoman.current`
over the WOMEN only (spouses mirror their wives'
`TransferToWoman.current`, so the women's mean is the household-mean
transfer to the woman; the men's mirrored column is deliberately not
averaged), and expose it as the `transfer_mean` run-pipeline metric
(range `[-1, 1]`).

- One observer group per resource (the `MDR-0008` rule); this record
  governs `TransferStats` alone.
- Observation timing: the contemporaneous (current) value at the tick's
  single observer snapshot (`MDR-0022`), matching NetLogo's
  contemporaneous semantics; this is distinct from the lagged
  `norm_global_means` transfer mean.
- The resource initializes to `NaN` = "not yet observed" at setup, like
  every new observer of this package (`MDR-0019`, `MDR-0020`).
- This discharges the `global-mean-transfer` storage clause of
  `TASK-0001` (the storage deferral of `MDR-0007`); the histories,
  moving averages, and subgroup sets of that task stay open.

## Consequences

The fused observer snapshot `update_observer_stats!` accumulates the
women's transfer sum in its women's reduction (`MDR-0022`); the
standalone `norm_global_means` is untouched and keeps its lagged
semantics. `registry/model/entities.md` gains the stored
contemporaneous transfer mapping and distinguishes it from the lagged
norm mean; `TASK-0001`'s storage clause is annotated as discharged on
completion of `TASK-0029`.
