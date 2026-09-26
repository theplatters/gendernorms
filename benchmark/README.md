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
