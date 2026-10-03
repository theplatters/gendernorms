# Scheduling tuning for the household bargaining kernel (ADR-0023)

Measurement report for the task-owned bargaining scratch and bounded
worker scheduling change (`registry/code/decisions/ADR-0023-task-owned-
bargaining-scratch.md`, `src/systems/household_bargaining.jl`
`set_theta!`). It selects `HOUSEHOLD_BARGAIN_CHUNK`, selects
`HOUSEHOLD_BARGAIN_SERIAL_CUTOFF`, and decides the scheduling
mechanism (atomic chunk cursor vs shared work queue) against the
baseline `Threads.@threads :greedy` loop. All raw observations are
kept; noisy and regressing cases are reported as measured.

## Environment

- Date: 2026-10-02 (measurement runs 14:28-14:57 local time,
  UTC+02:00).
- Baseline revision: `a3a379d9b9d96ce3bc5bd8a89a9199cf9f2f318d`
  (`a3a379d add derivative solver validation evidence and close
  TASK-0023`), run from the registered git worktree
  `/tmp/opencode/gendernorms-baseline` (clean at that revision plus
  the extended benchmark driver, identical to the main tree's
  `benchmark/bargaining_kernel.jl`).
- Candidate: the uncommitted main tree at
  `/home/franzs/Schreibtisch/Arbeit/gendernorms`
  (`src/systems/household_bargaining.jl` with the `ADR-0023`
  implementation, default `chunk = 4`, `schedule = :auto`).
- Julia: `julia version 1.12.7`.
- CPU: AMD Ryzen 7 5825U with Radeon Graphics, 8 cores / 16 hardware
  threads, SMT 2 threads/core, dynamic frequency (about 3.6 GHz at
  capture). One configuration at a time, sequential, no concurrent
  heavy jobs; every run was gated on a quiet-machine check (no
  competing Julia process for 45 s before the run starts).
- Thread counts: `JULIA_NUM_THREADS=1` and `JULIA_NUM_THREADS=8`,
  always explicit.

Machine-instability context: frequency scaling is dynamic, and
single-repetition outliers occur on both sides of every comparison
(see the `max` columns below; for example one 61.6 ms repetition in an
otherwise 35.1-35.4 ms `hl_cand_ws500_t1_r1` run and one 29.0 ms
repetition in `hl_base_ws100_t1`). Medians and IQRs are reported so
these do not distort the comparison. Absolute numbers from earlier
sessions are not comparable: the WP-A baseline of the same day
(12:16-12:19) measured `ws_500` 8T kernel medians around 16.6 ms
while today's interleaved baseline runs measure 12.2-12.7 ms on the
same code, so every comparison in this report is same-session and
interleaved. A first attempt at the headline matrix (14:13-14:24) ran
while an unrelated foreign test process was active on the machine;
those runs are void, were excluded from every number here, and are
kept only under `/tmp/opencode/scheduling-tuning/discarded-polluted/`.

## Methodology

Unchanged from `benchmark/bargaining_kernel.jl` (`MDR-0011`,
`ADR-0013`): seed-1 workload specs (`workload_spec` name/seed
contract preserved), one fresh `create_world` per measured repetition
(identical initial states across repetitions), one discarded tiny and
one discarded full-size JIT warmup pass per configuration, 20 ticks
per pass in the `MDR-0010` tick order with only the `set_theta!`
calls timed (`time_ns()`, `Base.gc_num()` deltas around exactly those
calls), 15 measured repetitions per configuration (30 for the chunk
tiebreaker and the crossover boundary run), no GC forced between
repetitions, and one `GenderNorms.run` end-to-end timing per
repetition on a second fresh world, reported separately. Statistics
use `Statistics.quantile` linear interpolation.

Two drivers, identical measurement code:

- `benchmark/bargaining_kernel.jl` (unchanged) for the
  baseline-vs-candidate headline runs; its `set_theta!(world,
  config.utility)` call uses each tree's defaults, so the baseline
  worktree runs `Threads.@threads :greedy` and the candidate runs
  `chunk = 4, schedule = :auto`.
