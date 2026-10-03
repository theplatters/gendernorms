---
id: ADR-0024
title: Task-owned norm perception scratch and bounded worker scheduling
status: accepted
date: 2026-10-03
supersedes: ""
superseded_by: ""
---

# ADR-0024: Task-owned norm perception scratch and bounded worker scheduling

## Context

The norm perception world loop `calculate_norm_perception!`
(`src/systems/norm_perception.jl`, port of the norm part of NetLogo
`calculate-utility`, ODD section Norm perception, see `MDR-0004`) ran
one `Threads.@threads :greedy` loop per gender over
`Iterators.partition` chunks of `NORM_PERCEPTION_CHUNK = 16` agents
(`ADR-0014`), and every agent iteration allocated a fresh
`spouse_seen = Ark.Entity[]` scratch vector for `norm_means`. The
measured thread scaling was negative above four threads: at 2000
agents per gender the kernel took 0.79 ms per tick at one thread, 0.48
at two, 0.38 at four, 0.75 at eight, and 3.5-4.2 at sixteen, with
per-call allocation growing from 656 KB / 11,686 objects at one thread
to 672 KB / 11,865 at sixteen (baseline table below). Two causes: the
per-chunk channel-pull churn of `Threads.@threads :greedy`, which grows
with the number of chunk-pulling threads, and the per-agent scratch
allocation (about 164 bytes and one vector per agent call), which
dominates the one-thread kernel and adds GC pressure everywhere.

Governing prior decisions:

- `ADR-0014` (superseded by `ADR-0023` for `set_theta!`) chose
  `Threads.@threads :greedy` over chunked `Iterators.partition` item
  pulling for both world loops, fixed the chunking origin, and pinned
  the worker-exception envelope (`TaskFailedException` /
  `CompositeException`). Its norm-perception loop is replaced by this
  record; the chunking origin and the exception envelope stay in
  force.
- `ADR-0015` item C1: `spouse_seen` is sizehinted to the maximum
  vertex degree of the two graphs, never indexed by
  `Threads.threadid()`, never shared across tasks.
- `ADR-0023` gave `set_theta!` task-owned scratch reuse and bounded
  worker scheduling over a shared atomic chunk cursor; its point 6
  declared norm-perception optimization out of scope. This record
  extends that pattern to `calculate_norm_perception!`. It does not
  supersede `ADR-0023` (`supersedes`/`superseded_by` stay empty):
  `ADR-0023` remains current for the bargaining kernel and this record
  adds the norm perception counterpart.

Invariants that motivate the design: bit-identical, thread-count
independent results (`MDR-0004`: neighbour sums accumulate in adjacency
order, spouses deduplicate in first-occurrence order, matching NetLogo
`calculate-utility`); no `Threads.threadid()`-indexed mutable buffers
(`ADR-0015`); scratch never shared across concurrent workers and no
persistent cross-tick pools or world resources (`ADR-0023`); and
per-agent computation only reads `old`/`current` state and writes
perception state, so chunking and scheduling cannot change results.

## Decision

1. **Bounded worker scheduling: atomic chunk cursor, one parallel
   region over both genders.** The two per-gender
   `Threads.@threads :greedy` loops are replaced by one region whose
   chunk indices are flattened over the women chunks then the men
   chunks (`wchunks = cld(nw, chunk)`, index `i <= wchunks` is women,
   else men with `j = i - wchunks`) and decoded arithmetically inside a
   single `process_chunk!` closure shared by both paths. The entity
   vectors are never concatenated and no chunk-descriptor arrays are
   allocated. At most `min(Threads.nthreads(), nchunks)` worker tasks
   claim chunk indices from a shared `Threads.Atomic{Int}` cursor
   (`atomic_add!`, stop when the claim exceeds `nchunks`); there is no
   task per chunk or per agent and no channels. The `@sync` join of the
   workers is the completion barrier before the next tick system runs,
   and a failing worker surfaces as `TaskFailedException` /
   `CompositeException` (`ADR-0014` envelope). There is no gender
   barrier: writes are disjoint per agent.
2. **Task-owned scratch.** `spouse_capacity` is computed once per call
   as the maximum vertex degree of the two graphs (the allocation-free
   expression of `ADR-0015` item C1, shared with `set_theta!`). The
   serial path owns one `sizehint!(Ark.Entity[], spouse_capacity)`
   buffer per call; each worker task constructs its own buffer in a
   fresh `let` binding inside its `Threads.@spawn` and reuses it across
   every chunk the task claims. `norm_means` empties the buffer at the
   start of its neighbour branch, so reuse across chunks is exact.
   Buffers are never indexed by `Threads.threadid()`, there is no
   task-local storage, no persistent pool, and no new world resource
   (`ADR-0023` point 1).
