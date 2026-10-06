# GenderNorms benchmark harness

Reproducible runtime comparison of the NetLogo reference model
(`gender_model_shocks_preferences.nlogox`) against the Julia port
(`GenderNorms`) on a matched configuration matrix. The measurement
methodology is recorded in
`registry/model/decisions/MDR-0011-benchmark-methodology.md`, the
harness structure in
`registry/code/decisions/ADR-0013-benchmark-harness.md`. The performance
report (`benchmark/report.md`) is written separately from
`results/summary.csv`.

## Prerequisites

- Julia 1.12 with the repository project (`julia --project=.`), single
  thread recommended (`JULIA_NUM_THREADS=1`); the driver warns when
  Julia runs with more than one thread.
- NetLogo 7.x headless (tested with 7.0.4) with Java on `PATH`; the
  driver uses `$NETLOGO_HOME/netlogo-headless.sh` (default
  `/opt/netlogo`).
- No new Julia packages: the driver uses the standard library only.

## Usage

```
julia --project=. benchmark/run_benchmarks.jl [--quick] [--only netlogo|julia] [--force] [--analyse] [--cold-start]
```

- no options: run the full 39-config matrix on both implementations.
- `--quick`: smoke subset (`pop_n50_t5`, `util_ces`) with fewer
  repetitions; quick results use the same file layout but different
  repetition counts, so a later full run redoes those configs
  automatically.
- `--only netlogo|julia`: run one side only.
- `--force`: redo configs whose raw output is already complete.
- `--analyse`: rebuild `netlogo_runs.csv`, `julia_runs.csv`,
  `netlogo_ticks.csv`, `julia_ticks.csv`, `summary.csv`, and the
  NetLogo rows of `cold_start.csv` from the raw files without running
  anything.
- `--cold-start`: measure "time to first result from a fresh process"
  for the base config `pop_n100_t20` (3 fresh Julia processes) into
  `cold_start.csv`, then exit (combine with `--analyse` to do both).

Runs are resumable: a config is skipped when its raw output files carry
the expected number of rows. Results are written under
`benchmark/results/` (created on demand).

## Threading speedup

`benchmark/threading_speedup.jl` measures the speedup from the
multithreaded tick loops (`calculate_norm_perception!` and `set_theta!`,
see `ADR-0014`). It is separate from the NetLogo-vs-Julia comparison of
`MDR-0011` / `ADR-0013`, which stays single-threaded
(`JULIA_NUM_THREADS=1`).

```
JULIA_NUM_THREADS=N julia --project=. benchmark/threading_speedup.jl [agents_per_gender] [ticks]
```

- `agents_per_gender` defaults to 100, `ticks` defaults to 10.
- Output: elapsed seconds, ticks/s, and the thread count.
- To read the speedup, compare a `-t 1` (or unset
  `JULIA_NUM_THREADS`) run against a `-t N` run on the same arguments;
  the ratio of ticks/s is the threading speedup.

## Bargaining kernel benchmark

`benchmark/bargaining_kernel.jl` benchmarks the household bargaining
kernel `set_theta!` (`src/systems/household_bargaining.jl`, port of
NetLogo `set-theta` and `calculate-payoff`, ODD section Transfer
bargaining) in isolation: per repetition it builds one fresh world from
the same specification and seed (identical initial states across
repetitions) and drives the ticks manually in the exact `step_model!`
order of `MDR-0010`, timing only the `set_theta!` calls with `time_ns()`
and taking `Base.gc_num()` deltas around exactly those calls. It is a
kernel comparison basis for `set_theta!` optimizations, separate from
the NetLogo-vs-Julia comparison of `MDR-0011` / `ADR-0013` and from the
threading speedup of `ADR-0014`.

```
JULIA_NUM_THREADS=1 julia --project=. benchmark/bargaining_kernel.jl [workloads] [ticks] [repetitions]
```

- `workloads` is a comma-separated list of workload names or `all`
  (default `all`); `ticks` defaults to 20, `repetitions` to 15. Run one
  thread count at a time and do not run other heavy jobs while timing.
