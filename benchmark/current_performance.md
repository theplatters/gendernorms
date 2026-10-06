# Current implementation performance profile

Measured on 2026-10-06 at source commit
`e8ccb0ecbd85eab5aecc3bd0106cfc750d3d3c33`.

## Conclusion

**There is room for improvement, but the current implementation is already
reasonably efficient.** Bargaining accounts for about 97% of single-thread
tick time. The strongest behavior-preserving candidates are removing the
per-household sorting allocation and caching static network metadata.
Isolated prototypes together reduced tick-loop time by 4-6% on one thread
and 14-19% on eight threads across four tested workloads, with bit-identical
tested trajectories. This is pilot evidence, not a production qualification
or a promise of the same gains on other machines.

No model, solver, package dependency, or `src/` file was changed. This report
records findings and experiments, not an adopted architectural or model
decision. The reusable read-only driver is `benchmark/profile_current.jl`
(existing tooling policy `ADR-0013`; profiling completed under `TASK-0036`).

## Scope and measurement

- AMD Ryzen 7 5825U: eight physical cores, sixteen hardware threads;
  Julia 1.12.7, `--startup-file=no`.
- Production `search=:local` (`MDR-0016`), current utility arithmetic and
  derivative responses (`MDR-0017`, `MDR-0023`, `ADR-0029`), current tick
  order (`MDR-0022`). No shock resources or file/dashboard logging.
- Kernel workloads come from `benchmark/bargaining_kernel.jl`: seed 1,
  CES beta 0.5, package-default parameters, including `initial_lambda=0.5`.
  N agents per gender means N households and 2N agents. These are NOT
  NetLogo-matched runs of `benchmark/run_benchmarks.jl`.
- Baselines: 20 ticks, two discarded warmup passes and 15 measured fresh,
  identically seeded worlds per workload. Compilation and setup are excluded
  from kernel/tick timings. No forced GC between repetitions. Thread counts
  and all heavy measurement jobs ran sequentially.
- CPU profiles: six seconds per workload, 0.5 ms sampling interval;
  11,087 tick-containing samples for `ws_500` and 10,979 for `heterogeneous`.
  Allocation profiles record every allocation of one warmed trajectory.
  Neither instrumented execution time is used as a baseline.
- Prototype comparisons: 25 interleaved repetitions per variant and workload,
  reversing variant order on alternate repetitions. Absolute times vary with
  CPU frequency and session; compare variants within their own table.

The previous `benchmark/report.md` and optimization validation reports are
historical. Their timings and solver behavior must not be assumed to describe
current HEAD. NetLogo and the dashboard were not re-profiled here.

## Current warmed baseline

Medians from the existing kernel harness; milliseconds per 20-tick run.
`run` includes metric collection and run-record construction, but not
`create_world`. Setup is measured separately on one thread.

| Workload | Households | Kernel 1T | `run` 1T | Kernel 8T | `run` 8T | Setup 1T |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Watts-Strogatz | 500 | 35.42 | 36.84 | 8.38 | 9.21 | 0.29 |
| Watts-Strogatz | 100 | 7.09 | 7.43 | 2.18 | 2.78 | 0.08 |
| Homogeneous mixing | 500 | 34.32 | 34.84 | 7.91 | 9.10 | 0.20 |
| No network | 500 | 34.37 | 35.10 | 7.98 | 8.95 | 0.20 |
| Homophily | 500 | 36.22 | 37.86 | 7.73 | 8.90 | 20.88 |
| Heterogeneous wages/conformism | 500 | 34.14 | 35.79 | 8.07 | 9.27 | 0.31 |

For `ws_500`, the kernel allocates 195,020 bytes and 1,037 objects per
tick at 1T; 235,441 bytes and about 1,166 objects at 8T. Warm runtime is
compute-dominated, not GC-dominated: median timed GC is zero at this size.
At 2,000-4,000 households, observed GC is roughly 1-5% of the kernel,
depending on thread count, so reducing allocation also helps larger runs.

### Where the time goes

`ws_500`, single-thread CPU profile; **inclusive** percentages, not additive:

| Function/path | Tick samples | Interpretation |
| --- | ---: | --- |
| `set_theta!` | 97.1% | Primary target |
| `bargain_transfer` | 89.1% | Most cost is inside the pure solver chain |
| `_transfer_local_search!` | 77.6% | Includes candidate labour solves and bounds |
| `mutual_best_response` | 37.0% | Alternating labour best responses |
| `_payoff_upper_bound` | 22.0% | Certification/envelope work per transfer probe |
| `sort!` | 6.0% | Transfer-search bookkeeping |
| `norm_means` | 5.1% | Includes both perception and bargaining callers |
| `calculate_norm_perception!` | 2.7% | Small standalone tick stage |

