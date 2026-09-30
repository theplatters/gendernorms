---
id: ADR-0016
title: Transfer search evaluation cache and staged driver
status: accepted
date: 2026-09-29
supersedes: ""
superseded_by: ""
---

## Context

`MDR-0012` replaces the unseeded Brent transfer search of `MDR-0005`
with a staged feasibility-discovery search: an explicit evaluation set
first, bounded refinement of promising regions second. Every candidate
evaluation is a full labour solve, so the same transfer must never be
solved twice; the refinement must read the sampled values instead of
re-deriving them; the committed hours must be the solved hours of the
committed transfer, never a re-solve through the `-Inf` certificate of
`ADR-0015`; and the evaluation closure must stay box-free under the
`MDR-0002` discipline.

## Decision

Two internal structures in `src/systems/household_bargaining.jl` carry
the staged search (model semantics are recorded in `MDR-0012`, this
record is about their shape only):

- `TransferObjectiveValue`, an immutable evaluation record with both
  utility gains, the Nash payoff, and the solved hours of one transfer.
  A transfer pruned by `_objective_prunable` is recorded as a `-Inf`
  payoff with `NaN` gains and hours and can never be committed.
- `_transfer_search!(cache, evaluate!, theta0, tol)`, the staged-search
  driver over one per-`bargain_transfer`-call
  `Dict{Float64,TransferObjectiveValue}` keyed by the exact transfer,
  with the helpers `_transfer_eval!` (cached evaluation) and
  `_transfer_better` (candidate tie rule). The driver is parameterized
  by the evaluation function `evaluate!`, so the search contract is
  testable through the cache with manufactured evaluations
  (`test/test_transfer_search.jl`) without the solver chain.

`bargain_transfer` owns the cache, seeds it at `theta0` with the
status-quo evaluation, and supplies the evaluation closure
`evaluate_transfer`, whose captures are single-assignment bindings (no
boxing, `MDR-0002`). The cache is per call and per household: no shared
mutable state crosses household boundaries, so the multithreaded
`set_theta!` loop stays scheduling-independent (`ADR-0014`,
`ADR-0015`).

## Consequences

The search allocates per call: the evaluation cache (about 2700
entries) and the sorted sampled-transfer vector replace the
allocation-free objective loop of `MDR-0005`. This is the recorded
cost of guaranteed feasibility discovery (`MDR-0012`);
`TASK-0014` tracks search-cost reduction. The helpers are internal
(non-exported) and registered in `registry/code/architecture.md`; they
are not part of the package surface.

Measured cost (factual amendment under `ADR-0008`; see
`benchmark/transfer_search_validation.md`): the cache holds 2376
evaluations per household-tick at `theta0 = 0` (2371 Stage A samples
plus 5 refinement evaluations; up to 2772 Stage A samples when
`theta0` lies off both grids), about 40.9 `set_theta!` allocations per
household-tick, and the `set_theta!` kernel regressed from 0.0627 s to
18.208 s at 1 thread and from 0.0136 s to 3.656 s at 8 threads on
`benchmark/bargaining_kernel.jl ws_500 20 5` (medians over 5
repetitions, pre-change numbers pre-`MDR-0012`).

Storage amendment (factual, `ADR-0017`): the per-call `Dict` cache and
the per-call `sort!(collect(keys(cache)))` of this record were replaced
by the task-owned reusable `TransferSearchScratch` of `ADR-0017`
(capacity-hinted `Dict` plus reusable sampled-transfer and
weak-maximum vectors, one scratch per `Threads.@threads :greedy` chunk
body, reset per household). The cache semantics of this record are
unchanged - exact-transfer `isequal` keys with `-0.0` distinct from
`+0.0`, one evaluation per transfer, every Stage A transfer present
including the certificate-pruned `-Inf` sentinels - and stay covered by
the cache-probing tests, which keep a caller-owned-cache entry point of
the driver.

## References

- `MDR-0012`, `MDR-0002`, `ADR-0014`, `ADR-0015`
- `src/systems/household_bargaining.jl`
- `test/test_transfer_search.jl`
- `benchmark/transfer_search_validation.md`