3. **Keyword contract.** `calculate_norm_perception!` keeps its
   two-positional-argument method (pinned by
   `test/test_decision_invariants.jl`) and gains
   `chunk::Int=NORM_PERCEPTION_CHUNK` and `schedule::Symbol=:auto`
   with values `:auto | :serial | :parallel`. `chunk >= 1` and schedule
   membership are validated before the world is touched
   (`ArgumentError`). `:serial` runs the direct loop, `:parallel`
   forces the worker path even at one thread (tests and benchmark
   sweeps), and `:auto` picks the worker path only when
   `Threads.nthreads() > 1` and the world holds more than
   `NORM_PERCEPTION_SERIAL_CUTOFF` total agents (women plus men).
   Both paths run the same `process_chunk!` closure, so results are
   bit-identical across paths, chunk sizes, and thread counts.
4. **Constants from measurements.** `NORM_PERCEPTION_CHUNK = 64`
   (replacing 16): the chunk-size sweep over {16, 32, 64, 128} at 8
   and 16 threads on 2000 agents per gender is flat within noise
   (0.070-0.088 ms per tick everywhere), 256 measurably regresses
   (0.080-0.081 at 8 threads, 0.086-0.097 at 16), and 64 is kept as
   the a-priori middle-of-the-flat-region pick, leaving 63 chunks for
   up to 16 workers at 2000 agents per gender. `NORM_PERCEPTION_SERIAL_CUTOFF = 256`
   total agents: the forced-path crossover at 8 threads measures
   serial 0.0064 vs parallel 0.0140 ms per tick at 128 total agents
   and 0.0129 vs 0.0141-0.0184 at 256 (serial wins), parallel 0.0176-0.0213
   vs serial 0.0268 at 512 (parallel wins), so the parallel path
   starts just above 256 total agents.
5. **Preserved semantics (`MDR-0004`).** The per-agent body is
   verbatim: `norm_means`, the same `Ark.get_components` calls in the
   same order, the same `norm_penalty` arguments, and the same
   `Ark.set_components!` tuple. `norm_means`, `norm_penalty`,
   `norm_global_means`, `_mean_old_working_time`, and
   `_mean_old_transfer` are untouched (the `MDR-0004` zero-allocation
   pin of `norm_means` stays green; `norm_means` keeps its second
   caller in `set_theta!`), and `globals` is computed once before any
   parallel work. Adjacency accumulation order and first-occurrence
   spouse dedup order are unchanged, so percepts and penalties are
   bit-identical to the sequential reference for any scheduling.

Rejected alternatives:

- Keeping per-agent (or per-chunk) scratch allocation: allocation
  scales with agents and was the dominant one-thread cost.
- Thread-indexed buffer pools: task migration makes
  `Threads.threadid()` indexing wrong and `ADR-0015` forbids it.
- Persistent cross-tick scratch pools or world resources: task-lifetime
  ownership is the point of this change (`ADR-0023`).
- Concatenating the entity vectors or allocating chunk-descriptor
  arrays for one region: pointless allocation and a needless order
  question; arithmetic decoding answers both.
- Keeping `Threads.@threads :greedy`: its measured thread scaling is
  negative above four threads (baseline table).

## Consequences

Final validation numbers (2026-10-03, AMD Ryzen 7 5825U, 8 cores / 16
SMT hardware threads, Julia 1.12.7, noisy desktop; whole-pass
descheduling outliers of 2-4x occur on both sides, so every comparison
below is same-session, interleaved, and reported as medians).
`benchmark/norm_perception_scaling.jl` (candidate, default
`chunk = 64`) and a measurement-identical variant of that driver
running the verbatim pre-change `Threads.@threads :greedy` kernel as
baseline; 30 ticks x 30 measured repetitions per run, two runs per
configuration, median ms per tick and per-call allocations:

- 2000 agents per gender (4000 total), median ms/tick
  (bytes/call, objects/call after the arrow):

  | threads | baseline run1 | baseline run2 | ADR-0024 run1 | ADR-0024 run2 | alloc |
  | ------- | ------------- | ------------- | ------------- | ------------- | ----- |
  | 1 | 0.860 | 0.818 | 0.227 | 0.229 | 656004 / 11686 -> 432 / 7 |
  | 2 | 0.473 | 0.510 | 0.159 | 0.155 | 656947 / 11696 -> 1872 / 29 |
  | 4 | 0.381 | 0.377 | 0.096 | 0.108 | 658926 / 11718 -> 3120 / 44 |
  | 8 | 0.750 | 0.772 | 0.076 | 0.075 | 663482 / 11768 -> 5424 / 72 |
  | 16 | 4.121 | 5.570 | 0.075 | 0.084 | 672436 / 11865 -> 10336 / 129 |

- 4000 agents per gender (8000 total), median ms/tick:

  | threads | baseline run1 | baseline run2 | ADR-0024 run1 | ADR-0024 run2 | alloc |
  | ------- | ------------- | ------------- | ------------- | ------------- | ----- |
  | 1 | 1.984 | 1.941 | 0.546 | 0.538 | 1309344 / 23325 -> 432 / 7 |
  | 2 | 1.042 | 1.070 | 0.328 | 0.328 | 1310285 / 23335 -> 1872 / 29 |
  | 4 | 0.754 | 0.828 | 0.185 | 0.203 | 1312271 / 23357 -> 3120 / 44 |
  | 8 | 1.433 | 1.466 | 0.151 | 0.156 | 1316814 / 23407 -> 5424 / 72 |
  | 16 | 6.783 | 6.479 | 0.145 | 0.129 | 1325788 / 23504 -> 10336 / 129 |

