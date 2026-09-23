---
id: ADR-0012
title: Run Execution Pipeline
status: accepted
date: 2026-09-23
supersedes: ""
superseded_by: ""
---

# ADR-0012: Run Execution Pipeline

## Context

The package has ported model subsystems in `src/systems/` but offers no
way to initialize, execute, and observe a model run. `TASK-0010` tracks
wiring the model loop; running models manually and building future
experiment infrastructure (parameter sweeps, Monte Carlo) need a
standardized, reproducible run pipeline. The ODD section Process overview
and scheduling defines the tick order and the ODD section Initialization
defines setup; Initialization item 2 covers the `fixed-rs` /
`random-seed-fixed` seeding path ("If `fixed-rs`, `random-seed
random-seed-fixed`").

The pipeline must satisfy five requirements: a serialized run
specification kept separate from mutable runtime state; validation that
reports useful errors; a `run(world)` entry point decoupled from one
specific model; an explicit lifecycle from specification through
initialization and execution to completion or failure; extensible
logging; and reproducibility given a seed.

## Decision

1. The run specification format is TOML, parsed with the `TOML` stdlib
   (plus the `Dates` and `UUIDs` stdlibs added to `Project.toml`). No
   third-party dependency is introduced. JSON or YAML can be added later
   as alternative parsers feeding the same `RunSpec` type; TOML is the
   recommended and currently only format.
2. A new layer `src/runtime/` is added above `src/systems/`, extending
   the layering of `ADR-0002` to `components -> resources -> systems ->
   runtime`. Files: `src/runtime/model_interface.jl`, `run_spec.jl`,
   `run_result.jl`, `logging.jl`, `run_context.jl`, `runner.jl`,
   `gender_norms_model.jl`, included in that order after the systems includes.
3. Model decoupling: the core defines `abstract type AbstractModel end`
   with six hooks dispatched on the model type -- `model_name`,
   `parse_model_config`, `setup_world`, `step_model!`, `model_metrics`,
   `config_to_dict` -- plus a `MODEL_REGISTRY` mapping the spec's
   `model.name` string to a model type via `resolve_model`. The pipeline
   core (`RunSpec`, `create_world`, `run`, `RunResult`, `RunLogger`) is
   model-agnostic. `GenderNormsModel` (in `gender_norms_model.jl`) is the
   binding for this package's model, registered as `"gender_norms"`.
4. Specification shape: `[run]` (`name`, required `seed`), `[model]`
   (required `name`, model-specific keys validated by
   `parse_model_config`), `[runtime]` (required `ticks`, the number of
   `go` calls), `[logging]` (optional `metrics` list, optional
   `[[logging.outputs]]` backends). Unknown keys are rejected everywhere.
   Validation aggregates all problems into one `RunSpecError` with
   per-path messages (e.g. `[model.agents_per_gender] ...`).
5. Lifecycle: `parse_spec`/`load_spec` produce an immutable `RunSpec`
   (throws `RunSpecError` on invalid input); `create_world(spec)` builds
   and initializes a world (throws on setup errors) and attaches a
   `RunContext` resource carrying the run id (a fresh `UUIDs.uuid4()`
   string), spec, model type, resolved config, metric functions, loggers,
   and the seeded RNG; `run(world)` executes `runtime.ticks` steps and
   returns a `RunResult` whose `status` is `RUN_SUCCESS` or `RUN_FAILURE`.
   Step or metric errors are caught and recorded in the result (`error`,
   `ticks_executed`); they are never reported as success.
   `InterruptException` is rethrown before finalization, so backends
   write no record for an interrupted run: an abort cannot masquerade
   as a completed run. Errors raised by logger hooks
   propagate to the caller. One run per world: a second `run` call on
   the same world throws `ArgumentError`; create a fresh world from
   the spec instead.
6. `run` is a module-local function `GenderNorms.run(world)` -- it is
   neither exported (which would clash with `Base.run` for downstream
   users) nor a method of `Base.run` (which would be type piracy on
   `Ark.World`).
7. Reproducibility: the spec's `seed` is required; `create_world` seeds
   `Random.MersenneTwister(seed)` and threads it explicitly through all
   stochastic setup code (replacing the previous implicit
   `Random.default_rng()` uses in `src/systems/initialisation.jl`). The
   RNG object lives in `RunContext` so future stochastic dynamics can
   draw from the same seeded stream. Two runs with identical
   specification and seed are identical wherever the model is
   deterministic given the seed. For pipeline runs this subsumes the
   `fixed-rs` / `random-seed-fixed` path of ODD Initialization item 2
   (see `TASK-0007`).
8. Logging: a sink interface `abstract type RunLogger end` with three
   hooks `run_started!(logger, info::RunInfo)`,
   `metrics_recorded!(logger, tick, values)`, and
   `run_finished!(logger, result::RunResult)` that default to no-ops, so
   backends implement only what they need and the core loop never changes
   when backends are added. `TomlLogger` writes
   `<directory>/<run-id>/run.toml` containing run id, name, model name,
   status, seed, start/end timestamps (ISO-8601 strings), ticks executed,
   error info on failure, an exact echo of the specification (via
   `spec_to_dict`, so the configuration and seed are recoverable from the
   record), and the per-tick metric series. New output backends add
   `validate_output_spec`/`build_logger` methods and a `LOG_OUTPUT_TYPES`
   entry. The runner itself collects the in-memory record (`RunResult`);
   loggers are sinks, so no separate in-memory logger is needed.
   `examples/run_example.jl` prints a short summary to stdout; this is
   the example's intended output, not stray debug output (the no-println
   rule of `registry/code/conventions.md` targets library code).
9. `src/main.jl` remains the empty standalone entry point; the runnable
   example lives in `examples/` (a spec TOML, a run script, and a README).

## Consequences

- Future parameter sweeps, Monte Carlo runners, database or CSV loggers,
  and JSON/YAML spec parsers plug in through the model hooks, the
  `RunSpec` type, and the `RunLogger` interface without rewriting the
  execution loop. This deferred experiment infrastructure is recorded as
  `TASK-0011`.
- The model step for `GenderNormsModel` schedules the ported systems per
  `MDR-0010`; `src/main.jl` and ODD quirk 11 remain open under
  `TASK-0010`.
- `test_decision_invariants.jl` and new `test/test_run_*.jl` files keep
  the pipeline shape executable; `registry/code/architecture.md`
  registers the new layer and files (done by the implementation work
  packages).
- Rejected alternatives: JSON as spec format would need a third-party
  parser while the TOML stdlib suffices; extending `Base.run` would be
  type piracy on `Ark.World`; a monolithic runner object holding spec and
  runtime state together would violate the spec/runtime separation and
  complicate sweeps.

## References

- `odd_model_description.typ`, `gender_model_shocks_preferences.nlogox`
- `registry/code/decisions/ADR-0002-layered-package-structure.md`
- `registry/code/decisions/ADR-0010-world-owned-model-properties.md`
- `registry/tasks.md`
