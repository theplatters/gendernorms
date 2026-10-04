---
id: ADR-0025
title: Interactive Genie dashboard outside the core package
status: accepted
date: 2026-10-04
supersedes: ""
superseded_by: ""
---

# ADR-0025: Interactive Genie dashboard outside the core package

## Context

Runs of the model produce per-tick metric paths that need to be
visualized and compared across adaptable configurations, including live
animation of runs launched from the UI. The run pipeline exposes a
`RunLogger` seam (`run_started!` / `metrics_recorded!` /
`run_finished!`) and monolithic one-run-per-world execution per
`ADR-0012`. Tooling such as `benchmark/` and `examples/` lives outside
`src/` per `ADR-0013`. Two constraints govern the design: `Ark.World`
is not safe to read concurrently with stepping, and the threaded
kernels (`set_theta!`, `calculate_norm_perception!` per `ADR-0023` /
`ADR-0024`) must not be disturbed by dashboard reads or scheduling
changes.

## Decision

1. The dashboard lives in a separate top-level `dashboard/` Julia
   project with its own dependency environment (Genie, Stipple,
   StipplePlotly). It depends on GenderNorms by path and uses only the
   public run API (`load_spec`, `parse_spec`, `spec_to_dict`,
   `create_world`, `add_logger!`, `GenderNorms.run`, `is_success`).
   Core `src/`, root `Project.toml`, and root `Manifest.toml` are
   untouched.
2. Live runs execute in one isolated Julia worker process per run
   behind a FIFO queue (default `--threads=N,1`): one run executes at a
   time, with no pause/resume. Adaptable run specs are built as dicts
   and parsed via `GenderNorms.parse_spec`.
3. A dashboard-side `RunLogger` subtype publishes per-tick metric rows
   into a preallocated buffer with an atomic published-row counter, so
   the model loop never blocks on I/O and no other task touches the
   world while it steps. A stream writer forwards batches over
   versioned JSONL worker-server IPC to the server, which animates the
   metric paths in real time.
4. Recorded runs are read from `runs/*/run.toml`. Recorded and live
   runs share one dashboard-side path representation. Dashboard-recorded
   runs are written via the existing `GN.TomlLogger` into
   `runs/.dashboard-staging/<job-uuid>/<run-uuid>/` and atomically
   promoted to `runs/<run-uuid>/` after clean completion.
5. Plots are Stipple/Plotly (PlotlyBase plots): one Plotly panel per
   metric, one trace per run, throttled full react updates (at most
   every 100 ms) with a presentation cursor revealing buffered rows
   over time; display-only downsampling above a point budget.
6. Extends `ADR-0012` (run pipeline and logging seam) and follows
   `ADR-0013` (external tooling outside `src/`); cites `ADR-0023` and
   `ADR-0024` for the scheduler constraints. This record supersedes
   nothing. No `registry/code/architecture.md` file-map entry is added
   because no file under `src/` changes. No model semantics change, no
   new metrics, and no MDR is needed.

## Consequences

- Zero unconditional overhead on core runs and benchmarks: the core is
  untouched by construction. Dashboard runs pay the optional logger
  cost plus worker startup and JIT latency.
- One executing run at a time and no pause/resume; the FIFO queue
  orders concurrent launch requests.
- Benchmark measurements must be taken with dashboard workers stopped
  because of CPU contention.
- Dependency compatibility of the Stipple stack (Genie, Stipple,
  StipplePlotly) on Julia 1.12 is qualified before the UI is built.
- Dashboard tests live in `dashboard/test/` and are not part of the
  core suite. Implementation and qualification work is tracked as
  `TASK-0028`; `TASK-0011` (sweeps, Monte Carlo runners, extra logging
  backends, JSON/YAML parsers) stays open.