The heterogeneous workload has the same anatomy: 96.6% bargaining,
33.4% mutual best response, and 23.0% upper bounds. Source locations:

- Labour loop: `src/optim/labour_optimization.jl:498-516`.
- Bound evaluation: `src/optim/transfer_optimization.jl:236-276` and
  `src/resources/utility_functions.jl:215-271`.
- Search sorting: `src/optim/transfer_optimization.jl:1142,1190,1218,1224`.
- Per-tick metadata rebuild: `src/systems/household_bargaining.jl:110-118`.

The lag copy, observer reduction, and preference adaptation allocate zero
bytes in the stage measurements and together cost about 0.1% of a 1T
`ws_500` tick. Optimizing or parallelizing them is low priority.

Typed solver probes infer `Tuple{Float64,Float64}` and
`Tuple{Float64,Float64,Float64}`, without `Any` or `Core.Box` in the inspected
optimized wrappers. `mutual_best_response` allocates zero bytes; a
scratch-reusing `bargain_transfer` still allocates 304 bytes for the sampled
ordinary household. There is no evidence of a broad solver type-instability
problem to fix before the concrete allocation sites below.

## Measured improvement candidates

### 1. Remove temporary sorting buffers

The full-rate allocation profile found 10,000 temporary vector headers
plus 10,000 backing memories at the Stage A `sort!(samples)` call
(`src/optim/transfer_optimization.jl:1142`): one pair per household-tick.
Julia's default tuple-vector sort enters `ScratchQuickSort`, allocates its
scratch, then uses insertion sort for the small partition. Scratch reuse
elsewhere in the solver does not prevent this allocation.

Production has at most 44 records. An explicit stable insertion sort for
these small production-only arrays, or a dedicated reusable sorting buffer,
avoids the churn without changing the probe schedule or floating-point
arithmetic. Leave the larger offline discovery arrays on their own path.

The isolated insertion-sort prototype removed about 152 KB/tick on
`ws_500`: **78% of 1T kernel allocated bytes and about 96% of allocation
objects**. Single-thread kernel time improved 2.6-4.4% across the four
workloads. At 8T, the `ws_500` runtime change was -0.6% (slightly slower,
within noise); do not claim a demonstrated 8T speedup from sorting alone.

### 2. Cache static entity indices and maximum degree

`set_theta!` rebuilds two entity-to-vertex dictionaries and scans both
graphs for maximum degree every tick. The tested worlds have fixed topology
and entity vectors. Preparing these three pieces of metadata once per
world removed 35,264 bytes/tick from the kernel and improved `ws_500`
kernel time by 2.8% at 1T and 15.8% at 8T. The larger parallel benefit is
consistent with removing work from the serial part of the tick.

This has more architectural risk than changing the small-array sort:
production needs an explicit ownership/invalidation contract for graph,
entity-vector, or population changes. Do not introduce a stale global cache,
or identify ECS query indices with graph vertices without checking the
mapping. The pilot passed immutable, caller-owned metadata to its copied
system; its preparation was outside the tick timing, not outside total
world-lifetime cost. A production design needs an ADR before implementation;
cached indices are currently deferred under `ADR-0015` / `ADR-0023`.

### Isolated A/B results

`ws_500`, 500 households, 20 ticks. KB means 1,000 bytes. These variants live
in separate temporary Julia modules; no `GenderNorms` method was replaced.
Tick-loop time includes all six systems, not runner metric/logging overhead.

| Threads | Variant | Kernel ms | Kernel IQR ms | Tick-loop ms | Allocated KB/tick |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | Current package | 37.77 | 3.29 | 39.00 | 195.05 |
| 1 | Unmodified copied control | 37.83 | 1.92 | 39.05 | 195.05 |
| 1 | Insertion sort | 36.11 | 1.62 | 37.30 | 42.96 |
| 1 | Cached indices/degree | 36.73 | 1.92 | 38.01 | 159.79 |
| 1 | Both | 35.35 | 0.42 | 36.56 | 7.70 |
| 8 | Current package | 9.50 | 1.20 | 10.45 | 235.47 |
| 8 | Unmodified copied control | 9.38 | 1.09 | 10.78 | 235.47 |
| 8 | Insertion sort | 9.55 | 1.33 | 10.49 | 83.39 |
| 8 | Cached indices/degree | 7.99 | 1.06 | 8.94 | 200.21 |
| 8 | Both | 7.80 | 0.44 | 8.75 | 48.12 |

