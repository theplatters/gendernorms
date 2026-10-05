# Architecture

This file maps every Julia source file under `src/` to its layer,
responsibility, and wiring status. It is normative: the table below
is the single source of truth for where code lives.

## Layers

The package uses the layering `components` -> `resources` -> `optim` ->
`systems` -> `runtime` (`ADR-0002`, revised by `ADR-0028`).

- `components`: plain data structs used as Ark ECS components.
  No behaviour, no dependencies on other layers.
- `resources`: shared configuration, utility functions, network
  construction, observers, and properties. May depend on `components`,
  never on optimization.
- `optim`: numerical optimization: the generic Brent core, the labour
  best-response solvers, and the transfer search. May use `resources`
  and `components` and earlier `optim` files, never `systems`/`runtime`
  or ECS-world access.
- `systems`: initialisation and model dynamics that operate on the
  Ark world using `components`, `resources`, and `optim`. May depend on
  every layer below it.
- `runtime`: run specification, run lifecycle, logging, and model
  binding. May depend on every layer below it.
- Dependency direction is downward only: `runtime` may use `systems`,
  `optim`, `resources`, and `components`; `systems` may use `optim`,
  `resources`, and `components`; `optim` may use `resources` and
  `components` and earlier `optim` files (within `optim` the
  dependencies point backward: `core` -> `labour` -> `transfer`);
  `resources` may use `components`; `components` must not depend on any
  layer above it. No include cycles.

## Module include order

The include list in `src/GenderNorms.jl` defines the load order.
It currently reads, in this exact order:

1. `src/components.jl`
2. `src/resources/utility_functions.jl`
3. `src/resources/social_network.jl`
4. `src/resources/observers.jl`
5. `src/resources/properties.jl`
6. `src/resources/shock.jl`
7. `src/optim/core.jl`
8. `src/optim/labour_optimization.jl`
9. `src/optim/transfer_optimization.jl`
10. `src/systems/household_bargaining.jl`
11. `src/systems/initialisation.jl`
12. `src/systems/statistics.jl`
13. `src/systems/shocks.jl`
14. `src/systems/preferences.jl`
15. `src/systems/norm_perception.jl`
16. `src/runtime/model_interface.jl`
17. `src/runtime/run_spec.jl`
18. `src/runtime/run_result.jl`
19. `src/runtime/logging.jl`
20. `src/runtime/run_context.jl`
21. `src/runtime/runner.jl`
22. `src/runtime/gender_norms_model.jl`

The module root is `src/GenderNorms.jl`.

## File map

