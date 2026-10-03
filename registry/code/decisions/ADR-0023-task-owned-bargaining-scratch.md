---
id: ADR-0023
title: Task-owned bargaining scratch and bounded worker scheduling
status: accepted
date: 2026-10-02
supersedes: ADR-0014
superseded_by: ""
---

# ADR-0023: Task-owned bargaining scratch and bounded worker scheduling

## Context

The household bargaining kernel `set_theta!`
(`src/systems/household_bargaining.jl`, port of NetLogo `set-theta` and
`calculate-payoff`, ODD section Transfer bargaining) runs
`Threads.@threads :greedy for chunk in
Iterators.partition(eachindex(entities), HOUSEHOLD_BARGAIN_CHUNK)` with
`HOUSEHOLD_BARGAIN_CHUNK = 4` (`ADR-0014`). Each chunk body constructs
its own `spouse_seen::Vector{Ark.Entity}` (sizehinted to the maximum
vertex degree of the two graphs, `ADR-0015` item C1) and its own
`TransferSearchScratch` (`ADR-0017` item 4), reusing them only across
the households of that one chunk; `TransferSearchScratch` is reset per
household by `_reset_scratch!` (`empty!` plus non-shrinking `sizehint!`).
For 500 households per tick this constructs about 125 scratch object
pairs per tick. A warmed one-thread sampling profile attributed about
13% of kernel time to scratch construction and reset and about 8% to
scheduling operations.

Governing prior decisions:

- `ADR-0014` (superseded by this record) chose `Threads.@threads
  :greedy` over chunked `Iterators.partition` item pulling and
  rejected `:dynamic` (static per-thread blocks, uneven per-household
  cost); worker exceptions surface as `TaskFailedException` /
  `CompositeException`.
- `ADR-0015` item C1: one `spouse_seen` per chunk body, sizehinted to
  the maximum graph degree, never indexed by `Threads.threadid()`,
  never shared across tasks. Its item 4 defers cached entity-to-vertex
  maps, which stay out of scope here.
- `ADR-0017` item 4: one `TransferSearchScratch` per
  `Threads.@threads :greedy` chunk body of `set_theta!`, reset per
  household via `_reset_scratch!` (`empty!` plus non-shrinking
  `sizehint!`), never retaining household parameters or closures; the
  standalone `bargain_transfer` keeps one scratch per call.
- `ADR-0021`: the probe-schedule driver, scratch capacity hints 32/32,
  and the consequence that probe sequences are deterministic and
  thread-count independent.

Invariants that motivate the design: bit-identical, thread-count
independent results (the `ADR-0021` consequence); no
`Threads.threadid()`-indexed mutable buffers (`ADR-0015`); scratch never
shares mutable state across concurrent workers and never retains
household parameters or closures (`ADR-0017` item 4); and per-household
computation is independent, so chunking and scheduling cannot change
results.

## Decision

1. **Task-owned buffer ownership.** `spouse_seen` and
   `TransferSearchScratch` are allocated once per active worker task and
   reused across every chunk that task processes. Buffers remain
   task-owned even if a task migrates between threads: they are never
   indexed by `Threads.threadid()`, never shared between concurrent
   workers, and there are no persistent cross-tick pools or world
   resources. Household reset semantics (`_reset_scratch!` per
   household) and the reusable buffer capacity (the existing sizehints)
   are retained.
2. **Bounded worker scheduling: atomic chunk cursor.**
   `Threads.@threads :greedy` is replaced by a bounded worker-task
   loop (worker count `min(nthreads, chunk count)`) over
   `Iterators.partition` chunks pulled dynamically from a shared
   atomic chunk cursor (a `Threads.Atomic{Int}` chunk index claimed
   inside the `@sync` region). Dynamic scheduling and bounded
   worker-task creation are retained; there is no task per household
   or per chunk. The shared-work-queue variant (a `Channel{Int}` of
   chunk indices drained by the same bounded worker tasks) was
   benchmarked against the cursor and rejected; its measured numbers
   and the verdict are in Consequences and
   `benchmark/scheduling_tuning.md`. The completion barrier before
   subsequent tick systems run is preserved (`@sync` join semantics
   equivalent to `@threads`), household writes stay disjoint, and
   worker failures propagate as `TaskFailedException` /
   `CompositeException`.