Together: `ws_500` kernel time -6.4%/-17.8% and tick-loop time
-6.3%/-16.2% at 1T/8T; allocated bytes -96%/-80%. Across `ws_500`,
heterogeneous, homogeneous mixing, and zero-conformism workloads, combined
tick-loop reductions were 4.4-6.4% at 1T and 14.0-18.6% at 8T.

Validation compared the UInt64 representations of current/lagged hours and
transfers, current/pre-shock preferences, committed utility, norm parameter,
perceived own-hours norm, and all four observer resources after every one
of 20 ticks, on all four workloads at both thread counts. All comparisons
passed, including NaNs and signed zeros. This does NOT replace the full
solver/certificate/fallback/lifecycle test battery required for adoption.
Small runtime deltas remain noise-sensitive; the copied control was 9.8%
slower on 8T homogeneous mixing, demonstrating that module/codegen/scheduling
noise can exceed the sorting-only gain.

## Other opportunities and limits

### Fresh-process latency dwarfs short warmed runs

Three sequential fresh processes executed a minimal top-level
`parse_spec` -> `create_world` -> `run` workload: 100 households,
20 ticks, seed 1, Watts-Strogatz, CES beta 0.5, package defaults,
one thread, no file logging. Installed package caches were not cleared;
these are first-use timings, not installation/precompilation timings.

| Phase | Median seconds |
| --- | ---: |
| Package load | 0.840 |
| First `parse_spec`, including dictionary input construction | 1.888 |
| First `create_world` | 4.125 |
| First `run`, 20 ticks | 5.705 |
| Entire fresh process, measured externally | 12.768 |

External process times ranged from 12.426 to 13.203 seconds. By contrast,
the warmed `ws_100` baseline above takes 7.43 ms for `run` and about
0.08 ms for setup. First-call compilation and startup dominate this
short one-off workflow; these phase timings do not separately attribute
every second to compiler work.

For batches of short runs, reuse a warmed Julia process rather than
launching one process per replication. If fresh-process latency matters,
representative precompilation workloads or a system image are worthwhile
next experiments. Their gains were not measured here, and no startup,
precompilation, or dependency changes were made.

### Network setup is a separate quadratic hotspot

Fresh-world setup medians, nine measured repetitions after two warmups,
single-thread, same seed/default traits. MB means 1,000,000 bytes.

| Network | N=100 ms | N=500 ms | N=2,000 ms | Allocated MB at N=2,000 |
| --- | ---: | ---: | ---: | ---: |
| Watts-Strogatz | 0.067 | 0.228 | 0.977 | 2.37 |
| Similarity | 0.846 | 18.541 | 278.514 | 325.56 |
| Homophily | 0.916 | 20.178 | 311.284 | 325.62 |

`generate_similarity`, `generate_homophily`, and `sample_nodes`
(`src/resources/social_network.jl:60-106`) create weights, candidates,
sampling keys, and selection storage for each agent, doing all-pairs work.
From 500 to 2,000 households, setup grows about 15-16x for a 4x population.
At 500 households it already adds about 20 ms to a roughly 38 ms homophily
run; at 2,000 it can dominate short runs.

Reusing these buffers is a worthwhile **unmeasured** next candidate for
repeated homophily/similarity experiments. It can reduce allocation without
removing all-pairs computation. Preserve RNG draw order, exact key
arithmetic, and sampling tie behavior; switching to approximate network
construction or a different sampling algorithm is not a free optimization
of ODD Network formation / NetLogo `generate-network` and
`generate-homophilic-network`.

### More threads are not automatically better

Median tick-system totals, milliseconds per tick, aggregated per repetition
before taking the median. Separate sequential processes per thread count;
small differences are not interleaved A/B evidence.

| Households | 1T | 4T | 8T | 16T |
| --- | ---: | ---: | ---: | ---: |
| 100 | 0.383 | 0.154 | 0.141 | 0.164 |
| 500 | 1.926 | 0.631 | 0.518 | 0.589 |
| 2,000 | 7.977 | 2.605 | 1.980 | 1.989 |
| 4,000 | 16.635 | 5.416 | 3.851 | 3.781 |

Eight threads are a sensible default on this eight-core CPU. Sixteen
hardware threads do not deliver another 2x: the large-population whole
tick is effectively flat, and smaller populations get slower. Bargaining
still accounts for about 91-94% at 8T. This supports the existing floor
investigation in `TASK-0027`; it does not by itself distinguish atomic
cursor contention, memory effects, SMT, or task scheduling as the cause.