| File | Layer | Responsibility | Status |
| ---- | ----- | -------------- | ------ |
| `src/GenderNorms.jl` | module root | Declares module `GenderNorms`, imports (`Ark`, `Graphs`, `Random`, `Dates`, `TOML`, `UUIDs`, `Distributions.Normal`), and include list | Included |
| `src/main.jl` | entry point | Standalone entry point, currently empty | Empty standalone file |
| `src/components.jl` | components | Ark ECS components as plain structs: gender, working time, transfers, spouse, wage, preferences, conformism, `NormParameter`, `PerceptionNormDivisionOfLabor`, `Lambda`, `DirectlyAffected`, and the committed-bundle utility observation `CommittedUtility` (`MDR-0019`; the unused `CurrentUtility` placeholder stays removed, see `MDR-0018`) | Included |
| `src/resources/utility_functions.jl` | resources | Utility specifications and payoff functions: `UtilitySpec` subtypes (`Additive`, `CES`, `Multiplicative`, `MultiplicativeWeighted`), `UtilityConfig`, the transient `AgentPayoffParams{G<:Gender}` parameter object of `mutual_best_response` and `individual_utility` (gender as the phantom type parameter `G` over the `Male`/`Female` markers, `ADR-0029`), the prepared own-hours objective `BestResponseObjective{S<:UtilitySpec,Recipient}` (hoisted transfer- and spouse-dependent terms, statically split role constructor and the role-dispatch helper family, exact expression grouping with the unified `MultiplicativeWeighted` role arithmetic of `MDR-0023`, `individual_utility` delegates to it; `MDR-0013`, `ADR-0018`, `ADR-0029`), `material` (including the validated-equivalent `CES` `beta == 0.5` sqrt/square specialization of `MDR-0013`), `individual_utility`, the gender-dispatched relevant transfer `_get_relevant_transfer` (`ADR-0029`), the derivative helpers `_material_log_derivatives`, `_gradient_sign_residual`, `_best_response_derivatives`, `_best_response_gradient_sign`, `_gradient_sign_at`, and `_one_sided_gradient` of the specialized best response (`MDR-0017`, `ADR-0022`), the role-dispatch helpers `_eval_objective_function`, `_x_for_gradient`, `_A_for_gradient`, `_consumption_slope`, `_consumption_at_upper`, `_consumption_intercept`, `_lower_material_gradient`, and `_upper_material_gradient` (`MDR-0017`, `ADR-0029`), and the material-envelope certification helpers `_material_envelope` and `_envelope_peak` with the certified CES `beta` floor `CES_CERT_MIN_BETA` of the certified `-Inf` transfer-objective certificate (`ADR-0015`) | Included |
| `src/resources/social_network.jl` | resources | Network specifications and graph construction: `NetworkSpec` subtypes, `SocialNetwork`, `generate` methods, similarity and homophily builders | Included |
| `src/resources/observers.jl` | resources | Observer structs for the per-tick aggregates: `WorkingTimeStats` (men/women/gap working-time means) plus the `PreferenceStats`, `UtilityStats`, and `TransferStats` observers of `MDR-0019`-`MDR-0021`, all written by `update_observer_stats!` | Included |
| `src/resources/properties.jl` | resources | Model properties and run state: the non-parametric `ModelProperties` resource that carries the `NetworkSpec` (`ADR-0010`), `PaidTime`, `MeanWage`, `MeanPreference`, `InitialConformism`, `ProbeCouple` | Included |
| `src/resources/shock.jl` | resources | Shock-mode resources: the abstract dispatch root `Shock` plus the concrete `WageShock`, `PreferenceShock`, and `WageGrowth` resources (see `MDR-0009`, `ADR-0011`) | Included |
| `src/optim/core.jl` | optim | Generic 1-D maximization machinery: the in-repo Brent search `maximize_1d` with its seeded variant and the `_brent_maximize` core (explicit initial-point variant for guidance/payoff refinement, `ADR-0021`); no domain constants (`ADR-0028`) | Included |
| `src/optim/labour_optimization.jl` | optim | Labour best-response solvers: `mutual_best_response` (labour stage, port of `choose-bundle`, alternating closure-free over the prepared own-hours objectives of `MDR-0013`/`ADR-0018`) and `best_response_1d` (the seeded `MDR-0002` fallback with the solver constants `BEST_RESPONSE_TOL` and `BEST_RESPONSE_WINDOW`, and the specialized derivative `best_response_1d(::BestResponseObjective, ::Float64)` of `MDR-0017`: `_derivative_best_response` with `_derivative_applicable`, `_derivative_seed_certificate`, `_seed_certificate_probes`, and `_derivative_response_accept`, the solver constants `DERIVATIVE_RESPONSE_TOL` and `DERIVATIVE_RESPONSE_MAX_ITER`, and the CES `beta` applicability floor `CES_DERIVATIVE_MIN_BETA`; `ADR-0022`) | Included |
| `src/optim/transfer_optimization.jl` | optim | Transfer-stage solvers: `bargain_transfer` (transfer stage, port of `set-theta` and `calculate-payoff`), with the bounded feasibility-guided production driver `_transfer_local_search!` of `MDR-0016`/`ADR-0021` and the retained tiered discovery driver `_transfer_search!` of `MDR-0014` selected explicitly by `search=:discovery`; both share `TransferObjectiveValue`, the `TransferSearchScratch` defined and reset here (constructed and owned per active worker task by the system, `ADR-0023`), the objective helpers `outside_options`, `equilibrium_payoff`, `nash_product`, `_transfer_gains`, and `_nash_from_gains`, and the strict cached-hours commit rule. The production solver parameters are `TRANSFER_EXPLORE_OFFSETS`, `TRANSFER_ANCHOR_OVERLAP`, `TRANSFER_GUIDANCE_MIN`, `TRANSFER_ADAPTIVE_OFFSET`, `TRANSFER_REFINE_TOL`, `TRANSFER_GUIDANCE_REFINEMENTS`, `TRANSFER_MAX_REFINEMENTS`, `TRANSFER_REFINE_MAX_ITER`, and `TRANSFER_SEARCH_MAX_EVALS`; `TRANSFER_COARSE_STEP`, `TRANSFER_FINE_STEP`, and `TRANSFER_FINE_STEPS` are discovery-only. Both modes reuse the outside-option solve exactly at bitwise `+0.0`, skip search on non-finite outside options, and use the pointwise `_objective_prunable`, `_payoff_upper_bound`, and `OBJECTIVE_CERT_MARGIN` (`ADR-0015`); discovery additionally uses `_objective_interval_prunable` and `_payoff_interval_bound` with the tight-corner guard `_interval_normal_ok` (`ADR-0017`) | Included |
| `src/systems/household_bargaining.jl` | systems | Household bargaining ECS orchestration: `payoff_params` (build one transient `AgentPayoffParams{G}` from an agent's traits and perceived norms, dispatching the gender marker `::G where {G<:Gender}`, `ADR-0029`) and the Query-based world loop `set_theta!`, which calls `payoff_params`, `bargain_transfer`, and `individual_utility` directly (no facade, `ADR-0028`) and commits both partners' hours and transfer plus their committed-bundle `CommittedUtility` observations (woman via the query column, man in the commit tuple; `MDR-0019`, `ADR-0026`); `set_theta!` defaults to local search and accepts the discovery keyword plus the `chunk`/`schedule` tuning keywords for tests and benchmark sweeps; disjoint household chunks of `chunk` items run through one shared per-chunk closure, either on the direct serial path (one thread, or at most `HOUSEHOLD_BARGAIN_SERIAL_CUTOFF` households under `:auto`) or on at most `min(Threads.nthreads(), nchunks)` bounded worker tasks pulling chunk indices from a shared atomic chunk cursor, each worker task owning one `spouse_seen` vector and one search scratch across its chunks (`ADR-0014`, `ADR-0023`) | Included |
| `src/systems/initialisation.jl` | systems | Model setup: household creation, trait draws, and social network construction from the world's `ModelProperties` with an explicit caller-provided `rng` (`ADR-0010`); every agent starts with `CommittedUtility(NaN)` = "not yet observed" (`MDR-0019`, `ADR-0026`) | Included |
| `src/systems/statistics.jl` | systems | Statistics core (port of `update-statistics`, see `MDR-0007`): the lag copy `update_old_working_time_and_transfer!`, the fused observer snapshot `update_observer_stats!` (women-then-men serial reductions writing `WorkingTimeStats`, `PreferenceStats`, `UtilityStats`, and `TransferStats` at the tick's single pre-adaptation observation point, see `MDR-0019`-`MDR-0022` and `ADR-0026`), and the standalone contemporaneous men/women/gap means `update_global_working_times!` kept for minimal worlds | Included |
| `src/systems/shocks.jl` | systems | Shock dynamics (port of `start-shock` and `end-shock`, see `MDR-0009`): the `WAGE_CUT` factor, `select_affected!`, `start_shock!`, `recover_shock!`, the `update_shocks!` tick scheduler, and the ported-but-unscheduled `update_wages!` | Included |
| `src/systems/preferences.jl` | systems | Preference dynamics: `update_preferences`, the clipped adaptation of `PreferencePrivate` toward own working time | Included |
| `src/systems/norm_perception.jl` | systems | Norm perception port of `calculate-utility`: `norm_global_means`, `norm_means`, `norm_penalty`, and `calculate_norm_perception!`; the world loop flattens the women chunks then the men chunks of disjoint agents into one parallel region and decodes chunk ranges arithmetically in a shared per-chunk closure, which runs on the direct serial path or on at most `min(Threads.nthreads(), nchunks)` bounded worker tasks pulling chunk indices from a shared atomic chunk cursor, each worker task owning one capacity-hinted `spouse_seen` scratch vector across its chunks, selected by the `chunk`/`schedule` keywords (`NORM_PERCEPTION_CHUNK`, `NORM_PERCEPTION_SERIAL_CUTOFF`; see `ADR-0014`, `ADR-0015`, `ADR-0024`) | Included |
| `src/runtime/model_interface.jl` | runtime | Model binding interface: the `AbstractModel` dispatch root, the `MODEL_REGISTRY` name mapping with `resolve_model`, and the six model hooks `model_name`, `parse_model_config`, `setup_world`, `step_model!`, `model_metrics`, and `config_to_dict` (see `ADR-0012`) | Included |
| `src/runtime/run_spec.jl` | runtime | Run specification: the immutable `RuntimeConfig`, `OutputSpec`, `LoggingConfig`, and `RunSpec` types, the aggregated `RunSpecError` with its `Base.showerror` rendering, the `parse_spec` validation entry point, `load_spec` file loading, the `spec_to_dict` round-trip echo, and the `_key_problems` unknown-key helper reused by model bindings (see `ADR-0012`) | Included |
| `src/runtime/run_result.jl` | runtime | Run outcome records: the `RunStatus` enum with `RUN_SUCCESS` and `RUN_FAILURE`, the `RunInfo` start description for logger hooks, the `RunResult` in-memory record, and the `is_success` status check (see `ADR-0012`) | Included |
| `src/runtime/logging.jl` | runtime | Logging sinks: the `RunLogger` interface with the no-op `run_started!`, `metrics_recorded!`, and `run_finished!` hooks, the `LOG_OUTPUT_TYPES` backend registry with `validate_output_spec` and `build_logger` dispatch, and the `TomlLogger` file backend with its `_write_run_record` writer (see `ADR-0012`) | Included |
| `src/runtime/run_context.jl` | runtime | Per-run mutable state: the non-parametric `RunContext` world resource carrying run id, spec, model, config, metric functions, loggers, and the seeded RNG (see `ADR-0012`) | Included |
| `src/runtime/runner.jl` | runtime | World creation and execution: `create_world` initialization with the seeded RNG, `add_logger!` programmatic backends, and the module-local `run` entry point with its record-or-rethrow failure semantics (see `ADR-0012`) | Included |
| `src/runtime/gender_norms_model.jl` | runtime | Model binding for this package: `GenderNormsModel` registered as `"gender_norms"` with its `GenderNormsConfig`, the `setup_world` setup port (registering `CommittedUtility` and the observer resources, `ADR-0026`), the `step_model!` go port (see `MDR-0022`, which supersedes `MDR-0010`), the eight-name observer `model_metrics`, the `config_to_dict` echo, and the `_parse_network_table`, `_parse_utility_table`, `_parse_gender_pair`, `_network_to_dict`, and `_utility_to_dict` table helpers (see `ADR-0012`) | Included |

## Registration rule

Every new `.jl` file under `src/` must be added to the module include
list in `src/GenderNorms.jl` at the correct layer position and must be
added as a row to the file-map table above. The only exception is
`src/main.jl`, which is the standalone entry point and is intentionally
not included by the module.

## Excluded files

Note: `src/main.jl` is the standalone entry point. It is currently empty
and is exempt by rule from the module include list, but it is documented
in the table above.

## Internal helpers

Private, non-exported helpers are documented here so that every
top-level definition has a registry entry. They are implementation
details and are not part of the package's public surface.

| Helper | File | Purpose |
| ------ | ---- | ------- |
| `NoNetwork` | `src/resources/social_network.jl` | `NetworkSpec` subtype producing an edgeless network. |
| `HomogeneousMixing` | `src/resources/social_network.jl` | `NetworkSpec` subtype producing an edgeless network; norm perception uses global means instead of neighbours. |
| `_watts_strogatz_k` | `src/resources/social_network.jl` | Clamp the Watts-Strogatz degree to a valid even `k` with `0 < k < n`. |
| `network_graph` | `src/systems/initialisation.jl` | Dispatch a `NetworkSpec` to the matching graph generator for a set of agents. |
| `trait_value` | `src/systems/initialisation.jl` | Read one similarity trait (`wage`, `conformism`, `preference_private`) from an entity. |
| `trait_values` | `src/systems/initialisation.jl` | Vectorised `trait_value` over a collection of entities. |
| `entities_with` | `src/systems/initialisation.jl` | Collect all entities that carry a given component type. |
| `_mean_old_working_time` | `src/systems/norm_perception.jl` | Mean lagged (`old`) working time over a non-empty entity collection. |
| `_mean_old_transfer` | `src/systems/norm_perception.jl` | Mean lagged (`old`) transfer to the woman over a non-empty entity collection. |
| `norm_global_means` | `src/systems/norm_perception.jl` | Global lagged means over the `SocialNetwork` entity vectors (isolated agents under homogenous mixing). |
| `norm_means` | `src/systems/norm_perception.jl` | Perceived norms of one agent: same-sex neighbour means plus spouses-of-neighbours working time, with isolated fallbacks; the neighbour branch iterates the neighbour list without materialising it and deduplicates spouses into a caller-owned scratch buffer so the per-agent computation allocates nothing. |
| `norm_penalty` | `src/systems/norm_perception.jl` | Norm exponent of `calculate-utility`: weighted squared deviations from the perceived norms. |
| `calculate_norm_perception!` | `src/systems/norm_perception.jl` | Compute and store `PerceptionNormDivisionOfLabor` and `NormParameter` for every agent; the shared per-chunk closure over the flattened women-then-men chunk indices runs on the direct serial path or on bounded worker tasks pulling chunk indices from a shared atomic cursor, selected by the `schedule` keyword (`:auto` is serial at one thread or at most `NORM_PERCEPTION_SERIAL_CUTOFF` total agents) with `chunk` agents per chunk (`ADR-0024`). |
| `NORM_PERCEPTION_CHUNK` | `src/systems/norm_perception.jl` | Agents per chunk (64) of the `calculate_norm_perception!` world loop, shared by the serial path and the bounded worker tasks; chunking origin `ADR-0014`, value 64 selected by the chunk-size sweep under `ADR-0024`. |
| `NORM_PERCEPTION_SERIAL_CUTOFF` | `src/systems/norm_perception.jl` | Serial crossover (256 total agents, women plus men) of the `:auto` schedule of `calculate_norm_perception!`: on multithreaded runs a world of at most this size runs the direct serial path instead of the bounded worker tasks; selected from the 8-thread forced-path crossover measurements (see `ADR-0024`). |
| `outside_options` | `src/optim/transfer_optimization.jl` | Zero-transfer outside options of both partners: the first lines of `set-theta`. |
| `maximize_1d` | `src/optim/core.jl` | In-repo Brent 1-D maximization with the seeded variant: the continuous solver behind `best_response_1d` and `bargain_transfer`. |
| `_brent_maximize` | `src/optim/core.jl` | Core Brent search behind `maximize_1d`, returning the best finite sample; explicit initial-point variant for guidance/payoff refinement (`ADR-0021`). |
| `mutual_best_response` | `src/optim/labour_optimization.jl` | Labour stage of the bargaining chain (port of `choose-bundle`): alternating closure-free best responses over the prepared own-hours objectives of `MDR-0013`/`ADR-0018`, each partner's hours solved by `best_response_1d` at the partner's previous hours until both changes fall within `eps` or `max_sweeps` rounds run (`MDR-0002`, `MDR-0017`). |
| `best_response_1d` | `src/optim/labour_optimization.jl` | Labour best response on `[0, 1]`: the specialized method on `BestResponseObjective` runs the two-tier safeguarded derivative solve of `MDR-0017` (the tier-1 seed certificate at `BEST_RESPONSE_TOL`, else the tier-2 full solve at `DERIVATIVE_RESPONSE_TOL`) and falls back to the seeded `BEST_RESPONSE_TOL`/`BEST_RESPONSE_WINDOW` expression of `MDR-0002` bitwise; the generic method keeps that seeded expression for generic callers (`MDR-0002`, `MDR-0017`, `ADR-0022`). |
| `_derivative_applicable` | `src/optim/labour_optimization.jl` | Applicability gate of the derivative best response: eligible specs (`Additive`, `Multiplicative`, `MultiplicativeWeighted`, `CES` with `CES_DERIVATIVE_MIN_BETA <= beta <= 1`), finite `h_start`, in-range and non-negative objective parameters, and non-negative consumption coefficients with `A > 0 || B > 0`; everything else runs the `MDR-0002` fallback (`MDR-0017`, `ADR-0022`). |
| `_material_log_derivatives` | `src/resources/utility_functions.jl` | Per-spec material log-derivative pair `g_mat`/`g_prime_mat` plus the same-pass material value of the combined derivative evaluation (the `MDR-0017` formulas with one shared reciprocal per form between the `g_mat` and `g_prime_mat` divisions, incl. the `CES` `beta == 1` special case), failing open with `NaN` for unenveloped specs (`MDR-0017`, `ADR-0022`). |
| `_gradient_sign_residual` | `src/resources/utility_functions.jl` | Per-spec division-free sign residual of the total log-derivative `g` for the derivative sign probes: `g` multiplied through by the spec's positive denominator (the `MDR-0017` sign forms, incl. the `CES` `beta == 0.5`/`beta == 1` special cases), with the `x * Q` / `sqrt(x) * sqrt(Q)` subnormal guards; the residual sign is the analytic sign of `g` up to the rounding of the multiplied-through form (`MDR-0017`, `ADR-0022`). |
| `_best_response_derivatives` | `src/resources/utility_functions.jl` | Combined derivative evaluation `(g, g_prime, value)` in one pass over the exact `x`/`Q`/`norm` groupings of the objective call overload (the value is bitwise `obj(h)`), with the fail-open numerical gate (`MDR-0017`, `ADR-0022`). |
| `_x_for_gradient` | `src/resources/utility_functions.jl` | Role-dispatched `x` of the derivative evaluations: the recipient's `h * wage_self + transfer_income` and the payer's `(h * wage_self) * one_minus_transfer`, in the call-overload expression grouping (`MDR-0017`, `ADR-0029`). |
| `_A_for_gradient` | `src/resources/utility_functions.jl` | Role-dispatched consumption slope `A` of the derivative formulas: `wage_self` for the recipient, `wage_self * one_minus_transfer` for the payer (`MDR-0017`, `ADR-0029`). |
| `_best_response_gradient_sign` | `src/resources/utility_functions.jl` | Derivative sign probe of the enclosure checks: the `_gradient_sign_residual` sign residual of `g` at a point with the point guards, `NaN` (skipped, never fatal) outside the guarded domain, on a non-finite or subnormal positive denominator product, or on a non-finite residual (`MDR-0017`, `ADR-0022`). |
| `_gradient_sign_at` | `src/resources/utility_functions.jl` | Shared-coefficient sign probe core behind `_best_response_gradient_sign` and the tier-1 seed-certificate probes: caller-supplied `A` and `k`, the `_gradient_sign_residual` sign form, same guards and `NaN` skip semantics (`MDR-0017`, `ADR-0022`). |
| `_derivative_seed_certificate` | `src/optim/labour_optimization.jl` | Tier-1 seed certificate of the derivative best response: two sign probes at `h_start +/- BEST_RESPONSE_TOL` and their one-sided domain-end rules certify the seed within that resolution of the optimum and keep its hours, at probe cost (one probe at a feasible boundary seed); a guard-open boundary seed never certifies (`MDR-0017`, `ADR-0022`). |
| `_seed_certificate_probes` | `src/optim/labour_optimization.jl` | Rule core of the tier-1 two-probe seed enclosure: the two `_gradient_sign_at` probes at `h_start +/- BEST_RESPONSE_TOL` with shared coefficients plus the boundary-seed rules (`MDR-0017`, `ADR-0022`). |
| `_consumption_slope` | `src/resources/utility_functions.jl` | Role-dispatched consumption slope `A` shared by the tier-1 seed certificate and the one-sided limits: `wage_self` for the recipient, `wage_self * one_minus_transfer` for the payer (`MDR-0017`, `ADR-0029`). |
| `_consumption_at_upper` | `src/resources/utility_functions.jl` | Role-dispatched consumption `x(1)` at the upper hours endpoint: `A + transfer_income` for the recipient, `A` for the payer (`MDR-0017`, `ADR-0029`). |
| `_consumption_intercept` | `src/resources/utility_functions.jl` | Role-dispatched consumption intercept `B`: `transfer_income` for the recipient, `0.0` for the payer (`MDR-0017`, `ADR-0029`). |
| `_lower_material_gradient` | `src/resources/utility_functions.jl` | Per-spec analytic limit of the material log-derivative `g` at the guard-infeasible lower endpoint `h -> 0+` (`+Inf`, the finite form, or `NaN` fail-open), consumed by `_one_sided_gradient` (`MDR-0017`, `ADR-0029`). |
| `_upper_material_gradient` | `src/resources/utility_functions.jl` | Per-spec analytic limit of the material log-derivative `g` at the guard-infeasible upper endpoint `h -> 1-` (`-Inf`, the finite form, or `NaN` fail-open), consumed by `_one_sided_gradient` (`MDR-0017`, `ADR-0029`). |
| `_one_sided_gradient` | `src/resources/utility_functions.jl` | Analytic one-sided limit of `g` at a guard-infeasible endpoint: `+Inf` at `h -> 0+` and `-Inf` at `h -> 1-` where the singular coefficient is nonzero, the finite analytic limit (material part plus the norm slope) where the form is nonsingular, `NaN` where indeterminate; bracketed only when it points away from the infeasible endpoint (`MDR-0017`, `ADR-0022`). |
| `_derivative_response_accept` | `src/optim/labour_optimization.jl` | Value acceptance of a derivative candidate: finite positive candidate value within 32 ulps of every evaluated feasible endpoint and seed value (`MDR-0017`, `ADR-0022`). |
| `_derivative_best_response` | `src/optim/labour_optimization.jl` | Two-tier safeguarded derivative best response: the tier-1 `_derivative_seed_certificate` keeps certified seeds at the `BEST_RESPONSE_TOL` resolution, the tier-2 full solve runs lazy endpoint signs with the strict boundary rules and the analytic one-sided limits, then bracketed safeguarded Newton/bisection with the probe sign-enclosure certificate or the sign-bracket width-exit certificate (both-probe enclosure required where evaluable, skipped probes accept the sign bracket), `(candidate, ok)` with `ok == false` running the `MDR-0002` fallback (`MDR-0017`, `ADR-0022`). |
| `DERIVATIVE_RESPONSE_TOL` | `src/optim/labour_optimization.jl` | Hours tolerance (1.0e-8) of the derivative best response: Newton step and bracket-width termination bound and sign-enclosure probe half-width (`MDR-0017`). |
| `DERIVATIVE_RESPONSE_MAX_ITER` | `src/optim/labour_optimization.jl` | Iteration cap (40) of the derivative best response's safeguarded Newton/bisection before falling back to `MDR-0002` (`MDR-0017`). |
| `BestResponseObjective` | `src/resources/utility_functions.jl` | Prepared own-hours objective of one `best_response_1d` call: the `individual_utility` of one partner at fixed spouse hours and transfer with every transfer- and spouse-dependent term hoisted out of the per-hours evaluation; an isbits callable parametric on `{S<:UtilitySpec,Recipient}` (the statically split role constructor of `ADR-0029`), constructed per best-response call and evaluated at own hours, with the exact expression grouping of the old `individual_utility` and identical guard triggers (modulo the `MDR-0023` payer-branch fix); `individual_utility` delegates to it as the single objective implementation, and the derivative solve of `MDR-0017` reads its coefficients for the log-utility derivatives (`MDR-0013`, `ADR-0018`, `ADR-0022`, `ADR-0029`). |
| `_eval_objective_function` | `src/resources/utility_functions.jl` | Shared body of the two `BestResponseObjective` call overloads: the `Q`, guard, norm, and `material` evaluation at the role-specific `x` of the call site, keeping the exact expression grouping of `individual_utility` (`ADR-0018`, `ADR-0029`). |
| `_envelope_peak` | `src/resources/utility_functions.jl` | Envelope evaluation helper of the certified `-Inf` transfer-objective certificate: evaluate the envelope candidate at `v == 0`, `v == v_star`, and `v == d` and take the largest (no dependence on maximizer mislocation), failing open on out-of-range or subnormal intermediates (`ADR-0015`). |
| `_material_envelope` | `src/resources/utility_functions.jl` | Per-spec material-utility envelopes of the certified `-Inf` transfer-objective certificate over `x <= q*v`, `Q <= 2-v`: the analytic maximizer per `UtilitySpec` (the `MultiplicativeWeighted` maximizer `2*alpha` for both roles after `MDR-0023`) plus a fail-open fallback for unenveloped specs; the dead `recipient::Bool` argument is dropped (`ADR-0015`, `ADR-0029`). |
| `CES_CERT_MIN_BETA` | `src/resources/utility_functions.jl` | Lower end (1.0e-3) of the certified CES `beta` band: below it the outer power `S^(1/beta)` amplifies inner-sum rounding by `1/beta` past `OBJECTIVE_CERT_MARGIN`, so the envelope fails open instead (`ADR-0015`). |
| `CES_DERIVATIVE_MIN_BETA` | `src/optim/labour_optimization.jl` | Lower end (1.0e-3) of the CES `beta` band of the derivative best response: below it the `1/beta` amplification of the inner-sum rounding jags the computed utility past the measured 1.0e-11 non-degradation envelope, so `_derivative_applicable` declines and the bitwise `MDR-0002` fallback runs instead (`MDR-0017`, `ADR-0022`). |
| `nash_product` | `src/optim/transfer_optimization.jl` | Nash product of the two utility gains over the outside options; `-Inf` when a gain is negative (port of `calculate-payoff`). |
| `equilibrium_payoff` | `src/optim/transfer_optimization.jl` | Labour equilibrium at one transfer plus its Nash product. |
| `OBJECTIVE_CERT_MARGIN` | `src/optim/transfer_optimization.jl` | Total relative margin (1.0e-9) inflating the envelope bound of the certified `-Inf` transfer-objective certificate before it is compared against an outside option; sized against the CES `1/beta` rounding amplification admitted by `CES_CERT_MIN_BETA` (`ADR-0015`). |
| `_payoff_upper_bound` | `src/optim/transfer_optimization.jl` | Certified upper bound on the computed `individual_utility` of one partner over all feasible working times, or `NaN` on fail open (`ADR-0015`). |
| `_objective_prunable` | `src/optim/transfer_optimization.jl` | Certified `-Inf` decision of the payoff-only transfer objective: prune a sampled transfer when a sound bound puts one partner's utility strictly below that partner's outside option; fail open otherwise (`ADR-0015`). |
| `_payoff_interval_bound` | `src/optim/transfer_optimization.jl` | Certified upper bound on the computed `individual_utility` of one partner at every transfer of a nonzero-sign slab (slackest consumption `q`, minimum norm penalty `z_min`, plus the pointwise-parity guards at the slab's tightest corner), or `NaN` on fail open (`ADR-0017`). |
| `_interval_normal_ok` | `src/optim/transfer_optimization.jl` | Tight-corner material guard of `_payoff_interval_bound`: the exactly-zero consumption exception (`iszero(q_slack)`) where pointwise parity holds through the identical exact `0.0` rule alone; mixed zero/nonzero consumption ranges do not qualify and both certificate paths fail open (`ADR-0017`). |
| `_objective_interval_prunable` | `src/optim/transfer_optimization.jl` | Sound interval-exclusion decision of the payoff-only transfer objective: `true` only when every transfer of the closed interval has computed Nash payoff exactly `-Inf`, with the zero point delegated to the pointwise `_objective_prunable` and a margin-inflated strict comparison; fail open otherwise (`ADR-0017`). |
| `bargain_transfer` | `src/optim/transfer_optimization.jl` | Bounded feasibility-guided production transfer search of `MDR-0016`, or the retained `MDR-0014` scan with `search=:discovery`; shared status seeding, fixed warm starts, strict-improvement cached-hours commit, exact status fallback, non-finite-outside fast path, and pointwise certificate. A scratch-taking method is the implementation; a standalone method builds one scratch per call (`ADR-0021`). |
| `TransferObjectiveValue` | `src/optim/transfer_optimization.jl` | Immutable evaluation record of one transfer: both utility gains, the Nash payoff, the solved hours, and separate `guidance_w`/`guidance_m` guidance gains (true gains at solved probes, certified bound gains at pruned probes); a certificate-pruned transfer is recorded with payoff `-Inf` and `NaN` gains and hours (`MDR-0012`, `ADR-0016`, `ADR-0021`). |
| `TransferSearchScratch` | `src/optim/transfer_optimization.jl` | Task-owned reusable search storage (`ADR-0017`): the evaluation cache, the sampled-transfer vector, the Stage B weak-maximum index vector, and the certified-slab list; one per active worker task of `set_theta!`, reused across every chunk the task processes and reset per household, never indexed by `Threads.threadid()`, never shared across tasks, and never retaining a household's parameters or closures (`ADR-0023` amends the per-chunk ownership wording of `ADR-0015` item C1/`ADR-0017` item 4 to per worker task). |
| `TRANSFER_CACHE_CAPACITY` | `src/optim/transfer_optimization.jl` | Production cache hint (32 records; the typical call needs 15 and exceptional calls grow normally, `Dict` `empty!` retains the storage across households); explicit discovery grows it normally (`ADR-0021`). |
| `TRANSFER_SAMPLE_CAPACITY` | `src/optim/transfer_optimization.jl` | Production sampled-vector hint (32), below the `TRANSFER_SEARCH_MAX_EVALS` raw entries including the seed; explicit discovery grows it normally (`ADR-0021`). |
| `_reset_scratch!` | `src/optim/transfer_optimization.jl` | Prepare one `TransferSearchScratch` for the next household: empty the cache and side vectors (keeping capacity) and re-apply the capacity hint without shrinking (`ADR-0017`). |
| `_transfer_eval!` | `src/optim/transfer_optimization.jl` | Cached evaluation of the staged transfer search: the cached `TransferObjectiveValue` at an exact transfer, or one `evaluate!` call recorded in the cache (`MDR-0012`, `ADR-0016`). |
| `_transfer_sample!` | `src/optim/transfer_optimization.jl` | Cached Stage A sample evaluation: `_transfer_eval!` plus the certified-slab prefilter (a covered transfer records its exact `-Inf` sentinel without an `evaluate!` call) and the sampled-sequence append (`MDR-0012`, `ADR-0017`). |
| `_transfer_covered` | `src/optim/transfer_optimization.jl` | Certified-slab membership test of the Stage A prefilter (`ADR-0017`). |
| `_transfer_cover_slabs!` | `src/optim/transfer_optimization.jl` | Adaptive bisection partitioning one Stage A grid-run extent into certified `-Inf` slabs, split at zero and stopped below `TRANSFER_SLAB_MIN_SAMPLES` samples (`ADR-0017`). |
| `_transfer_prepare_slabs!` | `src/optim/transfer_optimization.jl` | Certified-slab partition of every Stage A grid run of `_transfer_search!` before the enumeration loops (`ADR-0017`). |
| `TRANSFER_SLAB_MIN_SAMPLES` | `src/optim/transfer_optimization.jl` | Stop-splitting floor (32 grid samples, the measured `ws_500` break-even) of the slab bisection: below it pointwise evaluation is cheaper than another interval decision (`ADR-0017`). |
| `_transfer_better` | `src/optim/transfer_optimization.jl` | Candidate comparison of the staged transfer search: largest payoff, exact ties broken by the smallest `abs(theta - theta0)`, then the smallest `theta` (`MDR-0012`, `ADR-0016`). |
| `_transfer_search!` | `src/optim/transfer_optimization.jl` | Staged-search driver of `MDR-0012`: Stage A evaluation set in deterministic order deduplicated through the cache with the certified-slab prefilter, Stage B weak-local-maximum and equal-payoff-plateau detection with one bounded `maximize_1d` refinement per plateau representative, and best-candidate selection under the tie rule; methods take a `TransferSearchScratch` (with an interval certifier) or a caller-owned cache (tests, no prefilter), so the search contract is probeable through the cache (`ADR-0016`, `ADR-0017`). |
| `_transfer_local_search!` | `src/optim/transfer_optimization.jl` | Feasibility-guided production driver of `MDR-0016`: anchors and the sparse `TRANSFER_EXPLORE_OFFSETS` ladder (one ladder when the anchors overlap), conditional `TRANSFER_ADAPTIVE_OFFSET` probes, one seeded guidance refinement and one strictly-improving true-payoff refinement, selection over every finite cached record; returns the best candidate found within the record budget (`MDR-0016`, `ADR-0021`). |
| `TRANSFER_EXPLORE_OFFSETS` | `src/optim/transfer_optimization.jl` | Six sparse exploration offsets (0.0001, 0.001, 0.003 near-anchor; 0.03, 0.1, 0.3 remote) on both sides of each production anchor (`MDR-0016`). |
| `TRANSFER_ANCHOR_OVERLAP` | `src/optim/transfer_optimization.jl` | Anchor-overlap threshold (0.002) of the production ladder: below it the `0.0` and `theta0` ladders coincide and only one ladder is enumerated (`MDR-0016`). |
| `TRANSFER_GUIDANCE_MIN` | `src/optim/transfer_optimization.jl` | Minimum normalized guidance (-2e-5) of a refined production peak: weak maxima below the floor are left unrefined candidates (`MDR-0016`). |
| `TRANSFER_ADAPTIVE_OFFSET` | `src/optim/transfer_optimization.jl` | Adaptive probe offset (0.0003), sampled on one side of one anchor only when guidance at +/- 0.001 reaches `TRANSFER_GUIDANCE_MIN` and exceeds guidance at +/- 0.0001 (`MDR-0016`). |
| `TRANSFER_GUIDANCE_REFINEMENTS` | `src/optim/transfer_optimization.jl` | Maximum guidance weak peaks refined (1), plateau collapsed nearest to status, ranked by guidance (`MDR-0016`). |
| `TRANSFER_MAX_REFINEMENTS` | `src/optim/transfer_optimization.jl` | Maximum strictly improving finite-payoff candidates refined (1), ranked by the unchanged candidate order; skipped entirely when no candidate beats status (`MDR-0016`). |
| `TRANSFER_REFINE_MAX_ITER` | `src/optim/transfer_optimization.jl` | Production Brent iteration guard (6), at most 6 new probes per refinement; cached seeds and endpoints do not add calls (`MDR-0016`). |
| `TRANSFER_SEARCH_MAX_EVALS` | `src/optim/transfer_optimization.jl` | Worst-case record budget 44, including the status seed: 32 Stage A records plus 12 refinement iteration probes (`MDR-0016`). |
| `TRANSFER_COARSE_STEP` | `src/optim/transfer_optimization.jl` | Discovery-only coarse grid spacing (1.0e-3) of the full-domain Stage A grid `-1.0:TRANSFER_COARSE_STEP:1.0` of `_transfer_search!` (`MDR-0012`, `MDR-0014`); production no longer scans it (`MDR-0016`). |
| `TRANSFER_FINE_STEP` | `src/optim/transfer_optimization.jl` | Discovery-only fine anchor-window grid spacing (1.0e-4) of the `MDR-0014` tiered Stage A sample set (`MDR-0012`, `MDR-0014`). |
| `TRANSFER_FINE_STEPS` | `src/optim/transfer_optimization.jl` | Discovery-only fine-window half-width in samples (20, giving `+/- 0.002` around the anchors) of the tiered Stage A sample set (`MDR-0014`). |
| `TRANSFER_REFINE_TOL` | `src/optim/transfer_optimization.jl` | Bounded-Brent argument tolerance (1.0e-5) of the `_transfer_search!` plateau refinements and the `_transfer_local_search!` peak refinements, unchanged in both modes; callers must supply a finite positive value (`MDR-0012`, `MDR-0016`). |
| `_transfer_gains` | `src/optim/transfer_optimization.jl` | The two utility gains of `nash_product` at one solved transfer, computed exactly once per evaluation and shared by `_nash_from_gains` and the guidance values (`MDR-0016`, `ADR-0021`). |
| `_nash_from_gains` | `src/optim/transfer_optimization.jl` | Nash product of the two utility gains: their product when both are finite and non-negative, else `-Inf`; unchanged payoff arithmetic of `nash_product` (`MDR-0014`, `MDR-0016`). |
| `_get_relevant_transfer` | `src/resources/utility_functions.jl` | Gender-dispatched relevant transfer of `set-theta`: `theta` for `AgentPayoffParams{Male}`, `-theta` for `AgentPayoffParams{Female}` (the NetLogo sign flip for women), dispatched on the phantom marker instead of an `is_woman` flag (`ADR-0029`). |
| `payoff_params` | `src/systems/household_bargaining.jl` | Build one transient `AgentPayoffParams{G}` from an agent's traits and perceived norms, dispatching the gender marker `::G where {G<:Gender}` (`ADR-0029`). |
| `HOUSEHOLD_BARGAIN_CHUNK` | `src/systems/household_bargaining.jl` | Households per chunk (4) of the `set_theta!` household loop, shared by the serial path and the bounded worker tasks; chunking origin `ADR-0014`, value re-confirmed by measurement under `ADR-0023`. |
| `HOUSEHOLD_BARGAIN_SERIAL_CUTOFF` | `src/systems/household_bargaining.jl` | Serial crossover (8) of the `:auto` schedule of `set_theta!`: on multithreaded runs a household group of at most this size runs the direct serial path instead of the bounded worker tasks; selected from the 8-thread small-population crossover measurements (see `benchmark/scheduling_tuning.md` and `ADR-0023`). |
| `set_theta!` | `src/systems/household_bargaining.jl` | World loop: extract the household components with `Ark.Query`, run the transfer stage, and commit the bargained hours, transfer, and both partners' committed-bundle `CommittedUtility` observations (evaluated from the prepared parameters via `individual_utility` right after `bargain_transfer` returns; `MDR-0019`, `ADR-0026`); the shared per-chunk closure over `(chunk_range, spouse_seen, scratch)` runs on the direct serial path or on bounded worker tasks pulling chunk indices from a shared atomic cursor, selected by the `schedule` keyword (`:auto` is serial at one thread or at most `HOUSEHOLD_BARGAIN_SERIAL_CUTOFF` households) with `chunk` households per chunk (`ADR-0023`). |
| `update_old_working_time_and_transfer!` | `src/systems/statistics.jl` | Lag copy of `update-statistics`: copy `current` to `old` for `WorkingTime` and `TransferToWoman` on every agent carrying both `WorkingTime` and `TransferToWoman` (`MDR-0007`). |
| `update_global_working_times!` | `src/systems/statistics.jl` | Contemporaneous men/women/gap working-time means of `update-statistics` into `WorkingTimeStats`; kept unchanged as the standalone reducer for minimal worlds (the tick runs `update_observer_stats!` instead, see `MDR-0022`) (`MDR-0007`). |
| `update_observer_stats!` | `src/systems/statistics.jl` | Fused observer snapshot of one tick: two serial gender-filtered `Ark.Query` reductions in the historical women-then-men order with sequential scalar accumulators in the deterministic query batch/index order (the working-time accumulation bitwise-equal to `update_global_working_times!` on full-model worlds), writing `WorkingTimeStats`, `PreferenceStats`, `UtilityStats`, and `TransferStats` at the end and throwing the `MDR-0007` empty-gender `ArgumentError` before publishing anything (`MDR-0019`, `MDR-0020`, `MDR-0021`, `MDR-0022`, `ADR-0026`). |
| `update_preferences` | `src/systems/preferences.jl` | Clipped adaptation of `PreferencePrivate` toward own working time. |
| `Shock` | `src/resources/shock.jl` | Abstract dispatch root of the shock-mode resources; never a field or resource type (`MDR-0009`, `ADR-0011`). |
| `WageShock` | `src/resources/shock.jl` | Wage-shock mode resource with `start` and `depreciation` (`MDR-0009`, `ADR-0011`). |
| `PreferenceShock` | `src/resources/shock.jl` | Preference-shock mode resource with `start`, `depreciation`, `delta_men`, and `delta_woman` (`MDR-0009`, `ADR-0011`). |
| `WageGrowth` | `src/resources/shock.jl` | Gap-closing wage-growth resource with `rate`; ported but unscheduled (`MDR-0009`, `ADR-0011`). |
| `DirectlyAffected` | `src/components.jl` | Empty tag marking the wage-shock target sets drawn at setup (`MDR-0009`, `ADR-0011`). |
| `CommittedUtility` | `src/components.jl` | Immutable single-`Float64` committed-bundle utility observation written by `set_theta!` and aggregated by `update_observer_stats!`; evaluation state, not solver scratch (the `CurrentUtility` placeholder of `MDR-0018` stays removed) (`MDR-0019`, `ADR-0026`). |
| `PreferenceStats` | `src/resources/observers.jl` | Mutable per-sex pre-adaptation preference means, written by `update_observer_stats!` and read by the `preference_men`/`preference_women` metrics (`MDR-0020`, `ADR-0026`). |
| `UtilityStats` | `src/resources/observers.jl` | Mutable per-sex committed-utility means over the `CommittedUtility` observations (non-finite values propagate), written by `update_observer_stats!` and read by the `utility_men`/`utility_women` metrics (`MDR-0019`, `ADR-0026`). |
| `TransferStats` | `src/resources/observers.jl` | Mutable women-only contemporaneous transfer mean (`global-mean-transfer` of NetLogo `update-statistics`), written by `update_observer_stats!` and read by the `transfer_mean` metric (`MDR-0021`, `ADR-0026`). |
| `WAGE_CUT` | `src/systems/shocks.jl` | Kept wage fraction (0.6) for directly-affected agents at shock start (`MDR-0009`). |
| `select_affected!` | `src/systems/shocks.jl` | Setup-only draw of the `DirectlyAffected` sets per sex with a partial Fisher-Yates shuffle (`MDR-0009`). |
| `_tag_affected!` | `src/systems/shocks.jl` | Partial Fisher-Yates helper of `select_affected!` that tags the drawn agents (`MDR-0009`). |
| `start_shock!` | `src/systems/shocks.jl` | One-off shock start: save baselines for all turtles, then cut or shift (`MDR-0009`). |
| `recover_shock!` | `src/systems/shocks.jl` | Per-tick exponential recovery toward baselines with the no-overshoot guard (`MDR-0009`). |
| `update_shocks!` | `src/systems/shocks.jl` | Tick scheduler dispatching `tick == start` to `start_shock!` and `tick > start` to `recover_shock!` per present resource (`MDR-0009`). |
| `update_wages!` | `src/systems/shocks.jl` | Gap-closing wage growth for women; ported but unscheduled (`MDR-0009`). |
| `AbstractModel` | `src/runtime/model_interface.jl` | Dispatch root of the model bindings; bindings implement the six model hooks (see `ADR-0012`). |
| `MODEL_REGISTRY` | `src/runtime/model_interface.jl` | Specification `model.name` to model type mapping used by `resolve_model` (see `ADR-0012`). |
| `resolve_model` | `src/runtime/model_interface.jl` | Registry lookup throwing `ArgumentError` with the sorted registered names (see `ADR-0012`). |
| `model_name` | `src/runtime/model_interface.jl` | Model hook returning the specification name of a binding (see `ADR-0012`). |
| `parse_model_config` | `src/runtime/model_interface.jl` | Model hook validating the `[model]` keys into a resolved config, aggregating via `RunSpecError` (see `ADR-0012`). |
| `setup_world` | `src/runtime/model_interface.jl` | Model hook constructing and initializing a runnable world, named after NetLogo `setup` (see `ADR-0012`). |
| `step_model!` | `src/runtime/model_interface.jl` | Model hook executing one tick with the NetLogo `ticks` count at `go` entry (see `ADR-0012`). |
| `model_metrics` | `src/runtime/model_interface.jl` | Model hook returning the metric name to world function mapping (see `ADR-0012`); the `GenderNormsModel` binding returns the eight observer metrics (`working_time_*`, `preference_*`, `utility_*`, `transfer_mean`, see `MDR-0022` and `ADR-0026`). |
| `config_to_dict` | `src/runtime/model_interface.jl` | Model hook echoing the resolved config as a TOML-compatible dict (see `ADR-0012`). |
| `RuntimeConfig` | `src/runtime/run_spec.jl` | Immutable runtime section carrying the tick budget (see `ADR-0012`). |
| `OutputSpec` | `src/runtime/run_spec.jl` | Immutable selection of one logging backend with its args (see `ADR-0012`). |
| `LoggingConfig` | `src/runtime/run_spec.jl` | Immutable logging section with metric names and outputs (see `ADR-0012`). |
| `RunSpec` | `src/runtime/run_spec.jl` | Immutable validated run specification built by `parse_spec` (see `ADR-0012`). |
| `RunSpecError` | `src/runtime/run_spec.jl` | Aggregated specification failure carrying one problem line per issue (see `ADR-0012`). |
| `Base.showerror` | `src/runtime/run_spec.jl` | `RunSpecError` rendering as `invalid run specification:` plus `- ` lines (see `ADR-0012`). |
| `parse_spec` | `src/runtime/run_spec.jl` | Validation entry point building a `RunSpec` or throwing one `RunSpecError` (see `ADR-0012`). |
| `load_spec` | `src/runtime/run_spec.jl` | `TOML.parsefile` plus `parse_spec` with single-line load failures (see `ADR-0012`). |
| `spec_to_dict` | `src/runtime/run_spec.jl` | TOML-printable echo of a `RunSpec` in the accepted input shape (see `ADR-0012`). |
| `_key_problems` | `src/runtime/run_spec.jl` | Unknown-key problem lines reused by model bindings (see `ADR-0012`). |
| `RunStatus` | `src/runtime/run_result.jl` | Run outcome enum: `RUN_SUCCESS` or `RUN_FAILURE` (see `ADR-0012`). |
| `RUN_SUCCESS` | `src/runtime/run_result.jl` | `RunStatus` value for a run completing every tick (see `ADR-0012`). |
| `RUN_FAILURE` | `src/runtime/run_result.jl` | `RunStatus` value for a run stopped by a recorded error (see `ADR-0012`). |
| `RunInfo` | `src/runtime/run_result.jl` | Run start description passed to `run_started!` (see `ADR-0012`). |
| `RunResult` | `src/runtime/run_result.jl` | In-memory record of a finished run collected by `run` (see `ADR-0012`). |
| `is_success` | `src/runtime/run_result.jl` | Status check returning true exactly on `RUN_SUCCESS` (see `ADR-0012`). |
| `RunContext` | `src/runtime/run_context.jl` | Non-parametric world resource with run id, spec, model, metrics, loggers, RNG (see `ADR-0012`). |
| `RunLogger` | `src/runtime/logging.jl` | Abstract logging sink interface with no-op hooks (see `ADR-0012`). |
| `run_started!` | `src/runtime/logging.jl` | Logger hook notified once when a run begins (see `ADR-0012`). |
| `metrics_recorded!` | `src/runtime/logging.jl` | Logger hook notified after every executed tick (see `ADR-0012`). |
| `run_finished!` | `src/runtime/logging.jl` | Logger hook notified once with the finished `RunResult` (see `ADR-0012`). |
| `LOG_OUTPUT_TYPES` | `src/runtime/logging.jl` | Registered logging output backend names (see `ADR-0012`). |
| `validate_output_spec` | `src/runtime/logging.jl` | Backend argument validation dispatching on `Val{Symbol(type)}` (see `ADR-0012`). |
| `build_logger` | `src/runtime/logging.jl` | Backend construction dispatching on `Val{Symbol(type)}` (see `ADR-0012`). |
| `TomlLogger` | `src/runtime/logging.jl` | File backend writing `<directory>/<run-id>/run.toml` (see `ADR-0012`). |
| `_write_run_record` | `src/runtime/logging.jl` | Internal writer of the `[run]`, `[spec]`, `[metrics]` record (see `ADR-0012`). |
| `create_world` | `src/runtime/runner.jl` | Initialization from a `RunSpec` with the seeded RNG and `RunContext` (see `ADR-0012`). |
| `add_logger!` | `src/runtime/runner.jl` | Appends a programmatic backend to the world `RunContext` (see `ADR-0012`). |
| `run` | `src/runtime/runner.jl` | Module-local execution entry point (not `Base.run`), one run per world (see `ADR-0012`). |
| `GenderNormsModel` | `src/runtime/gender_norms_model.jl` | `AbstractModel` binding of this package, registered as `"gender_norms"` (see `ADR-0012`). |
| `GenderNormsConfig` | `src/runtime/gender_norms_model.jl` | Validated model-specific configuration: properties, gendered trait means, and utility config (see `ADR-0012`). |
| `_parse_network_table` | `src/runtime/gender_norms_model.jl` | Parse one `[model.network]` table into a `NetworkSpec` with per-type keys (see `ADR-0012`). |
| `_parse_utility_table` | `src/runtime/gender_norms_model.jl` | Parse one `[model.utility]` table into a `UtilityConfig`, with `beta` only for `ces` (see `ADR-0012`). |
| `_parse_gender_pair` | `src/runtime/gender_norms_model.jl` | Parse one `men`/`women` specification table with range checks (see `ADR-0012`). |
| `_network_to_dict` | `src/runtime/gender_norms_model.jl` | Echo one `NetworkSpec` as its `[model.network]` table shape (see `ADR-0012`). |
| `_utility_to_dict` | `src/runtime/gender_norms_model.jl` | Echo one `UtilityConfig` as its `[model.utility]` table shape (see `ADR-0012`). |
