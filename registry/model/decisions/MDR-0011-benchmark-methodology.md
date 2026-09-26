---
id: MDR-0011
title: Benchmark comparison methodology
status: accepted
date: 2026-09-26
supersedes: ""
superseded_by: ""
---

# MDR-0011: Benchmark comparison methodology

## Context

The benchmark harness (`benchmark/`, see `ADR-0013`) compares the
runtime speed of the NetLogo reference implementation
(`gender_model_shocks_preferences.nlogox`) and of the Julia port on
matched configurations. The ODD does not specify performance, so the
measurement scope on both sides and the mapping between NetLogo
interface globals and Julia run-specification keys
(`src/runtime/gender_norms_model.jl`, `examples/example_run.toml`) must
be fixed before collecting numbers.

The model already carries its own timing hook: `setup` calls
`reset-timer` at its start and `go` ends with `set run-time timer` (ODD
section Statistics; ODD section Process overview and scheduling), so
the global `run-time` is the in-model wall-clock time of `setup` plus
all `go` calls of one run, with JVM startup and model loading excluded
automatically. On the Julia side the run pipeline (`ADR-0012`)
separates `create_world(spec)` (port of NetLogo `setup`, ODD section
Initialization) from the `step_model!` loop (port of `to go`, see
`MDR-0010`), which makes the same scope measurable piecewise.

Both sides must execute identical configurations. NetLogo widget
defaults are not trustworthy (`convergence_epsilon`'s default 0.001
lies outside its own slider range 0-0.0001), and the Julia `initial_lambda`
default 0.5 diverges from the NetLogo `lambda` slider default 0.002
(see `registry/model/discrepancies.md`), so every global is set
explicitly on both sides.

## Decision

1. NetLogo scope: one BehaviorSpace setup file per config with one
   experiment, run as one headless invocation
   (`netlogo-headless.sh --threads 1`, `runMetricsEveryStep="true"`,
   `timeLimit=<ticks>`, so exactly `ticks` `go` calls and one table row
   per step including `[step] == 0`), with the metrics `timer` and
   `run-time` (both trivial global reads; the `[step]` column already
   gives the tick count). `timer` runs from `reset-timer` at the start
   of `setup`, so one run decomposes from its own rows within a single
   invocation: `setup_s = timer[0]` (timer after setup),
   `tick_s[k] = timer[k] - timer[k-1]` for `k = 1..ticks`, and
   `total_s = timer[ticks]`. The decomposition is internally
   consistent (`setup_s >= 0`, tick differences telescope to the
   total) and immune to cross-invocation interference. `run-time` at
   the final step must equal `timer[ticks]`; a config disagreeing by
   more than the timer resolution (2 ms) is flagged during analysis.
   The process wall time of the invocation is recorded separately
   (`results/netlogo/invocations.csv`); wall minus the summed in-model
   `timer` series approximates JVM startup + model load and feeds the
   cold-start comparison (`results/cold_start.csv`, one row per
   invocation).
2. Julia scope: `time_ns()` around `GenderNorms.create_world(spec)`
   (setup) and around the `step_model!` loop for
   `tick in 0:(ticks - 1)` (steps; the first call sees tick 0, see
   `MDR-0010` and `examples/run_example.jl`). The run specification has
   `[run]` (`seed = 42`), `[model]`, and `[runtime]` tables and no
   `[logging]` table, so the timed scope is the core loop exactly:
   no per-tick metrics, no TOML logging. This matches the NetLogo
   `go`-loop scope (the per-step BehaviorSpace metrics of item 1 are
   trivial global reads; their evaluation overhead is inside the
   NetLogo timer, see Consequences).