- `benchmark/scheduling_sweep.jl` (new, additive) for all sweeps; it
  reuses `BargainingKernelBench.workload_spec` (the same module
  contract `benchmark/anchor_local_validation.jl` uses) and adds only
  the `ws_<N>` population workload (seed 1, Watts-Strogatz
  `neighbors_per_side` 2, `rewiring` 0.1, CES `beta` 0.5, `N` agents
  per gender = `N` households) and the `chunk` / `schedule` / `search`
  keywords of `set_theta!`. Its `schedule` symbol is the scheduling
  variant switch: `:serial` / `:parallel` / `:auto` run against the
  current tree, `:queue` runs only against the throwaway queue tree.

Interleaving actually used:

- Headline `ws_500`, both thread counts: ABAB over two rounds
  (baseline 1T, candidate 1T, baseline 8T, candidate 8T; repeated),
  labels `*_r1` / `*_r2`.
- Headline `heterogeneous` and `ws_100`: AB per thread count
  (baseline 1T, candidate 1T, baseline 8T, candidate 8T).
- Variant comparison: ABAB at process level (greedy, cursor+queue in
  one process per workload pair, greedy, cursor+queue), with cursor
  and queue adjacent within each process, plus one main-tree cursor
  cross-check run.

## 1. Interleaved baseline vs candidate (headline matrix)

Kernel time `kernel_s` = sum of the `set_theta!` calls over 20 ticks
of a 500-household (or 100-household) world, in milliseconds.
Allocation is the timed-section total of the same 20 ticks.
`e2e_s` is the separate full `GenderNorms.run` (all systems).
Medians [Q25, Q75] over 15 repetitions per run.

### Kernel time (ms, 20-tick sum)

| workload | threads | baseline med [Q25, Q75] | candidate med [Q25, Q75] | delta med |
|---|---|---|---|---|
| ws_500 (r1) | 1 | 45.773 [45.267, 48.097] | 35.243 [35.204, 35.400] | -23.0% |
| ws_500 (r2) | 1 | 45.958 [45.057, 47.070] | 35.220 [35.158, 35.285] | -23.4% |
| ws_500 (r1) | 8 | 12.541 [12.207, 13.339] | 8.820 [8.204, 9.090] | -29.7% |
| ws_500 (r2) | 8 | 12.178 [11.616, 13.320] | 8.864 [8.366, 9.362] | -27.2% |
| heterogeneous | 1 | 44.288 [42.999, 46.307] | 32.400 [32.360, 32.456] | -26.8% |
| heterogeneous | 8 | 12.673 [11.598, 16.323] | 8.600 [8.282, 9.363] | -32.1% |
| ws_100 | 1 | 8.778 [8.765, 8.798] | 7.006 [6.993, 7.022] | -20.2% |
| ws_100 | 8 | 3.140 [2.907, 3.753] | 2.579 [2.453, 2.828] | -17.9% |

Min/max (tail honesty): baseline `ws_500` 1T 43.3-64.0 ms, candidate
`ws_500` 1T 35.1-61.6 ms (r1) and 35.1-35.7 ms (r2); baseline
`heterogeneous` 8T 9.5-32.8 ms, candidate `heterogeneous` 8T
8.1-9.7 ms; baseline `ws_100` 1T 8.7-29.0 ms (one 29.0 ms outlier),
candidate `ws_100` 1T 7.0-7.1 ms. The single-rep outliers hit both
sides and never move medians; the candidate's 1T repetitions are also
far less dispersed (IQR 0.1-0.2 ms vs 2.0-3.3 ms).

### Kernel allocation (20-tick totals, medians)

| workload | threads | baseline bytes / count | candidate bytes / count | delta bytes | delta count |
|---|---|---|---|---|---|
| ws_500 | 1 | 16,612,752 / 51,014 | 3,899,760 / 20,720 | -76.5% | -59.4% |
| ws_500 | 8 | 16,686,928 / 51,725 | 4,705,616 / 23,292 | -71.8% | -55.0% |
| heterogeneous | 1 | 16,561,216 / 50,662 | 3,848,896 / 20,382 | -76.8% | -59.8% |
| heterogeneous | 8 | 16,635,824 / 51,378 | 4,654,176 / 22,942 | -72.0% | -55.3% |
| ws_100 | 1 | 3,399,264 / 10,988 | 911,264 / 4,708 | -73.2% | -57.2% |
| ws_100 | 8 | 3,474,224 / 11,707 | 1,716,544 / 7,268 | -50.6% | -38.0% |