- Workloads (all seed 1, CES utility with `beta` 0.5; the population
  column is `agents_per_gender`, so households per tick is the same
  number): `ws_500` (REPRESENTATIVE: `watts_strogatz`
  `neighbors_per_side` 2, `rewiring` 0.1, 500), `ws_100` (same at 100),
  `homogeneous_mixing` (500), `no_network` (`none`, 500), `homophily`
  (`homophily` with `m` 2, 500), `heterogeneous` (the `ws_500` network
  and population plus `mean_wage` 2.0/0.5 men/women and
  `initial_conformism` 50.0/50.0, the high-conformism end of the config
  matrix below, so households differ strongly).
- Warmup per workload: one discarded tiny pass (2 agents per gender,
  1 tick) and one discarded full-size pass, so the report excludes all
  compilation and world construction. No GC is forced between
  repetitions (same policy as `MDR-0011`).
- Reported per workload (each number printed at full `repr` precision
  in the result block): the per-repetition `set_theta!` time summed over
  the ticks, summarized over repetitions as `median`, `min`, `max`, and
  `iqr` (the 75th minus the 25th percentile,
  `Statistics.quantile` linear interpolation) plus `mean`; the median
  total allocated bytes and allocation count of the timed `set_theta!`
  sections, per tick and per household per tick (households =
  `agents_per_gender`); the median `create_world` setup time; and the
  end-to-end `GenderNorms.run` time (median over repetitions, fresh
  world per repetition, reported separately and never mixed into the
  kernel numbers).
- Output ends with a machine-readable CSV table (a `csv` marker line,
  the header, one row per workload) with the same numbers for later
  report assembly; columns: `workload`, `threads`, `ticks`,
  `repetitions`, `households`, `kernel_median_s`, `kernel_iqr_s`,
  `kernel_min_s`, `kernel_max_s`, `kernel_mean_s`, `alloc_bytes`,
  `alloc_count`, `alloc_bytes_per_tick`, `alloc_count_per_tick`,
  `alloc_bytes_per_household_tick`, `alloc_count_per_household_tick`,
  `setup_median_s`, `e2e_median_s`.
- `benchmark/bargaining_kernel_report.md` assembles the A/B evidence
  for the behavior-preserving bargaining kernel optimization of
  `ADR-0015` (baseline commit vs final tree, both thread counts): the
  before/after runtime, allocation, and evaluation-count tables, the
  equivalence results, the exactness argument of the certified `-Inf`
  transfer-objective certificate, and the deviations.

## Current implementation profiling

`benchmark/profile_current.jl` profiles the current Julia implementation
without modifying or instrumenting package code. It uses the seed-1
workloads of `bargaining_kernel.jl`, production local transfer search,
and the current `MDR-0022` tick order. The findings from the 2026-10-06
run are in `benchmark/current_performance.md`; older optimization reports
are historical baselines, not measurements of current HEAD.

```sh
JULIA_NUM_THREADS=1 julia --startup-file=no --project=. benchmark/profile_current.jl /tmp/opencode/gn-profile-1t all ws_500,heterogeneous 15 6
JULIA_NUM_THREADS=8 julia --startup-file=no --project=. benchmark/profile_current.jl /tmp/opencode/gn-profile-8t timings ws_500,ws_2000,ws_4000 15
```

Positional arguments: output directory (default
`/tmp/opencode/gendernorms-current-profile`), section
(`timings|cpu|allocs|all`, default `all`), comma-separated workloads,
measured repetitions (default 15), and CPU-profile seconds per workload
(default 5). CPU/allocation sections require one worker thread; timings
support any thread count. Run measurements sequentially without other
heavy jobs. No dependencies are added.

Additional workloads: `ws_<N>` for population scaling and `additive`,
`multiplicative`, `multiplicative_weighted`, and `ces_0.3` for utility
comparisons at 500 households. All keep package-default parameters;
these are not NetLogo-matched runs of `run_benchmarks.jl`.

Outputs: raw/summary per-system timing and GC-counter CSVs, warmed CPU
flat/tree reports, inclusive function and leaf-location sample CSVs,
and full-rate allocation source/type totals with example stacks.
Setup is excluded from tick measurements and CPU sample CSVs. Inclusive
CPU percentages overlap; do not sum them. Instrumented execution times
are not performance baselines. Allocation-profiler object sizes omit
some GC bookkeeping; use the timing CSVs for total allocated bytes.