3. Matched-configuration mapping (every global set explicitly on both
   sides):

   | NetLogo global | Julia run-spec key | Benchmark value |
   | --- | --- | --- |
   | `number-agents-each-type` | `agents_per_gender` | swept 25-800 |
   | `network-structure` | `network.type` | swept (names below) |
   | `random-network-prob` | `network.p` (random) | 0.01 |
   | `watts-strogatz-neighbors` | `network.neighbors_per_side` (watts_strogatz) | 2 on both sides (equivalence below) |
   | `watts-strogatz-rewiring` | `network.rewiring` | 0.1 |
   | `preferential-attachment-min-degree` | `network.m` (preferential_attachment, similarity, homophily) | 2 (NetLogo `generate-network` / `generate-homophilic-network` use it too) |
   | `utility-function` | `utility.type` | swept (names below) |
   | `CES_beta` | `utility.beta` (ces) | 0.5 |
   | `weight-working-time-self` | `utility.w_self` | 1 |
   | `weight-working-time-partner` | `utility.w_partner` | 1 |
   | `weight-transfer` | `utility.w_transfer` | 1 |
   | `conformism-male` / `conformism-female` | `initial_conformism.men` / `.women` | swept 0/1/10/50 (base 10) |
   | `wage-male` / `wage-female` | `mean_wage.men` / `.women` | 1.0 / 0.9 |
   | `norm-paid-time-male` / `norm-paid-time-female` | `paid_time.men` / `.women` | 77 / 36 <-> 0.77 / 0.36 (NetLogo `set-initials-men`/`-women` divide by 100; Julia uses fractions) |
   | `preference-private-mean-male` / `-female` | `mean_preference.men` / `.women` | 0.45 / 0.48 (see `MDR-0006`) |
   | `std-dev-values` | `std_dev` | 0.2 |
   | `initial-transfer` | `initial_transfer` | 0.0 |
   | `lambda` | `initial_lambda` | 0.002 on both sides, set explicitly (the Julia default 0.5 diverges from the NetLogo slider) |
   | `convergence_epsilon` | no key (solver tolerance, see `MDR-0002`) | 0.001, set explicitly |
   | `fixed-rs` / `random-seed-fixed` | `[run] seed` | `true` / 1 vs 42 |
   | `shock` | (no shock resources added to the world) | `"no"` |
   | `perc-affected-male` / `perc-affected-female` | (none; `select_affected!` is not called in Julia setup, see `TASK-0007`) | 0 / 0 so the NetLogo `setup` work matches the Julia setup work |
   | `shock-start` | (none) | 60 (never reached at <= 50 ticks) |
   | `wage-growth-rate` | (none) | 0 (shock machinery off) |
   | `preference-private-shock-male` / `-female` | (none) | 0 / 0 (shock machinery off) |
   | `shock-depreciation` | (none) | 0.005 (irrelevant while `shock = "no"`) |
   | `import-csv`, `specific-couple`, `output-locations` | (none) | false |
   | `*-in-question` (6 probe globals) | (unwired `ProbeCouple`, see `TASK-0006`) | widget defaults; never read while `specific-couple` is false |

   Network names: `none` <-> `none`, `watts-strogatz` <->
   `watts_strogatz`, `random-network` <-> `random`,
   `preferential-attachment` <-> `preferential_attachment`,
   `preference-private` <-> `similarity` with trait
   `preference_private`, `homophily` <-> `homophily`, `homogenous
   mixing` <-> `homogeneous_mixing`. Utility names: `additive` <->
   `additive`, `CES` <-> `ces`, `multiplicative` <->
   `multiplicative`, `multiplicative including weights` <->
   `multiplicative_weighted`.
