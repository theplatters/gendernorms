---
id: ADR-0014
title: Multithreaded tick loops with greedy scheduling
status: accepted
date: 2026-09-26
supersedes: ""
superseded_by: ""
---

# ADR-0014: Multithreaded tick loops with greedy scheduling

## Context

The two per-tick world loops `calculate_norm_perception!`
(`src/systems/norm_perception.jl`, port of NetLogo `calculate-utility`,
ODD section Norm perception) and `set_theta!`
(`src/systems/household_bargaining.jl`, port of NetLogo `set-theta` and
`calculate-payoff`, ODD section Transfer bargaining) iterate disjoint
work items per tick and dominate tick cost. Each agent iteration touches
only its own components and reads only lagged `old` state of others;
each household iteration reads only `old` state and its own household's
`current` state and writes only its own agents' components. Iteration
order is therefore irrelevant and results are bit-identical for any
thread count; no RNG is involved in either loop.

Thread safety was verified against the installed Ark 0.5.1 source: Ark
`get_components` and `set_components!` reduce to plain disjoint array
indexing with no lazy mutation, so concurrent disjoint writes are safe.
The caller-owned `spouse_seen` scratch buffer of `norm_means`
(zero-allocation pin per `MDR-0004`) cannot stay shared across threads
and becomes a per-iteration scratch vector.

`Threads.@threads :dynamic` was rejected: in Julia 1.12 its
implementation statically partitions iterations into one contiguous
block per thread and its documentation assumes uniform workload, while
per-household bargaining cost varies (variable Brent and best-response
iteration counts), so work would not be distributed evenly. `:greedy`
(the work-pulling scheduler) assigns each next item to whichever worker
frees first.

## Decision

1. The inner per-agent loop of `calculate_norm_perception!` and the
   inner per-household loop of `set_theta!` run multithreaded with
   `Threads.@threads :greedy`.
2. Each `norm_means` iteration allocates its own `spouse_seen` scratch
   vector, so the buffer is never shared across threads.
3. Everything else is unchanged: component extraction stays Query-based
   per `ADR-0007`, and tick order stays as decided in `MDR-0010`.

## Consequences

- Results are bit-identical for any thread count; cross-thread-count
  determinism is covered by `test/test_threading.jl`.
- Exceptions raised inside the parallel loops surface wrapped in
  `TaskFailedException` / `CompositeException` rather than directly.
- One scratch-vector allocation per agent and household iteration (the
  `MDR-0004` zero-allocation pin no longer applies inside the threaded
  loops).
- `benchmark/threading_speedup.jl` measures the threading speedup; the
  `MDR-0011` NetLogo comparison benchmark keeps running Julia with
  `JULIA_NUM_THREADS=1` (see `ADR-0013`).
- No model-behavior change and no ODD change, so no MDR is needed.

## References

- `registry/model/decisions/MDR-0004-norm-perception-port.md`
- `registry/model/decisions/MDR-0010-go-tick-loop-scheduling.md`
- `registry/model/decisions/MDR-0011-benchmark-methodology.md`
- `registry/code/decisions/ADR-0007-set-theta-query-extraction.md`
- `registry/code/decisions/ADR-0013-benchmark-harness.md`
- `registry/tasks.md`