3. **Serial path.** A direct serial path (one `spouse_seen` and one
   `TransferSearchScratch`, no tasks) runs when Julia runs with one
   thread, and on multithreaded runs when the population is at most
   `HOUSEHOLD_BARGAIN_SERIAL_CUTOFF = 8` households. The cutoff is
   selected from the crossover measurements of Consequences: serial
   wins at 4 households and below, the paths tie through 8, and
   parallel is ahead from 10 (up to 4.5x at 96+).
4. **Chunk size from measurements.** `HOUSEHOLD_BARGAIN_CHUNK` is
   re-confirmed as 4 from measurements over {4, 8, 16, 32} on the
   representative (`ws_500`) and heterogeneous workloads: chunk 8 is
   within noise on `ws_500` but worse on `heterogeneous` and `ws_100`
   and showed the worse tail, and load balance is not sacrificed
   merely to minimize allocation.
5. **Keyword arguments.** `set_theta!` gains backward-compatible
   keyword arguments `chunk::Int=HOUSEHOLD_BARGAIN_CHUNK` and
   `schedule::Symbol=:auto` with values `:auto | :serial | :parallel`
   (`:auto` implements point 3; forcing exists for tests and benchmark
   sweeps). Default behavior stays results-identical.
6. **Out of scope.** Norm-perception optimization, cached
   entity-to-vertex maps (the `ADR-0015` item 4 deferral), and the
   solver rewrite are explicitly out of scope. Model results, solver
   behavior, transfer-search coverage, utility arithmetic, certificates,
   transfer probes, refinement budgets, warm starts, alternating-response
   order, convergence criteria, tie-breaking, and cached-hours commits
   are unchanged; output must remain bit-identical and thread-count
   independent.

Rejected alternatives:

- Thread-indexed buffer pools: task migration makes
  `Threads.threadid()` indexing wrong and `ADR-0015` forbids it.
- Persistent cross-tick scratch pools or world resources: task-lifetime
  ownership is the point of this change.
- Keeping `Threads.@threads :greedy` and pulling scratch from
  `task_local_storage`: ties buffer lifetime to scheduler task internals
  and still pays per-chunk body setup.
- Spawning a task per chunk or per household: task-creation churn,
  contradicting bounded worker-task creation.

## Consequences

- Scratch construction and reset now scale with the number of active
  worker tasks instead of with the number of chunks. Instrumented
  counts (`benchmark/scheduling_tuning.md` section 5, `ws_500`): the
  baseline per-chunk bodies construct 125 scratch pairs per tick (500
  households, chunk 4) at both thread counts, the bounded worker loop
  constructs exactly `min(nthreads, nchunks)` (8 at 8 threads at every
  measured chunk size, 3 when only 3 chunks exist), and the serial
  path constructs 1.
- Kernel time (20-tick `set_theta!` medians, same-session interleaved
  baseline-versus-candidate, 15-30 repetitions,
  `benchmark/scheduling_tuning.md` section 1): `ws_500` 45.8 -> 35.2
  ms at 1 thread (-23%) and 12.4 -> 8.8 ms at 8 threads (-27..-30%);
  `heterogeneous` 44.3 -> 32.4 ms (-27%) and 12.7 -> 8.6 ms (-32%);
  `ws_100` 8.78 -> 7.01 ms (-20%) and 3.14 -> 2.58 ms (-18%). Kernel
  allocation at `ws_500` falls 77%/72% in bytes and 59%/55% in object
  count (1T/8T), and end-to-end `GenderNorms.run` improves 18-23% on
  the 500-household and heterogeneous workloads (9% on `ws_100` at 8
  threads), less than the kernel because the unchanged
  `calculate_norm_perception!` shares the tick.
- Scheduling mechanism (8T, chunk 4, two interleaved rounds): the
  atomic chunk cursor is kept and the shared work queue
  (`Channel{Int}` of chunk indices, same bounded workers and scratch
  ownership, bit-identical results) rejected: the queue is slower on
  every comparison, +11.7%/+18.5% kernel median on `ws_500` and
  +3.2%/+8.3% on `heterogeneous`, and adds about 2,741 objects and
  119 KB per 20-tick kernel pass (Channel iteration machinery); the
  cursor beats the baseline `:greedy` loop by 30-36% and the rejected
  queue variant still beats it by 21-31%.