4. Watts-Strogatz neighbor equivalence: NetLogo `setup` calls
   `nw:generate-watts-strogatz men/women links
   number-agents-each-type watts-strogatz-neighbors
   watts-strogatz-rewiring`, where `watts-strogatz-neighbors` is the
   neighborhood size on each side (measured in the reference model at
   rewiring 0: value 2 gives mean degree 4). Julia maps
   `neighbors_per_side` `v` to the `Graphs.watts_strogatz` ring degree
   `k = 2v` in `src/resources/social_network.jl` (`_watts_strogatz_k`),
   so `v` gives degree `2v` as well (measured: `v = 2` gives mean
   degree 4). The equivalence is therefore 1:1 (`v` <-> `v`), and the
   benchmark sets 2 on both sides (degree-4 rings, the value used by
   the model's shipped BehaviorSpace experiments). Note this corrects
   the pairing `watts-strogatz-neighbors = 2` <-> `neighbors_per_side =
   1`, which would run degree-4 rings on NetLogo and degree-2 rings in
   Julia; the earlier pairing assumed `Graphs.watts_strogatz` counts
   `k` neighbors per side, but `k` is the total ring degree.
5. Seeds and repetitions: NetLogo runs `repetitions = 9` per experiment
   with `sequentialRunOrder="true"` and `fixed-rs = true`,
   `random-seed-fixed = 1`, so every repetition re-seeds and executes
   identical work; the row `[run number] == 1` is dropped (JIT warmup;
   it is visibly slower) and runs 2-9 are the 8 measured repetitions.
   Julia runs `seed = 42`, 2 discarded warmup runs, then 8 timed
   repetitions. Quick smoke runs use 3 NetLogo repetitions (2 measured)
   and 2 measured Julia repetitions. No GC is forced between
   repetitions on either side (BehaviorSpace repetitions run inside one
   JVM without forced GC). Both sides record their per-tick series (the
   NetLogo `timer` differences and the per-call `step_model!` timings,
   flattened to `results/netlogo_ticks.csv` / `results/julia_ticks.csv`)
   because per-tick cost declines as the model converges and the report
   discusses it. The RNG streams differ (NetLogo `random-seed` vs
   `Random.MersenneTwister(42)` in `create_world`), so trajectories are
   not bit-identical across sides; the configurations are matched, not
   the trajectories. Julia must run single-threaded (the driver warns
   when `Threads.nthreads() != 1`); NetLogo runs with `--threads 1`.
   Cold start is measured as "time to first result from a fresh
   process" for the base config `pop_n100_t20`: 3 fresh Julia
   processes running `parse_spec` + `create_world` + the step loop
   (full process wall per process) and, per NetLogo invocation, wall
   minus the summed in-model `timer` series, merged in
   `results/cold_start.csv`.

## Consequences

- The measured speedup ratios reflect algorithmic differences as well
  as language/runtime differences and are not pure language
  benchmarks. In particular:
  - The Julia port is partial: NetLogo `update-statistics` computes
    10-element histories, moving averages, `global-mean-transfer`
    storage, and the observer-set statistics (shock propagation,
    household employment types), which the Julia statistics core does
    not (see `TASK-0001` and `MDR-0007`); NetLogo does strictly more
    work per tick inside the timed `go` scope.
  - NetLogo recomputes norm perceptions (`mean [old-working-time] of
    [link-neighbors]`, and the spouses-of-neighbors means) inside every
    `calculate-utility` call of `set-theta`/`choose-bundle`, while
    Julia computes them once per agent per tick in
    `calculate_norm_perception!` (see `MDR-0004`).
  - The bargaining solvers differ: NetLogo searches a discrete theta
    grid in `set-theta` and hill-climbs in `choose-bundle` with step
    `current-delta` and stop tolerance `convergence_epsilon`, while
    Julia solves continuous best responses with the in-repo Brent
    maximizer (see `MDR-0002` and `MDR-0005`).
- The benchmark covers the no-shock path only: `shock = "no"`, and the
  NetLogo `perc-affected-*` draws are set to 0 to match the Julia
  `setup`, which does not call `select_affected!` (`TASK-0007`). A
  shock-scoped comparison needs that wiring first.
- The NetLogo timed scope includes BehaviorSpace's per-step evaluation
  of the two trivial metric reporters (`timer`, `run-time`), which the
  earlier metric-at-final-step-only variant excluded. This is a small
  constant overhead per tick in the conservative direction: it can only
  make NetLogo look slightly slower. The NetLogo `timer` has
  millisecond resolution, so per-step differences are quantized; use
  medians over the 8 measured repetitions.
- The first full run used a paired two-invocation split (experiment
  `<id>` with `setup` measuring setup + go, experiment `<id>_steps`
  with the compound setup command `setup  reset-timer` measuring the go
  loop alone, `setup_s = total_s - steps_s` per paired repetition). It
  was rejected after transient machine interference hit whole `_steps`
  invocations and produced physically impossible values (negative
  `netlogo_median_setup_s`, go-loop times exceeding the combined
  setup + go total), making every derived column untrustworthy. The
  benchmark results were regenerated with the single-invocation
  per-step `timer` method of item 1; the stale `<id>_steps.csv` files
  and the old `results/` contents were deleted.
- `benchmark/results/summary.csv` carries the per-config statistics
  (including median first-tick and last-tick seconds, since per-tick
  cost declines as the model converges) and the speedup ratio; the
  performance report is written from it separately (see `ADR-0013` and
  `TASK-0012`).
