# Code Registry

This directory is the CODE half of the `registry/` system.
It records how the Julia implementation in `src/` is organized,
which conventions it follows, and which architecture decisions were made.

## Relation to `registry/model/`

- `registry/code/` covers the software side: file map, layering,
  naming and cleanliness rules, and Architecture Decision Records (ADRs).
- `registry/model/` covers the model side: ODD description, NetLogo mapping,
  and Model Decision Records (MDRs).
- Agent and model code must cite the NetLogo procedure and ODD section
  it ports (see `registry/code/conventions.md`).
  Divergences from the NetLogo or ODD behaviour require an MDR in
  `registry/model/`; structural code changes require an ADR here.

## Index

- `registry/code/architecture.md`: file map and layering of `src/`,
  module include order, and registration rules for new files.
- `registry/code/conventions.md`: normative naming, structure,
  documentation, formatting, and dead-code rules plus enforcement.
- `registry/code/decisions/ADR-0001-ark-ecs.md`: use Ark.jl ECS.
- `registry/code/decisions/ADR-0002-layered-package-structure.md`:
  `components` -> `resources` -> `systems` layering and include order.
- `registry/code/decisions/ADR-0003-utility-dispatch.md`:
  `UtilitySpec` subtype dispatch for utility forms.
- `registry/code/decisions/ADR-0004-registry-system.md`: this registry,
  ADR versus MDR split, and validator plus CI enforcement.
- `registry/code/decisions/ADR-0005-parametric-model-properties.md`:
  parametric `ModelProperties` resource that carried the network
  specification in its type parameter (superseded by `ADR-0010`).
- `registry/code/decisions/ADR-0006-transient-agent-payoff-params.md`:
  `AgentPayoffParams` as a transient input to `individual_utility` that is
  never passed between functions (superseded by `ADR-0007`).
- `registry/code/decisions/ADR-0007-set-theta-query-extraction.md`:
  household components extracted with `Ark.Query` in `set_theta!` and
  built into transient bundles at the solver call.
- `registry/code/decisions/ADR-0008-decision-record-lifecycle.md`:
  in-place amendment while a record is current, supersede once it is
  relied upon, plus the citation and index checks and the on-demand
  digest.
- `registry/code/decisions/ADR-0009-task-ledger.md`: the `TASK-NNNN`
  ledger for recorded but unimplemented work and its validator checks.
- `registry/code/decisions/ADR-0010-world-owned-model-properties.md`:
  non-parametric `ModelProperties`; the world is the single carrier of the
  network specification and systems take no specification argument
  (supersedes `ADR-0005`).
- `registry/code/decisions/ADR-0011-typed-shock-resources.md`:
  enum-free shock dispatch over concrete resources with a
  `DirectlyAffected` component tag and a `resources`/`systems` file split
  (see `MDR-0009`).
- `registry/code/decisions/ADR-0012-run-execution-pipeline.md`:
  run execution pipeline (TOML run specification, world creation,
  execution, and logging) on the new `src/runtime/` layer above
  `src/systems/` (see `MDR-0010`).
- `registry/code/decisions/ADR-0013-benchmark-harness.md`:
  benchmark tooling in `benchmark/` outside the package, with a
  driver-defined config matrix, results layout, and resumability
  (see `MDR-0011`).

## How to add a new source file correctly

1. Decide the layer for the file: `components`, `resources`, or `systems`.
   The module root `src/GenderNorms.jl` holds the include list only.
   The standalone entry point `src/main.jl` is exempt from the include list.
2. Use a `snake_case.jl` file name with one concern per file.
   Keep to the naming, docstring, and formatting rules in
   `registry/code/conventions.md`.
3. Add the `include(...)` line to `src/GenderNorms.jl` in dependency order
   (`components` -> `resources` -> `systems`, no cycles).
   Every new `.jl` file under `src/`, except `src/main.jl`,
   must be added to the module include list.
4. Add a row for the file to the file-map table in
   `registry/code/architecture.md`, with its layer,
   responsibility, and status.
5. If the file introduces or changes an architectural pattern,
   record an ADR in `registry/code/decisions/` following the
   filename, frontmatter, and heading rules in `registry/code/conventions.md`.
   If it changes model behaviour, record an MDR in `registry/model/` instead.
6. Run `julia --project=. scripts/registry_check.jl` before finishing
   and fix any reported violation.