- Chunk size (forced `:parallel` at 8T, forced `:serial` at 1T):
  `HOUSEHOLD_BARGAIN_CHUNK` is re-confirmed as 4. Chunk 8 is within
  noise of 4 on `ws_500` (about 3% median, roughly 2 standard errors,
  in two runs) but worse on `heterogeneous` (median and IQR) and on
  `ws_100` (2.60 vs 2.45 ms) and produced the worse tail (54 ms
  outlier); allocation is equal for 4 and 8 because scratch
  construction is worker-scaled, so load balance decides. Chunk 16 is
  never better; chunk 32 is rejected (9.81 vs 9.18 ms on `ws_500`,
  4.82 vs 2.45 ms on `ws_100`, 75 ms tail).
- Serial crossover (8T, chunk 4, forced paths, 30 repetitions at the
  boundary): serial wins at 4 households and below (task-spawn cost
  about 0.26 ms per 20-tick pass at N = 2/4), the paths tie at 6-8
  (0.822 vs 0.824 ms at N = 8), and parallel is ahead from N = 10
  (+5.5%) and decisively from 12 (+22% at 12, +30% at 16, +51% at 24,
  up to 4.5x at 96+), selecting `HOUSEHOLD_BARGAIN_SERIAL_CUTOFF = 8`.
- Bit-identical baseline-versus-candidate: PASS. Deterministic state
  dumps (full `GenderNorms.run` plus `:local` and `:discovery`
  bargaining segments on Watts-Strogatz and homogeneous-mixing
  worlds, per-agent rows at full Float64 precision) are md5-identical
  across baseline and candidate at 1T and 8T and across thread counts;
  same-seed repeat runs are identical as well.
- Noise honesty: one first headline attempt ran under foreign machine
  load, is void, and is excluded from every number here (kept under
  `/tmp/opencode/scheduling-tuning/discarded-polluted/`);
  single-repetition outliers occurred on both sides and never moved
  the medians (the candidate's 1T repetitions are also far less
  dispersed); absolute numbers differ across sessions because CPU
  frequency is dynamic, so every comparison is same-session and
  interleaved.
- Remaining bottlenecks: the per-tick entity-index `Dict` rebuild of
  `set_theta!` (with the `Iterators.partition` chunk collection and
  the `spouse_capacity` degree scan) stays deferred with the cached
  entity-to-vertex maps of `ADR-0015` item 4; about 2.05 objects and
  390 bytes of per-household work per household-tick remain in the
  kernel; the per-agent `spouse_seen` scratch of
  `calculate_norm_perception!` is unchanged and out of scope (point
  6).
- The `ADR-0015` item C1 and `ADR-0017` item 4 wording about per-chunk
  construction is amended by this record: buffer ownership granularity
  becomes per worker task rather than per chunk body. Those records are
  not superseded; all their other content (the maximum-degree sizehint
  bound, the per-household `_reset_scratch!` reset with its non-shrinking
  sizehint, the never-`Threads.threadid()`-indexed and no-sharing rules,
  and the no-retained-parameters-or-closures rule) remains in force.
- Default `set_theta!` behavior is results-identical to the
  `Threads.@threads :greedy` implementation it replaces (verified
  bit-identical above); worker exceptions surface as
  `TaskFailedException` / `CompositeException` as under `ADR-0014`,
  and the worker-loop barrier keeps the tick sequence of `MDR-0010`
  semantics intact.
- `TASK-0025` tracked the implementation and measurement work item and
  is closed (`done`) after verification: bit-identical,
  thread-count-independent results and the full measurement plan
  above.
- No model-behavior change and no ODD change, so no MDR is needed.
- The full measurement report and its reproducible driver are
  `benchmark/scheduling_tuning.md` and `benchmark/scheduling_sweep.jl`.

## References

- `registry/code/decisions/ADR-0014-multithreaded-tick-systems.md`
- `registry/code/decisions/ADR-0015-bargaining-kernel-optimization.md`
- `registry/code/decisions/ADR-0017-interval-certificate-and-search-storage.md`
- `registry/code/decisions/ADR-0021-seeded-guidance-transfer-driver.md`
- `src/systems/household_bargaining.jl`
- `benchmark/scheduling_tuning.md`
- `benchmark/scheduling_sweep.jl`
- `registry/tasks.md`