The 8T candidate allocates more than the 1T candidate (4.7 MB vs
3.9 MB at `ws_500`): the parallel path constructs 8 worker scratch
pairs per tick instead of 1 (see section 5). Allocation counts are
nearly deterministic within a configuration (IQR at most a few
objects).

### End-to-end `GenderNorms.run` (ms, medians; separate from kernel)

| workload | threads | baseline | candidate | delta |
|---|---|---|---|---|
| ws_500 (r1/r2) | 1 | 49.47 / 49.56 | 39.57 / 39.32 | -20.1% / -20.7% |
| ws_500 (r1/r2) | 8 | 18.33 / 17.96 | 14.31 / 14.27 | -21.9% / -20.5% |
| heterogeneous | 1 | 48.07 | 36.83 | -23.4% |
| heterogeneous | 8 | 18.10 | 14.11 | -22.0% |
| ws_100 | 1 | 9.84 | 8.04 | -18.3% |
| ws_100 | 8 | 5.53 | 5.02 | -9.2% |

End-to-end speedups are smaller than kernel speedups because
`GenderNorms.run` also executes `calculate_norm_perception!` and the
other tick systems, which this task does not change.

## 2. Chunk-size sweep (candidate)

Forced `:parallel` at 8T (isolates the worker schedule from the
`:auto` serial path) and forced `:serial` at 1T (chunk size only
affects partitioning there), 20 ticks, 15 reps. Kernel medians in ms
[Q25, Q75], allocation as 20-tick totals.

8T, `schedule=:parallel`:

| workload | chunk | med [Q25, Q75] | min | max | bytes | count |
|---|---|---|---|---|---|---|
| ws_500 | 4 | 9.181 [8.381, 9.838] | 7.941 | 10.936 | 4,706,256 | 23,312 |
| ws_500 | 8 | 8.926 [8.473, 9.979] | 8.083 | 11.882 | 4,687,376 | 23,312 |
| ws_500 | 16 | 8.945 [8.525, 9.884] | 8.338 | 10.654 | 4,676,496 | 23,312 |
| ws_500 | 32 | 9.811 [8.849, 10.831] | 8.493 | 74.969 | 4,671,472 | 23,314 |
| heterogeneous | 4 | 8.075 [7.810, 8.612] | 7.695 | 14.499 | 4,654,816 | 22,962 |
| heterogeneous | 8 | 8.012 [7.894, 8.910] | 7.696 | 11.212 | 4,635,936 | 22,962 |
| heterogeneous | 16 | 8.463 [8.027, 9.891] | 7.708 | 56.230 | 4,625,056 | 22,962 |
| heterogeneous | 32 | 9.135 [8.498, 9.725] | 7.690 | 12.639 | 4,619,936 | 22,962 |
| ws_100 | 4 | 2.454 [2.433, 2.554] | 2.182 | 4.250 | 1,717,184 | 7,288 |
| ws_100 | 8 | 2.602 [2.439, 2.735] | 2.205 | 4.150 | 1,713,024 | 7,288 |
| ws_100 | 16 | 3.234 [2.846, 3.493] | 2.588 | 7.521 | 1,598,944 | 6,968 |
| ws_100 | 32 | 4.825 [4.628, 4.980] | 4.396 | 5.393 | 1,261,504 | 6,008 |

1T, `schedule=:serial`: `ws_500` medians 35.669 / 35.649 / 35.682 /
35.660 ms and `heterogeneous` 32.724 / 32.663 / 32.680 / 32.664 ms
for chunk 4/8/16/32 - flat, as expected (one scratch pair regardless
of chunking; only the chunk-range objects shrink, 3,900,400 ->
3,865,520 bytes at `ws_500`). `ws_100` 1T is flat as well
(7.058-7.108 ms).

Focused 30-rep tiebreaker at 8T (`schedule=:parallel`), to resolve
the chunk 4 vs 8 question:

| workload | chunk | med | IQR | min | max |
|---|---|---|---|---|---|
| ws_500 | 4 | 9.030 | 0.967 | 8.002 | 10.273 |
| ws_500 | 8 | 8.739 | 1.040 | 7.784 | 54.075 |
| heterogeneous | 4 | 8.041 | 0.917 | 7.489 | 11.583 |
| heterogeneous | 8 | 8.166 | 1.544 | 7.457 | 10.695 |

Selection (`ADR-0023` point 4): `ws_500` puts chunk 8 about 3%
(0.29 ms, roughly 2 standard errors of the median) ahead of chunk 4
in both runs, `heterogeneous` splits the two runs and favors chunk 4
on both median and IQR in the higher-rep run, `ws_100` clearly favors
chunk 4 (2.45 vs 2.60 ms, and 16/32 are much worse because 100
households at chunk 32 leave only 4 chunks for 8 workers). Tail
behavior favors chunk 4 (chunk 8 produced a 54 ms outlier, chunk 32 a
75 ms and a 56 ms outlier; coarser chunks amplify the per-household
cost variance of the Brent iterations). Allocation is essentially
equal for 4/8 (worker-scaled, not chunk-scaled; see section 5).
Conclusion: there is no consistent median winner between 4 and 8 on
the selection workloads, allocation is not a differentiator, and
load balance (tail behavior, `ws_100`, populations near the serial
cutoff) favors the finer granularity. **`HOUSEHOLD_BARGAIN_CHUNK`
stays 4.** Chunk 16 is acceptable but never better; chunk 32 is
rejected (worst medians and the worst observed tail).

## 3. Scheduling-mechanism variants (8T, chunk 4, forced paths)

Three mechanisms, 20 ticks, 15 reps per run, two interleaved rounds
(`r1`, `r2`); cursor and queue measured in one process per round
against the clean throwaway queue tree
(`/tmp/opencode/gendernorms-queue-clean`), greedy in the baseline
worktree, plus a main-tree cursor cross-check. Kernel medians in ms
[Q25, Q75]; allocation as 20-tick totals.

| workload | mechanism | med r1 | med r2 | IQR r1/r2 | bytes | count |
|---|---|---|---|---|---|---|
| ws_500 | `@threads :greedy` (baseline) | 12.520 | 12.818 | 1.815 / 1.463 | 16,687,152 | 51,727 |
| ws_500 | cursor (`:parallel`, throwaway tree) | 8.776 | 8.513 | 0.894 / 1.271 | 4,712,384 | 23,513 |
| ws_500 | cursor (`:parallel`, main tree) | 8.312 | - | 0.572 | 4,706,256 | 23,312 |
| ws_500 | queue (`:queue`, throwaway tree) | 9.800 | 10.091 | 0.800 / 1.622 | 4,831,824 | 26,254 |
| heterogeneous | `@threads :greedy` (baseline) | 12.383 | 12.703 | 2.358 / 1.476 | 16,635,520 | 51,374 |
| heterogeneous | cursor (`:parallel`, throwaway tree) | 8.435 | 8.126 | 1.440 / 1.071 | 4,660,896 | 23,162 |
| heterogeneous | cursor (`:parallel`, main tree) | 8.182 | - | 1.274 | 4,654,816 | 22,962 |
| heterogeneous | queue (`:queue`, throwaway tree) | 8.708 | 8.803 | 0.718 / 1.266 | 4,780,336 | 25,903 |

Verdict (decision criterion: lower kernel median on both selection
workloads in both interleaved rounds, with tails not worse): the
**atomic chunk cursor wins** and stays in the main tree. The queue is
slower on every comparison: `ws_500` +11.7% / +18.5% vs cursor,
`heterogeneous` +3.2% / +8.3%, and it allocates about 2,741 more
objects and 119 KB more per 20-tick kernel pass (Channel iteration
machinery). Rejected option documented here: shared work queue
(`Channel{Int}` of chunk indices, closed after filling and drained by
iteration by the same bounded worker tasks, identical scratch
ownership and join barrier; implemented only in the throwaway tree,
results bit-identical to the cursor). Its measured numbers are the
`queue` rows above. The cursor beats the baseline `:greedy` loop by
30-36% at 8T and the rejected queue variant still beats it by 21-31%;
both cut kernel allocation by about 71-72%.