## Transfer search validation

`benchmark/transfer_search_validation.md` is the validation package for
the staged transfer search of `MDR-0012` (`TASK-0014`): finer-grid
solution-quality comparison, labour-tolerance artifact assessment,
multi-tick old-versus-new trajectories against the frozen reference
search, a matched-state NetLogo comparison of the transfer stage (ODD
section Transfer bargaining), and the measured search cost. Its data
tables live in `benchmark/transfer_validation/` (per section: fine-grid
results, tolerance sweeps, per-tick and per-household trajectory CSVs,
and the NetLogo probe tables); the throwaway driver scripts are
recorded with their `/tmp/opencode/` paths at the top of the report.

The staged performance recovery on top of it has one validation
report per stage: `benchmark/solver_equivalence_validation.md`
(Stage 2, `TASK-0019`, `MDR-0013`) records the same-state
solver-arithmetic equivalence protocol and its deltas, and
`benchmark/search_reduction_validation.md` (Stage 3, `TASK-0018`,
`MDR-0014`) records the fine-grid quality on three workloads, the
same-state and trajectory comparison against the frozen `MDR-0013`
reference search, the constructed adversarial band table of the
documented discovery guarantee, and the kernel metrics with the
remaining cost anatomy (tables `benchmark/transfer_validation/st2_*.csv`
and `st3_*.csv`).

Production now defaults to the bounded anchor-local search of `MDR-0015`
(`ADR-0020`): at most 216 distinct objective records including the status
seed, with no full-domain scan or global discovery guarantee. The prior
tiered discovery solver is retained explicitly through
`bargain_transfer(...; search=:discovery)` and
`set_theta!(world, config; search=:discovery)` for offline validation.
No TOML configuration change is needed to use the production default.

`benchmark/anchor_local_validation.jl` reproduces identical-state quality
against discovery and a finer grid (44 households x states 0/1/5 on three
workloads), 25-tick trajectory deltas, and sequential warmed kernel timings:

```sh
JULIA_NUM_THREADS=1 julia --project=. benchmark/anchor_local_validation.jl /tmp/opencode/anchor-validation quality
JULIA_NUM_THREADS=1 julia --project=. benchmark/anchor_local_validation.jl /tmp/opencode/anchor-validation trajectories
JULIA_NUM_THREADS=1 julia --project=. benchmark/anchor_local_validation.jl /tmp/opencode/anchor-validation timing
```

Run timings without concurrent heavy jobs. The default section is `all`;
the default output directory is `/tmp/opencode/anchor-local-validation`.
`benchmark/anchor_local_validation.md` records the evidence, including
solution losses rather than an equivalence claim. Its tables live in
`benchmark/transfer_validation/anchor_*.csv`.

## Results layout

- `results/experiments/<config_id>.xml` - generated BehaviorSpace
  setup file (one experiment per config).
- `results/experiments/cold_start_pop_n100_t20.toml` - run
  specification used by the cold-start probe.
- `results/netlogo/<config_id>.csv` - raw BehaviorSpace table: the
  per-step series (`[step]` 0..ticks, metrics `timer` and `run-time`)
  of every repetition.
- `results/netlogo/invocations.csv` - NetLogo process wall time per
  invocation (one invocation per config).
- `results/julia/<config_id>.csv` - per-repetition Julia rows
  (`rep,setup_s,steps_s,total_s`).
- `results/julia/<config_id>_ticks.csv` - per-call Julia rows
  (`rep,tick,seconds`, tick 0-based like `step_model!`).
- `results/netlogo_runs.csv`, `results/julia_runs.csv` - flattened
  merged tables, one row per measured repetition, including the config
  parameters (the NetLogo table also carries `timer_drift_s`, the
  `run-time` minus `timer` final-step consistency check).
- `results/netlogo_ticks.csv`, `results/julia_ticks.csv` - flattened
  per-tick series with config parameters (NetLogo tick `k` is the
  `k`-th `go` call, `k = 1..ticks`; Julia tick `j` is the `(j+1)`-th
  `step_model!` call, `j = 0..ticks-1`), for per-tick curve plots.
