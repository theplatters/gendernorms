---
id: ADR-0028
title: Optimization layer boundary
status: accepted
date: 2026-10-05
supersedes: ADR-0002
superseded_by: ""
---

## Context

Two source files mix three concerns each. `src/resources/utility_functions.jl`
pairs utility formula evaluation (`UtilitySpec`, `material`,
`individual_utility`, `BestResponseObjective`) with generic numerical
solver algorithms (the in-repo Brent search, the labour best-response
solvers) and their domain constants, so a resources-layer file owns
domain solvers. `src/systems/household_bargaining.jl` pairs the ECS
orchestration of the `set_theta!` world loop with the transfer objective,
the Nash arithmetic, the transfer-search drivers, and their solver
constants, so the systems layer owns generic numerical machinery and the
solver surface is hard to see. The layered package structure of
`ADR-0002` (with the `runtime` layer added by `ADR-0012`) has no home
for pure numerical optimization that must not touch the ECS world.

Hard constraint: this is a pure code-motion refactor. Every top-level
symbol keeps its qualified name and signature (about 75 symbols); the
solver APIs are frozen by `MDR-0013` and `ADR-0018`/`ADR-0022`, tests
and benchmarks call them directly, and behavior must stay bit-identical.
The placement statements of `ADR-0015` through `ADR-0023` were written
against the then-current files and must be read as historical placement
after this record.

## Decision

Supersede `ADR-0002` with a five-layer structure whose only new layer is
`optim`, between `resources` and `systems`, and move the solver machinery
there. Physical placement only: no semantic, model, parameter, or
dependency change.

1. **Layers and dependency rules.** The layering becomes `components`
   -> `resources` -> `optim` -> `systems` -> `runtime`. `resources` may
   depend on `components`, never on optimization. `optim` may use
   `resources` and `components` and earlier `optim` files, never
   `systems`/`runtime` or ECS-world access; within `optim` the
   dependencies point backward (`core` -> `labour` -> `transfer`).
   `systems` may use `optim` and lower layers; `runtime` may use all
   lower layers. The package stays one flat module `GenderNorms` with no
   exports, unchanged. Retained structural rules from `ADR-0002`: the
   module root `src/GenderNorms.jl` owns the include list,
   `src/main.jl` stays a standalone entry point outside the module,
   dependency direction is downward only, and include cycles are
   forbidden; every new `.jl` file under `src/`, except `src/main.jl`,
   must be added to the include list in layer order and registered as a
   row in the file-map table of `registry/code/architecture.md`; an
   unwired file may only exist documented as `Excluded from module:`.
2. **Include order.** The include list in `src/GenderNorms.jl` becomes,
   in this exact order: `src/components.jl`; then
   `src/resources/utility_functions.jl`, `src/resources/social_network.jl`,
   `src/resources/observers.jl`, `src/resources/properties.jl`,
   `src/resources/shock.jl`; then `src/optim/core.jl`,
   `src/optim/labour_optimization.jl`,
   `src/optim/transfer_optimization.jl`; then
   `src/systems/household_bargaining.jl`, `src/systems/initialisation.jl`,
   `src/systems/statistics.jl`, `src/systems/shocks.jl`,
   `src/systems/preferences.jl`, `src/systems/norm_perception.jl`; then
   `src/runtime/model_interface.jl`, `src/runtime/run_spec.jl`,
   `src/runtime/run_result.jl`, `src/runtime/logging.jl`,
   `src/runtime/run_context.jl`, `src/runtime/runner.jl`,
   `src/runtime/gender_norms_model.jl`. In particular
   `src/systems/household_bargaining.jl` moves from its old position
   after `src/resources/utility_functions.jl` into the systems block.