The main-tree cursor run agrees with the cursor run in the throwaway
tree (8.31 vs 8.51-8.78 ms at `ws_500`), so the throwaway comparison
is representative; the throwaway copy's cursor path allocates 201
more objects per pass than the main tree's, an artifact of the extra
variant branch in that copy's `set_theta!`.

## 4. Serial crossover (8T, chunk 4, forced `:serial` vs `:parallel`)

`ws_<N>` populations, 20 ticks, 15 reps per configuration in one
process (schedule order serial, parallel, auto per population);
`auto` rows show what the default `:auto` schedule actually picked
(serial for `N <= 64` with the provisional cutoff 64). Kernel medians
in ms over 20 ticks:

| N | serial | parallel | auto | faster path |
|---|---|---|---|---|
| 2 | 0.408 | 0.673 | 0.274 | serial (+66%) |
| 4 | 0.451 | 0.719 | 0.506 | serial (+59%) |
| 8 | 0.828 | 0.848 | 1.299 | tie |
| 16 | 2.205 | 0.994 | 2.142 | parallel (2.2x) |
| 32 | 3.268 | 1.185 | 3.266 | parallel (2.8x) |
| 48 | 4.835 | 1.401 | 4.366 | parallel (3.5x) |
| 64 | 6.053 | 1.854 | 5.967 | parallel (3.3x) |
| 96 | 9.321 | 2.089 | 2.294 | parallel (4.5x) |
| 128 | 12.000 | 2.710 | 2.755 | parallel (4.4x) |
| 192 | 17.108 | 3.748 | 3.886 | parallel (4.6x) |
| 256 | 22.345 | 4.941 | 4.942 | parallel (4.5x) |

Small populations are noisy at these scales: the `auto` and `serial`
rows run identical code below the cutoff yet differ by up to 33% at
N = 2 and N = 8 (`auto` 0.274 vs `serial` 0.408 at N = 2), so the
boundary was re-measured with 30 reps on `serial` and `parallel`
only. Kernel medians in ms:

| N | serial | parallel | parallel advantage |
|---|---|---|---|
| 6 | 0.767 | 0.762 | +0.7% (tie) |
| 8 | 0.822 | 0.824 | -0.2% (tie) |
| 10 | 1.012 | 0.956 | +5.5% |
| 12 | 1.242 | 0.970 | +21.9% |
| 16 | 1.610 | 1.120 | +30.4% |
| 24 | 2.540 | 1.243 | +51.1% |