- `results/summary.csv` - one row per config and implementation:
  median/mean/min/max total seconds, median setup, per-tick, first-tick
  and last-tick seconds, repetition counts, and
  `speedup_netlogo_over_julia` (ratio of median totals). A report can
  be built from this file alone.
- `results/cold_start.csv` - `impl,detail,seconds`: one `julia` row per
  cold-start process (full process wall incl. first run of the base
  config) and one `netlogo` row per invocation (process wall minus the
  summed in-model `timer` series, approximating JVM startup + model
  load).
- `results/environment.txt` - CPU, cores, RAM, OS, `julia -v`, NetLogo
  version, `java -version` at the time of the run.

## Methodology (summary; details in `MDR-0011`)

NetLogo side, per config: one BehaviorSpace experiment run as one
headless invocation with `--threads 1`, `repetitions = 9` (quick: 3),
`runMetricsEveryStep = "true"` (so every run emits one row per step
including `[step] == 0`), and `timeLimit = <ticks>` (exactly `ticks`
`go` calls). The metrics are `timer` and `run-time` (both trivial
global reads; `[step]` already gives the tick count). `timer` runs from
`reset-timer` at the start of `setup`, so one run decomposes internally
consistently from its own rows: `setup_s = timer[0]`,
`tick_s[k] = timer[k] - timer[k-1]` for `k = 1..ticks`,
`total_s = timer[ticks]`. `run-time` at the final step must equal
`timer[ticks]`; a config disagreeing by more than the timer resolution
(2 ms) is flagged during analysis. Row `[run number] == 1` is dropped
as JIT warmup (it is visibly slower); runs 2..9 are the 8 measured
repetitions. The process wall time per invocation is recorded
separately.

Julia side, per config: a validated run specification (`seed = 42`, no
`[logging]` table), then `create_world(spec)` (port of `setup`) and the
`step_model!` loop for `tick in 0:(ticks-1)` (port of `go`, see
`MDR-0010`), each timed with `time_ns()`; every `step_model!` call is
additionally timed into `<id>_ticks.csv`. Two warmup runs are
discarded, then 8 (quick: 2) timed repetitions; no GC is forced between
repetitions, mirroring BehaviorSpace repetitions inside one JVM.

Seeds differ by implementation (NetLogo `random-seed-fixed = 1`, Julia
42) and the RNG streams are different, so trajectories are not
bit-identical; the configurations are matched, not the trajectories.

Cold start: `--cold-start` spawns 3 fresh Julia processes (with
`--project`) that run `parse_spec` + `create_world` + the step loop for
the base config `pop_n100_t20` and records each process wall time; the
NetLogo side is derived per invocation from `invocations.csv` wall
minus the summed in-model `timer` series.

## Config matrix (single source of truth: `config_matrix()` in the driver)

Base configuration: 100 agents per gender, 20 ticks, `watts_strogatz`
network, `ces` utility, conformism 10/10.

| Group | Swept knobs | Configs |
| --- | --- | --- |
| `pop` | agents_per_gender in 25, 50, 100, 200, 400, 800 x ticks in 1, 5, 20, 50 | 24 (`pop_n25_t1`, ...) |
| `net` | network in none, watts_strogatz, random, preferential_attachment, similarity, homophily, homogeneous_mixing | 7 (`net_none`, ...) |
| `util` | utility in additive, ces, multiplicative, multiplicative_weighted | 4 (`util_ces`, ...) |
| `conf` | initial_conformism (men = women) in 0, 1, 10, 50 | 4 (`conf_0`, ...) |

## Configuration mapping (both sides run identical configurations)