3. **Symbol allocation.** Every moved symbol keeps its name and
   signature; only the defining file changes:

   | File | Symbols |
   | ---- | ------- |
   | `src/resources/utility_functions.jl` | `UtilitySpec`, `Additive`, `CES`, `Multiplicative`, `MultiplicativeWeighted`, `UtilityConfig`, `material`, `AgentPayoffParams`, `BestResponseObjective`, `individual_utility`, `_material_log_derivatives`, `_gradient_sign_residual`, `_best_response_derivatives`, `_best_response_gradient_sign`, `_gradient_sign_at`, `_one_sided_gradient`, `_material_envelope`, `_envelope_peak`, `CES_CERT_MIN_BETA` |
   | `src/optim/core.jl` | `_brent_maximize`, `maximize_1d` (only these: generic numerical machinery, no domain constants) |
   | `src/optim/labour_optimization.jl` | `BEST_RESPONSE_TOL`, `BEST_RESPONSE_WINDOW`, `DERIVATIVE_RESPONSE_TOL`, `DERIVATIVE_RESPONSE_MAX_ITER`, `CES_DERIVATIVE_MIN_BETA`, `_derivative_applicable`, `_derivative_response_accept`, `_derivative_seed_certificate`, `_seed_certificate_probes`, `_derivative_best_response`, `best_response_1d`, `mutual_best_response` |
   | `src/optim/transfer_optimization.jl` | `outside_options`, `_transfer_gains`, `_nash_from_gains`, `nash_product`, `equilibrium_payoff`, `bargain_transfer`, `TransferObjectiveValue`, `TransferSearchScratch`, `_reset_scratch!`, `_transfer_eval!`, `_transfer_covered`, `_transfer_sample!`, `_transfer_cover_slabs!`, `_transfer_prepare_slabs!`, `_transfer_better`, `_transfer_search!`, `_transfer_local_search!`, `_payoff_upper_bound`, `_objective_prunable`, `_payoff_interval_bound`, `_interval_normal_ok`, `_objective_interval_prunable`, and the constants `TRANSFER_COARSE_STEP`, `TRANSFER_FINE_STEP`, `TRANSFER_FINE_STEPS`, `TRANSFER_REFINE_TOL`, `TRANSFER_EXPLORE_OFFSETS`, `TRANSFER_ANCHOR_OVERLAP`, `TRANSFER_GUIDANCE_MIN`, `TRANSFER_ADAPTIVE_OFFSET`, `TRANSFER_GUIDANCE_REFINEMENTS`, `TRANSFER_MAX_REFINEMENTS`, `TRANSFER_REFINE_MAX_ITER`, `TRANSFER_SEARCH_MAX_EVALS`, `TRANSFER_SLAB_MIN_SAMPLES`, `TRANSFER_SAMPLE_CAPACITY`, `TRANSFER_CACHE_CAPACITY`, `OBJECTIVE_CERT_MARGIN` |
   | `src/systems/household_bargaining.jl` | `payoff_params`, `set_theta!`, `HOUSEHOLD_BARGAIN_CHUNK`, `HOUSEHOLD_BARGAIN_SERIAL_CUTOFF` |

   The per-symbol registration in the internal-helpers table of
   `registry/code/architecture.md` is updated to match this allocation.
4. **Minimal Brent core.** `src/optim/core.jl` holds only the generic
   numerical machinery, `_brent_maximize` and `maximize_1d`; it carries
   no domain constants. The domain solvers and every solver constant
   live in `src/optim/labour_optimization.jl` and
   `src/optim/transfer_optimization.jl`.
5. **Existing seam kept; no facade.** No facade or wrapper layer is
   introduced between the systems and the solvers: `set_theta!` and its
   `process_chunk!` closure keep calling `payoff_params`,
   `bargain_transfer`, and `individual_utility` directly, and
   `mutual_best_response` stays inside transfer optimization as the
   labour stage of the transfer objective. The `optim` files use
   resources/components types directly.
6. **Scratch ownership unchanged.** Per `ADR-0023`, `TransferSearchScratch`
   is defined and reset (`_reset_scratch!`) in
   `src/optim/transfer_optimization.jl` and constructed and owned per
   active worker task by the system (`set_theta!`), reused across the
   task's chunks and reset per household; it is never indexed by
   `Threads.threadid()` and never shared across tasks.
7. **Placement-only scope of the prior solver records.** This record
   changes physical placement only for the solver decisions in
   `ADR-0015` through `ADR-0023`; the `ADR-0007` Query-extraction
   contract of `set_theta!` and the `ADR-0026` committed-observation
   rules are preserved unchanged. File paths stated in those records
   (and in `MDR-0013` through `MDR-0017`) describe historical
   placement. The parametric role and gender markers of `ADR-0029`
   apply on top of this placement decision: the marker types and the
   role-dispatch helper family live in
   `src/resources/utility_functions.jl` as allocated above.

## Consequences

- Code motion only: behavior stays bit-identical, pinned by the existing
  equivalence, search-identity, certificate, and threading tests. The
  registry locations change: the layer list, include list, file map, and
  internal-helpers table of `registry/code/architecture.md` and the
  Julia-location columns of `registry/model/parameters.md`,
  `registry/model/processes.md`, and `registry/model/discrepancies.md`
  point at the new files.
- No model decision, parameter, dependency, or ODD semantic changes; no
  MDR is required and the NetLogo/ODD citations of the moved code stay
  with it. Historical ADR/MDR measurement texts and benchmark reports
  keep their original paths; where an older record would otherwise
  appear to prescribe current ownership, a forward pointer to this
  record is added (`ADR-0022`, `MDR-0017`).
- Verification status: pending at the time of recording. The code motion
  and the full test suite land in this same change and are verified at
  integration (`julia --project=. scripts/registry_check.jl`, the
  package load check, and the full test suite at one and multiple
  thread counts).
