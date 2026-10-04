# Code Registry

Current search decision: `registry/code/decisions/ADR-0021-seeded-guidance-transfer-driver.md`
supersedes `ADR-0020`; the seeded Brent feasibility-guided production
driver with separate bound-guidance storage is accepted (`TASK-0021`).

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
- `registry/code/decisions/ADR-0014-multithreaded-tick-systems.md`:
  multithreaded per-tick world loops (`calculate_norm_perception!`
  and `set_theta!`) with `Threads.@threads :greedy` over disjoint
  agents and households (superseded by `ADR-0023`).
- `registry/code/decisions/ADR-0015-bargaining-kernel-optimization.md`:
  behavior-preserving bargaining kernel optimization: exact identical
  solve reuse in `bargain_transfer`, chunk-task-owned `spouse_seen`
  scratch in `set_theta!`, and the certified `-Inf` transfer-objective
  certificate with its fail-open guards (implemented under `TASK-0015`).
- `registry/code/decisions/ADR-0016-transfer-search-evaluation-cache-and-staged-driver.md`:
  per-call evaluation cache `TransferObjectiveValue` and staged-search
  driver `_transfer_search!` behind the feasibility-discovery transfer
  search of `MDR-0012` (implemented under `TASK-0016`).
- `registry/code/decisions/ADR-0017-interval-certificate-and-search-storage.md`:
  sound interval-exclusion certificate `_objective_interval_prunable`
  as a Stage A objective-call prefilter and the task-owned reusable
  `TransferSearchScratch` search storage replacing the per-call `Dict`
  of `ADR-0016` (implemented under `TASK-0017`).
- `registry/code/decisions/ADR-0018-prepared-best-response-objective.md`:
  prepared own-hours objective `BestResponseObjective` hoisting the
  transfer- and spouse-dependent terms out of the 1-D best-response
  evaluation, with `individual_utility` delegating to it as the single
  objective implementation (implemented under `TASK-0019`, arithmetic
  change governed by `MDR-0013`).
- `registry/code/decisions/ADR-0019-tiered-search-machinery-and-specialized-ces-envelope.md`:
  tiered sample enumeration and sampled-sequence/evaluation-cache
  discipline of `_transfer_search!` (slab-covered samples stay out of
  the cache) and the specialized `CES` `beta == 0.5` sqrt/square
  `_material_envelope` with its margin re-derivation (implemented
  under `TASK-0018`, sample-set semantics governed by `MDR-0014`;
  retires the bitwise search-identity oracle of `ADR-0017`).

- `registry/code/decisions/ADR-0020-bounded-production-transfer-driver.md`:
  bounded production driver alongside the retained discovery driver,
  explicit local/discovery keyword, shared objective and commit path,
  and smaller production scratch hints (see `MDR-0015`; superseded by
  `ADR-0021`).

- `registry/code/decisions/ADR-0021-seeded-guidance-transfer-driver.md`:
  feasibility-guided production driver with the sparse adaptive schedule
  of `MDR-0016`: explicit-seed `_brent_maximize` variant, separate
  guidance gains on `TransferObjectiveValue`, single-lookup evaluation
  cache, and 32-record production storage hints (see `MDR-0016`).

- `registry/code/decisions/ADR-0022-specialized-derivative-best-response.md`:
  specialized `best_response_1d(::BestResponseObjective, ::Float64)`
  dispatch with the two-tier safeguarded derivative solve of
  `MDR-0017` (the `BEST_RESPONSE_TOL` seed certificate, then the
  `DERIVATIVE_RESPONSE_TOL` full solve), the unchanged bitwise generic
  Brent fallback, the allocation-free derivative helpers, and the
  fail-open-to-legacy policy (extends `ADR-0018`).

- `registry/code/decisions/ADR-0023-task-owned-bargaining-scratch.md`:
  task-owned `spouse_seen` and `TransferSearchScratch` reuse per active
  worker task in `set_theta!` and bounded worker scheduling: the bounded
  worker-task loop over a shared atomic chunk cursor with the
  shared-work-queue variant rejected by measurement,
  `HOUSEHOLD_BARGAIN_CHUNK` re-confirmed at 4, and
  `HOUSEHOLD_BARGAIN_SERIAL_CUTOFF` 8 from the measured serial
  crossover (see `benchmark/scheduling_tuning.md`).

- `registry/code/decisions/ADR-0024-task-owned-norm-perception-scratch.md`:
  the `ADR-0023` pattern applied to `calculate_norm_perception!` (which
  `ADR-0023` left out of scope; no supersede): one flattened
  women-then-men parallel region with arithmetic chunk decoding,
  bounded worker tasks over a shared atomic chunk cursor, one
  capacity-hinted `spouse_seen` per worker task reused across chunks
  (the per-agent scratch allocation removed), and `chunk`/`schedule`
  keywords with `NORM_PERCEPTION_CHUNK` 64 and
  `NORM_PERCEPTION_SERIAL_CUTOFF` 256 from measurements.

- `registry/code/decisions/ADR-0025-interactive-dashboard.md`:
  interactive Genie/Stipple/StipplePlotly dashboard in a separate
  `dashboard/` project outside `src/` (extends `ADR-0012`, follows
  `ADR-0013`): live runs in one isolated worker process per run behind
  a FIFO queue with a buffered dashboard `RunLogger` and versioned
  JSONL IPC, shared live/recorded path representation with staged
  writes and atomic promotion, and throttled Plotly panels
  (implemented under `TASK-0028`).

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