- Kernel time improves 3.1-3.7x at one to four threads, 9-10x at
  eight threads, and 48-61x at sixteen threads, and per-call
  allocation falls from one scratch vector per agent (656 KB-1.33 MB
  and 11.7k-23.5k objects per call, growing with thread count) to one
  buffer per call path (432 bytes / 7 objects serial, 1.9-10.3 KB /
  29-129 objects on the worker path, scaling with workers instead of
  agents). The residual serial 432 bytes / 7 objects per call are the
  per-call closure, buffer, and degree-scan setup and are deliberately
  not chased here.
- Thread scaling of the candidate (median of the two run medians):
  strictly decreasing 1 -> 2 -> 4 -> 8 -> 16 threads at 4000 agents per
  gender (0.542, 0.328, 0.194, 0.154, 0.137 ms/tick) and at 2000
  agents per gender through eight threads (0.228, 0.157, 0.102,
  0.076), where eight -> sixteen is a plateau within noise (0.076 ->
  0.079; the individual runs overlap at 0.075-0.084). The chunk-size
  sweep does not move that plateau (see below), and the machine has
  only eight physical cores: at 2000 agents per gender the kernel runs
  at the noise floor (about 75 microseconds per tick), where the
  per-call fixed costs (up to 16 task spawns, the max-degree scan)
  dominate whatever SMT adds. Reported honestly as a plateau within
  noise rather than a strictly decreasing step; every other step is
  strictly decreasing at both sizes.
- Chunk-size sweep (2000 agents per gender, 30 ticks x 15 reps, two
  runs per cell, forced chunk through the `NORM_PERCEPTION_CHUNK`
  default, median ms/tick): 16 -> 0.073/0.071 (8T), 0.073/0.080
  (16T); 32 -> 0.081/0.073, 0.082/0.080; 64 -> 0.070/0.073,
  0.077/0.088; 128 -> 0.073/0.078, 0.077/0.077; 256 -> 0.080/0.081,
  0.097/0.086. 16-128 are flat within noise (spread matches run-to-run
  dispersion), 256 regresses, confirming the earlier small probe that
  16 measured marginally better at 8 threads and 256 regressed;
  `NORM_PERCEPTION_CHUNK = 64` is kept as the documented a-priori
  pick rather than overfitting the noise floor.
- Serial crossover (8 threads, forced `:serial` (cutoff overridden to
  10^9) vs forced `:parallel` (cutoff 0), 30 ticks x 30 reps, median
  ms/tick): total 128 agents serial 0.0064/0.0064 vs parallel
  0.0141/0.0140; total 256 serial 0.0128/0.0130 vs parallel
  0.0141/0.0184; total 512 serial 0.0270/0.0267 vs parallel
  0.0213/0.0176. Serial wins at and below 256 total agents, parallel
  from 512, selecting `NORM_PERCEPTION_SERIAL_CUTOFF = 256`.
- Preliminary measurements (earlier same-day probes, kept for
  transparency, superseded by the tables above): the first chunk sweep
  at 30 ticks x 5 reps (8T/16T medians 0.062-0.089 for chunks
  16-128, one 16T chunk-64 run polluted to 0.375) and the first
  headline matrix at 30 ticks x 5 reps (candidate 0.23/0.16/0.10/0.07/0.09
  at 2000 and 0.51/0.31/0.20/0.15/0.16 at 4000 agents per gender for
  1/2/4/8/16 threads, with whole-pass descheduling outliers up to
  0.56 at 8 and 16 threads), which motivated the 30-repetition
  interleaved protocol of the final numbers.
- Bit-identical and thread-count independent: PASS. The full test
  suite is green at 1, 8, and 16 threads (including the bitwise
  schedule x chunk matrix of `test/test_threading.jl` over
  `(:serial, :parallel, :auto) x (1, 3, 16, 64, 256)` on short-chunk
  and shared-spouse worlds, the above-cutoff `:auto` runs, the
  fewer-chunks-than-workers and many-chunk cases, the empty-world
  no-ops, and the pre-touch `ArgumentError` validation), and
  `test/threading_driver.jl` prints byte-identical output (md5
  `3f237d58917de5ed561e61db7340ac07`, 59,894 bytes) at 1, 2, 4, 8,
  and 16 threads with `calculate_norm_perception!` and `set_theta!`
  both driven through `chunk = 3` and forced schedules.
- No model-behavior change and no ODD change: the `MDR-0004`
  consequences (percepts and penalties of NetLogo `calculate-utility`,
  adjacency order, first-occurrence spouse dedup) are preserved
  bitwise, so no MDR is needed; `registry/model/` is untouched.
- `TASK-0026` tracked the implementation, test, and measurement work
  item and is closed (`done`).
- Remaining bottlenecks: the per-call max-degree scan for
  `spouse_capacity` and the per-call task-spawn cost bound the
  small-world parallel gains (the serial crossover above); the
  `set_theta!` per-tick entity-index `Dict` rebuild stays deferred
  with the cached entity-to-vertex maps of `ADR-0015` item 4.