### Preserve the numerical/model contracts

The larger CPU targets are labour solves and certified bounds, not logging
or statistics. Preparing invariant bound inputs once per household is a
possible further experiment, but no speedup was measured for it here.
Likewise, `norm_means` is called in both perception and bargaining; sharing
a complete lagged-norm snapshot may remove some duplicate work, but the
current component only stores the own-hours mean, not all three norms.
The measured 5.1% includes both callers, so it is not all removable.

The utility sweep at 500 households measured 1.82/1.93/1.84/3.47/7.59
ms/tick for additive / CES beta 0.5 / multiplicative / weighted
multiplicative / CES beta 0.3. Existing beta-0.5 sqrt/square specialization
is already effective; changing beta or utility form changes the model.

Do not obtain speedups by dropping transfer probes, weakening tolerances or
certificate guards, changing warm starts, or assuming zero transfer is
always optimal. These change the coverage/correctness contracts of
`MDR-0016` / `MDR-0017` and require model decisions and renewed validation.

## Reproduction and artifacts

```sh
JULIA_NUM_THREADS=1 julia --startup-file=no --project=. benchmark/bargaining_kernel.jl all 20 15
JULIA_NUM_THREADS=8 julia --startup-file=no --project=. benchmark/bargaining_kernel.jl all 20 15
JULIA_NUM_THREADS=1 julia --startup-file=no --project=. benchmark/profile_current.jl /tmp/opencode/gn-profile all ws_500,heterogeneous 15 6
JULIA_NUM_THREADS=8 julia --startup-file=no --project=. benchmark/profile_current.jl /tmp/opencode/gn-profile-8t timings ws_100,ws_500,ws_2000,ws_4000 15
```

Original artifacts from this session, intentionally outside the package:

- `/tmp/opencode/gendernorms-baseline-1t.txt` and
  `/tmp/opencode/gendernorms-baseline-8t.txt`: baseline summaries and raw reps.
- `/tmp/opencode/gendernorms-current-profile-1t/`: stage CSVs, CPU flat/tree
  reports, function/leaf sample counts, allocation totals and example stacks.
- `/tmp/opencode/gendernorms-stage-sweep-{1,4,8,16}t/`: raw/summary stage CSVs;
  launcher `/tmp/opencode/gendernorms-stage-sweep.jl`.
- `/tmp/opencode/gendernorms-sort-experiment-{1,8}t/raw.csv`: all interleaved
  prototype measurements; driver `/tmp/opencode/gendernorms-sort-experiment.jl`.
  Invoke with `JULIA_NUM_THREADS=1` or `8`, `julia --startup-file=no
  --project=. /tmp/opencode/gendernorms-sort-experiment.jl`.
- `/tmp/opencode/gendernorms-extra-probes/`: raw setup measurements, typed
  solver inference, and allocation probes; driver
  `/tmp/opencode/gendernorms-extra-probes.jl`.
- `/tmp/opencode/gendernorms-cold-runtime-sweep.log`: the three minimal
  fresh-process measurements; probe
  `/tmp/opencode/gendernorms-cold-runtime.jl` and launcher
  `/tmp/opencode/gendernorms-cold-sweep.jl`. Reproduce with
  `julia --startup-file=no --project=. /tmp/opencode/gendernorms-cold-sweep.jl`.

The temporary prototype driver copies exact function ranges from the
recorded source commit; it is diagnostic scaffolding, not a maintained
optimization implementation. Reproduce it against that commit before
changing source line ranges. Temporary paths may not survive cleanup;
the tables above retain the findings and the read-only driver reproduces
the core profiling methodology.

## Verification

- Profiling driver smoke-tested with all sections at 1T and timings at 8T
  (`ws_100`, two repetitions); generated CSVs checked for field counts,
  embedded-quote escaping, and allocation source grouping.
- `julia --project=. scripts/registry_check.jl --strict`: zero warnings/errors.
  The initially reported missing registry entry for the existing `_is_ok`
  helper was documented in `registry/code/architecture.md`; no solver edit.
- `julia --project=. -e 'using GenderNorms'`: passed.
- `JULIA_NUM_THREADS=1 julia --startup-file=no --project=. test/runtests.jl`:
  187 test sets, 214,421 passing assertions (including cross-thread checks).
  This checks the unchanged package, not qualification of the temporary
  optimization prototypes. Logs:
  `/tmp/opencode/gendernorms-profile-tests.log` and
  `/tmp/opencode/gendernorms-profile-registry-check.log`.