The two schedules tie through N = 8, the parallel path is ahead from
N = 10 and decisively from N = 12, and the serial path is clearly
better at N <= 4 (task-spawn cost about 0.26 ms per 20-tick pass at
N = 2/4). Recommendation (the `:auto` rule is "serial when the group
holds at most the cutoff"): **`HOUSEHOLD_BARGAIN_SERIAL_CUTOFF = 8`**,
i.e. groups of at most 8 households run serial and 9+ run parallel;
the 9-10 household region is a measured tie-to-slightly-positive
region, and every population at 12+ gains 22-51% (up to 4.5x at 96+)
from the parallel path. This replaces the provisional value 64, which
leaves populations of 16-64 households on a serial path that measures
2.2-3.3x slower (for example 6.053 ms serial vs 1.854 ms parallel at
N = 64). Implementing the constant change in
`src/systems/household_bargaining.jl` is follow-up work of the
`ADR-0023` acceptance (main-tree `src/` is out of scope for this
report).

## 5. Scratch-construction scaling

Instrumented throwaway copies (`/tmp/opencode/gendernorms-scratchcount`
for the candidate, `/tmp/opencode/gendernorms-baseline-instr` for the
baseline, `/tmp/opencode/gendernorms-queue` for the queue variant)
count `TransferSearchScratch` and `spouse_seen` constructions and
processed chunks per `set_theta!` call
(`/tmp/opencode/scratch_construction_count.jl`, `ws_500`, 3 ticks,
counts identical per tick):

| variant | threads | chunk | chunks/tick | scratch pairs/tick | spouse_seen/tick |
|---|---|---|---|---|---|
| baseline `:greedy` | 8 | 4 | 125 | 125 | 125 |
| baseline `:greedy` | 1 | 4 | 125 | 125 | 125 |
| candidate `:serial` | 1 | 4 | 125 | 1 | 1 |
| candidate `:auto` (-> serial) | 1 | 4 | 125 | 1 | 1 |
| candidate cursor `:parallel` | 8 | 1 | 500 | 8 | 8 |
| candidate cursor `:parallel` | 8 | 4 | 125 | 8 | 8 |
| candidate cursor `:parallel` | 8 | 8 | 63 | 8 | 8 |
| candidate cursor `:parallel` | 8 | 32 | 16 | 8 | 8 |
| candidate cursor `:parallel` | 8 | 64 | 8 | 8 | 8 |
| candidate cursor `:parallel` | 8 | 200 | 3 | 3 | 3 |
| candidate `:auto` (-> parallel) | 8 | 4 | 125 | 8 | 8 |
| queue variant `:queue` | 8 | 4 | 125 | 8 | 8 |

Constructions per tick are exactly `min(nthreads, nchunks)` on the
parallel path (1 on the serial path) and never scale with the chunk
count: 500 chunks still construct 8 pairs, and 3 chunks construct 3.
The baseline constructs one pair per chunk body (125/tick at
`ws_500`, chunk 4) at both thread counts.

Honest scope statement: not all kernel allocation becomes
worker-scaled. From the headline `ws_500` 1T allocation delta
(baseline 51,014 objects / 16.61 MB minus candidate 20,720 / 3.90 MB
over 20 ticks) a scratch pair costs about 12 objects and 5.1 KB, and
the removed 124 pairs per tick account for essentially the whole
count delta: after subtracting the measured scratch-pair cost, both
revisions leave about 2.05 objects per household-tick (naive
per-household totals are 5.10 in the baseline and 2.07 in the
candidate). What remains in the
candidate is per-household work: `Ark.get_components` / component
writes, the household-bound `evaluate_transfer` closure of
`bargain_transfer`, Dict lookups in `norm_means`, the per-tick
entity-index Dict rebuild in `set_theta!`, the `Iterators.partition`
chunk collection, and the per-worker scratch pairs themselves
(8/tick at 8T vs 1/tick at 1T: the 8T candidate allocates 0.81 MB
more per 20-tick pass than the 1T candidate).

## 6. Bit-identical baseline vs candidate

Deterministic state dumps (`/tmp/opencode/determinism_dump.jl`, run
unmodified against both trees: full `GenderNorms.run` plus same-seed
repeat on a Watts-Strogatz and a homogeneous-mixing world, and
`:local` and `:discovery` bargaining segments (three ticks of
`calculate_norm_perception!` + `set_theta!`) with per-agent rows at
full Float64 precision, 560 lines of output per invocation) were
produced at 1T and 8T and diffed byte for byte:

- baseline@1T == candidate@1T: identical
- baseline@8T == candidate@8T: identical
- candidate@1T == candidate@8T: identical (thread-count independence)
- baseline@1T == baseline@8T: identical

All four dumps share the same md5 (`1207b51bfa778efaf7b8a6e9778fda7c`
on the 2026-10-02 files under `/tmp/opencode/scheduling-tuning/`).
Covered search modes: `:local` and `:discovery`; covered networks:
Watts-Strogatz and homogeneous mixing (exercises the `norm_global_means`
path). No mismatch; the STOP condition did not trigger. (Within-tree
thread-count independence is additionally covered by
`test/test_threading.jl` and `test/threading_driver.jl` of the
candidate.)

## 7. Remaining bottlenecks (out of scope for this task)

- `calculate_norm_perception!` with its per-agent `spouse_seen` scratch
  (explicitly out of scope, `ADR-0023` point 6) dominates the
  end-to-end remainder; the e2e speedup (-18% to -23%) is smaller than
  the kernel speedup because of it.
- Per-tick entity-index Dict rebuild in `set_theta!`
  (`women_index` / `men_index`), the `Iterators.partition` chunk
  collection, and `spouse_capacity` degree scan: fixed per-tick costs
  that matter most at small populations (visible in the crossover's
  0.26 ms task/path overhead at N = 2-4).
- Per-household allocations (component reads/writes, the
  `evaluate_transfer` closure, `norm_means` Dict lookups): about 2.07
  objects and 390 bytes per household-tick remain in the candidate
  kernel.
- Parallel efficiency of the kernel is about 4.0x at 8T (`ws_500`
  candidate: 35.2 ms -> 8.8 ms); the per-tick serial fraction and the
  uneven per-household Brent iterations bound the speedup well below
  8x.
- The `_reset_scratch!` `empty!` + `sizehint!` per household remains,
  as designed (`ADR-0017`); it is cheap but nonzero.

## 8. Raw data paths

- Clean per-run outputs (all numbers above):
  `/tmp/opencode/scheduling-tuning/runs/*.out` (26 runs; timeline
  with start/end timestamps in `/tmp/opencode/scheduling-tuning/timeline.log`).
- Merged raw per-repetition table (1785 rows):
  `/tmp/opencode/scheduling-tuning/raw_all.csv`; recomputed
  statistics (median/Q25/Q75/IQR/min/max per configuration):
  `/tmp/opencode/scheduling-tuning/summary_stats.csv`
  (`/tmp/opencode/scheduling-tuning/summarize.jl`).
- Scratch-construction counts:
  `/tmp/opencode/scheduling-tuning/scratch-counts/*.txt`.
- Determinism dumps: `/tmp/opencode/scheduling-tuning/det_*.txt`.
- Void runs excluded from this report (foreign CPU load):
  `/tmp/opencode/scheduling-tuning/discarded-polluted/`.
- WP-A pre-change baseline (context, quiet machine, same day):
  `/tmp/opencode/bargaining-baseline/`.
- Throwaway trees (not part of the repository):
  `/tmp/opencode/gendernorms-queue` (queue variant + counters),
  `/tmp/opencode/gendernorms-queue-clean` (queue variant, timing),
  `/tmp/opencode/gendernorms-scratchcount` (candidate + counters),
  `/tmp/opencode/gendernorms-baseline-instr` (baseline + counters);
  scripts `/tmp/opencode/scratch_construction_count.jl`,
  `/tmp/opencode/determinism_dump.jl`.

## Recommendation

- **`HOUSEHOLD_BARGAIN_CHUNK = 4`** (unchanged). Chunk 8 is within
  noise of chunk 4 on `ws_500` (3% median advantage, about 2
  standard errors, in two runs) but loses on `heterogeneous` (median
  and IQR) and on `ws_100` (2.60 vs 2.45 ms) and showed the worse
  tail (54 ms outlier); allocation is equal for 4 and 8 (worker-scaled
  construction), so load balance decides: keep the finer chunk.
  Chunks 16/32 are rejected (32: 9.81 vs 9.18 ms on `ws_500`, 4.82 vs
  2.45 ms on `ws_100`, 75 ms tail).
- **`HOUSEHOLD_BARGAIN_SERIAL_CUTOFF = 8`** (replacing the provisional
  64). Serial and parallel tie through 8 households (30-rep medians
  0.822 vs 0.824 ms at N = 8), parallel wins from N = 10 (+5.5%) and
  decisively from N = 12 (+22% at 12, +30% at 16, +51% at 24, up to
  4.5x at 96+), serial wins at N <= 4 (task overhead). With the
  provisional 64, populations of 16-64 households lose 2.2-3.3x.
- **Keep the atomic chunk cursor; reject the shared work queue.**
  Criterion: kernel median on `ws_500` and `heterogeneous` at 8T in
  two interleaved rounds, tails not worse. Cursor 8.78/8.51 ms vs
  queue 9.80/10.09 ms (`ws_500`, +11.7%/+18.5% for the queue) and
  8.44/8.13 vs 8.71/8.80 ms (`heterogeneous`, +3.2%/+8.3%); the queue
  also allocates +2,741 objects/+119 KB per 20-tick pass. The cursor
  beats the baseline `Threads.@threads :greedy` (12.52/12.82 ms and
  12.38/12.70 ms) by 30-36% and the rejected queue variant still beats
  it by 21-31%. The queue variant's measured numbers are
  recorded in section 3 and its implementation exists only in the
  throwaway tree.