| NetLogo global | Julia run-spec key | Value |
| --- | --- | --- |
| `number-agents-each-type` | `agents_per_gender` | swept (25-800) |
| `network-structure` | `network.type` | swept; names below |
| `random-network-prob` | `network.p` (random) | 0.01 |
| `watts-strogatz-neighbors` | `network.neighbors_per_side` (watts_strogatz) | 2 on both sides (equivalence below) |
| `watts-strogatz-rewiring` | `network.rewiring` | 0.1 |
| `preferential-attachment-min-degree` | `network.m` (preferential_attachment, similarity, homophily) | 2 |
| `utility-function` | `utility.type` | swept; names below |
| `CES_beta` | `utility.beta` (ces) | 0.5 |
| `weight-working-time-self` | `utility.w_self` | 1 |
| `weight-working-time-partner` | `utility.w_partner` | 1 |
| `weight-transfer` | `utility.w_transfer` | 1 |
| `conformism-male` / `conformism-female` | `initial_conformism.men` / `.women` | swept (10 base) |
| `wage-male` / `wage-female` | `mean_wage.men` / `.women` | 1.0 / 0.9 |
| `norm-paid-time-male` / `norm-paid-time-female` | `paid_time.men` / `.women` | 77 / 36 <-> 0.77 / 0.36 (NetLogo `set-initials-*` divides by 100) |
| `preference-private-mean-male` / `-female` | `mean_preference.men` / `.women` | 0.45 / 0.48 |
| `std-dev-values` | `std_dev` | 0.2 |
| `initial-transfer` | `initial_transfer` | 0.0 |
| `lambda` | `initial_lambda` | 0.002 on both sides (the Julia default 0.5 diverges, see `registry/model/discrepancies.md`) |
| `convergence_epsilon` | (solver tolerance, see `MDR-0002`) | 0.001, set explicitly (the widget default lies outside its own slider range) |
| `fixed-rs` / `random-seed-fixed` | `[run] seed` | true / 1 vs 42 |
| `shock` | (no shock resources configured) | `"no"` |
| `perc-affected-male` / `perc-affected-female` | (`select_affected!` not called in Julia setup, `TASK-0007`) | 0 / 0 |
| `shock-start`, `wage-growth-rate`, `preference-private-shock-*`, `shock-depreciation` | (none) | shock machinery off: 60, 0, 0/0, 0.005 |
| `import-csv`, `specific-couple`, `output-locations` | (none) | false |
| `*-in-question` (6 probe globals) | (unwired `ProbeCouple`, `TASK-0006`) | widget defaults; never read while `specific-couple` is false |

Network names: `none`<->none, `watts-strogatz`<->watts_strogatz,
`random-network`<->random, `preferential-attachment`<->preferential_attachment,
`preference-private`<->similarity with trait `preference_private`,
`homophily`<->homophily, `homogenous mixing`<->homogeneous_mixing.
Utility names: `additive`<->additive, `CES`<->ces,
`multiplicative`<->multiplicative,
`multiplicative including weights`<->multiplicative_weighted.

Watts-Strogatz equivalence: NetLogo `nw:generate-watts-strogatz` (called
from `setup`) treats `watts-strogatz-neighbors` as the neighborhood size
on each side; Julia maps `neighbors_per_side` to the
`Graphs.watts_strogatz` ring degree `k = 2 * neighbors_per_side`
(`src/resources/social_network.jl`). Both give each node `v` neighbors
per side (degree `2v`; measured in both implementations at rewiring 0),
so the equivalence is 1:1 and the benchmark uses 2 on both sides, the
value of the model's shipped BehaviorSpace experiments. See `MDR-0011`.

## Comparability caveats

Measured speed ratios reflect algorithmic differences as well as
language/runtime differences; see `MDR-0011` for the full list: the
Julia statistics core is a partial `update-statistics` port (histories
and observer statistics missing, `TASK-0001`), NetLogo recomputes norm
perceptions inside every `calculate-utility` call while Julia computes
them once per agent per tick (`MDR-0004`), and the bargaining solvers
differ (NetLogo discrete search vs continuous Brent maximization,
`MDR-0002`, `MDR-0005`). The NetLogo timed scope additionally includes
BehaviorSpace's per-step evaluation of the two trivial metric reporters
(`timer`, `run-time`), a small constant per-tick overhead that can only
make NetLogo look slightly slower.

## Regeneration note

The first full run used a paired two-invocation split
(`<id>` + `<id>_steps` with `setup  reset-timer`) for the NetLogo
setup/step decomposition; it was rejected after transient machine
interference produced impossible values (negative setup times, go-loop
times exceeding the combined total). `benchmark/results/` was wiped and
regenerated with the single-invocation per-step `timer` method
(`MDR-0011`); the current contents are from a `--quick` smoke run. Wipe
`benchmark/results/` again before the full-matrix run so nothing stale
remains (the completeness check would redo the quick configs anyway).
