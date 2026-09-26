---
id: ADR-0013
title: Benchmark Harness
status: accepted
date: 2026-09-26
supersedes: ""
superseded_by: ""
---

# ADR-0013: Benchmark Harness

## Context

The runtime speed of the NetLogo reference model
(`gender_model_shocks_preferences.nlogox`) and of the Julia port must be
compared on matched configurations. The measurement methodology is
model-side and recorded in `MDR-0011`; this record covers where the
tooling lives and how it is organized. Precedent: `scripts/`,
`examples/`, and `test/` are developer tooling outside the `src/`
module - they are not included in `src/GenderNorms.jl` and not listed in
the `registry/code/architecture.md` file map (whose coverage rules are
defined for `src/`). The benchmark harness shells out to NetLogo,
generates BehaviorSpace experiment XML, and manages result files; none
of that belongs in the package.

## Decision

1. Benchmark tooling lives in `benchmark/` outside the package, like
   `scripts/` and `examples/`: `benchmark/run_benchmarks.jl` (the
   driver), `benchmark/README.md` (usage, layout, methodology summary),
   and `benchmark/results/` (generated artifacts). No file under
   `benchmark/` is included in `src/GenderNorms.jl` or registered in
   `registry/code/architecture.md`. The driver uses only the Julia
   standard library (`Printf`, `Statistics`, `Dates`); no new `Project.toml`
   dependency.
2. The driver is the single source of truth for the benchmark config
   matrix (39 configs in the groups `pop`, `net`, `util`, `conf`) and
   for the NetLogo-global-to-Julia-run-spec mapping (the full table in
   `MDR-0011` and `benchmark/README.md`). Both implementation sides are
   generated from one `BenchConfig` per config, so they cannot drift
   apart.
3. Results layout under `benchmark/results/`: raw per-config outputs
   (the NetLogo per-step series `netlogo/<id>.csv`, the Julia
   per-repetition rows `julia/<id>.csv`, and the Julia per-call series
   `julia/<id>_ticks.csv`), the per-invocation NetLogo wall times
   (`netlogo/invocations.csv`), the generated setup files
   (`experiments/<id>.xml` and the cold-start probe specification
   `experiments/cold_start_<id>.toml`), the flattened merged tables
   (`netlogo_runs.csv`, `julia_runs.csv` for per-repetition rows,
   `netlogo_ticks.csv`, `julia_ticks.csv` for per-tick series), the
   per-config summary (`summary.csv`, sufficient to build the report
   alone), the cold-start measurements (`cold_start.csv`, one `julia`
   row per probe process and one `netlogo` row per invocation:
   wall minus the summed in-model `timer` series), and
   `environment.txt` (CPU, cores, RAM, OS, `julia -v`, NetLogo version,
   `java -version`).
4. Resumability: a config is skipped when its raw output files carry the
   expected repetition count (a partial file is redone); `--force`
   reruns regardless; `--analyse` rebuilds the merged files from the
   raw outputs only. `--quick` runs a smoke subset with fewer
   repetitions into the same layout, so a later full run redoes those
   configs automatically through the completeness check.
5. The CLI is `julia --project=. benchmark/run_benchmarks.jl` with
   `--quick`, `--only netlogo|julia`, `--force`, `--analyse`,
   `--cold-start` (fresh-process startup measurement for the base
   config), and `--help`; the NetLogo installation comes from the
   `NETLOGO_HOME` environment variable (default `/opt/netlogo`).

## Consequences

- `benchmark/` is not covered by the package test suite and not subject
  to the `registry/code/architecture.md` registration rules, but the
  cleanliness rules of `registry/code/conventions.md` (ASCII, no tabs,
  no trailing whitespace, docstrings, no dead code) apply to it by
  convention.
- `benchmark/report.md` is written by a later work package from
  `results/summary.csv` alone; the column contract of `summary.csv` is
  fixed by this decision and must not be narrowed without amending this
  record. The contract is one row per config with data: the config
  columns `config_id`, `group`, `agents_per_gender`, `ticks`,
  `network`, `utility`, `conformism`, then per implementation
  (`netlogo_` / `julia_` prefixes) `median_total_s`,
  `median_setup_s`, `median_per_tick_s`, `median_tick_first_s`,
  `median_tick_last_s`, `mean_total_s`, `min_total_s`, `max_total_s`,
  `n_reps`, and finally `speedup_netlogo_over_julia` (ratio of median
  totals). The `*_median_tick_first_s` / `*_median_tick_last_s` columns
  extend the original contract (per-tick cost declines as the model
  converges); the NetLogo setup/step decomposition is the per-step
  `timer` method of `MDR-0011`.
- The measurement semantics (what is timed, warmup/repetition policy,
  the matched-configuration mapping, and the comparability caveats) are
  recorded in `MDR-0011`; changes to them are model decisions, not
  structural ones.
- Future experiment infrastructure (`TASK-0011`: parameter sweeps and
  Monte Carlo runners on the run pipeline of `ADR-0012`) may absorb or
  supersede the config-matrix runner; until then `benchmark/` stays a
  standalone developer tool.

## References

- `registry/model/decisions/MDR-0011-benchmark-methodology.md`
- `registry/code/decisions/ADR-0012-run-execution-pipeline.md`
- `registry/tasks.md`
