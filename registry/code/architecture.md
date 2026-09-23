# Architecture

This file maps every Julia source file under `src/` to its layer,
responsibility, and wiring status. It is normative: the table below
is the single source of truth for where code lives.

## Layers

The package uses the layering `components` -> `resources` -> `systems` -> `runtime`.

- `components`: plain data structs used as Ark ECS components.
  No behaviour, no dependencies on other layers.
- `resources`: shared configuration, utility functions, network
  construction, observers, and properties. May depend on `components`.
- `systems`: initialisation and model dynamics that operate on the
  Ark world using `components` and `resources`. May depend on both
  layers below it.
- `runtime`: run specification, run lifecycle, logging, and model
  binding. May depend on every layer below it.
- Dependency direction is downward only: `runtime` may use `systems`,
  `resources`, and `components`; `systems` may use `resources`
  and `components`; `resources` may use `components`; `components`
  must not depend on any layer above it. No include cycles.

## Module include order

The include list in `src/GenderNorms.jl` defines the load order.
It currently reads, in this exact order:

1. `src/components.jl`
2. `src/resources/utility_functions.jl`
3. `src/systems/household_bargaining.jl`
4. `src/resources/social_network.jl`
5. `src/resources/observers.jl`
6. `src/resources/properties.jl`
7. `src/resources/shock.jl`
8. `src/systems/initialisation.jl`
9. `src/systems/statistics.jl`
10. `src/systems/shocks.jl`
11. `src/systems/preferences.jl`
12. `src/systems/norm_perception.jl`
13. `src/runtime/model_interface.jl`
14. `src/runtime/run_spec.jl`
15. `src/runtime/run_result.jl`
16. `src/runtime/logging.jl`
17. `src/runtime/run_context.jl`
18. `src/runtime/runner.jl`
19. `src/runtime/gender_norms_model.jl`

The module root is `src/GenderNorms.jl`.

## File map

| File | Layer | Responsibility | Status |
| ---- | ----- | -------------- | ------ |
| `src/GenderNorms.jl` | module root | Declares module `GenderNorms`, imports (`Ark`, `Graphs`, `Random`, `Dates`, `TOML`, `UUIDs`, `Distributions.Normal`), and include list | Included |
| `src/main.jl` | entry point | Standalone entry point, currently empty | Empty standalone file |
| `src/components.jl` | components | Ark ECS components as plain structs: gender, working time, transfers, spouse, wage, preferences, conformism, utility, `NormParameter`, `PerceptionNormDivisionOfLabor`, `Lambda`, `DirectlyAffected` | Included |
| `src/resources/utility_functions.jl` | resources | Utility specifications and payoff functions: `UtilitySpec` subtypes, `UtilityConfig`, the transient `AgentPayoffParams` parameter object of `mutual_best_response` and `individual_utility`, `material`, `individual_utility`, the in-repo Brent search `maximize_1d` with its seeded variant and the `_brent_maximize` core, the seeded `best_response_1d`, and the solver constants `BEST_RESPONSE_TOL` and `BEST_RESPONSE_WINDOW` | Included |
| `src/resources/social_network.jl` | resources | Network specifications and graph construction: `NetworkSpec` subtypes, `SocialNetwork`, `generate` methods, similarity and homophily builders | Included |
| `src/resources/observers.jl` | resources | Observer structs for aggregate working-time statistics | Included |
| `src/resources/properties.jl` | resources | Model properties and run state: the non-parametric `ModelProperties` resource that carries the `NetworkSpec` (`ADR-0010`), `PaidTime`, `MeanWage`, `MeanPreference`, `InitialConformism`, `ProbeCouple` | Included |
| `src/resources/shock.jl` | resources | Shock-mode resources: the abstract dispatch root `Shock` plus the concrete `WageShock`, `PreferenceShock`, and `WageGrowth` resources (see `MDR-0009`, `ADR-0011`) | Included |
| `src/systems/household_bargaining.jl` | systems | Household bargaining dynamics: the pure solvers `mutual_best_response` (labour stage, port of `choose-bundle`), `bargain_transfer` with the `TRANSFER_TOL` tolerance and the `maximize_1d` search plus the helpers `outside_options`, `equilibrium_payoff`, `nash_product`, and `payoff_params` (transfer stage, port of `set-theta` and `calculate-payoff`), and the Query-based world loop `set_theta!`, which extracts the components, builds the transient `AgentPayoffParams`, and commits the bargained hours and transfer | Included |
| `src/systems/initialisation.jl` | systems | Model setup: household creation, trait draws, and social network construction from the world's `ModelProperties` with an explicit caller-provided `rng` (`ADR-0010`) | Included |
| `src/systems/statistics.jl` | systems | Statistics core (port of `update-statistics`, see `MDR-0007`): the lag copy `update_old_working_time_and_transfer!` and the contemporaneous men/women/gap means `update_global_working_times!` into `WorkingTimeStats` | Included |
| `src/systems/shocks.jl` | systems | Shock dynamics (port of `start-shock` and `end-shock`, see `MDR-0009`): the `WAGE_CUT` factor, `select_affected!`, `start_shock!`, `recover_shock!`, the `update_shocks!` tick scheduler, and the ported-but-unscheduled `update_wages!` | Included |
| `src/systems/preferences.jl` | systems | Preference dynamics: `update_preferences`, the clipped adaptation of `PreferencePrivate` toward own working time | Included |
| `src/systems/norm_perception.jl` | systems | Norm perception port of `calculate-utility`: `norm_global_means`, `norm_means`, `norm_penalty`, and `calculate_norm_perception!` | Included |
| `src/runtime/model_interface.jl` | runtime | Model binding interface: the `AbstractModel` dispatch root, the `MODEL_REGISTRY` name mapping with `resolve_model`, and the six model hooks `model_name`, `parse_model_config`, `setup_world`, `step_model!`, `model_metrics`, and `config_to_dict` (see `ADR-0012`) | Included |
| `src/runtime/run_spec.jl` | runtime | Run specification: the immutable `RuntimeConfig`, `OutputSpec`, `LoggingConfig`, and `RunSpec` types, the aggregated `RunSpecError` with its `Base.showerror` rendering, the `parse_spec` validation entry point, `load_spec` file loading, the `spec_to_dict` round-trip echo, and the `_key_problems` unknown-key helper reused by model bindings (see `ADR-0012`) | Included |
| `src/runtime/run_result.jl` | runtime | Run outcome records: the `RunStatus` enum with `RUN_SUCCESS` and `RUN_FAILURE`, the `RunInfo` start description for logger hooks, the `RunResult` in-memory record, and the `is_success` status check (see `ADR-0012`) | Included |
| `src/runtime/logging.jl` | runtime | Logging sinks: the `RunLogger` interface with the no-op `run_started!`, `metrics_recorded!`, and `run_finished!` hooks, the `LOG_OUTPUT_TYPES` backend registry with `validate_output_spec` and `build_logger` dispatch, and the `TomlLogger` file backend with its `_write_run_record` writer (see `ADR-0012`) | Included |
| `src/runtime/run_context.jl` | runtime | Per-run mutable state: the non-parametric `RunContext` world resource carrying run id, spec, model, config, metric functions, loggers, and the seeded RNG (see `ADR-0012`) | Included |
| `src/runtime/runner.jl` | runtime | World creation and execution: `create_world` initialization with the seeded RNG, `add_logger!` programmatic backends, and the module-local `run` entry point with its record-or-rethrow failure semantics (see `ADR-0012`) | Included |
| `src/runtime/gender_norms_model.jl` | runtime | Model binding for this package: `GenderNormsModel` registered as `"gender_norms"` with its `GenderNormsConfig`, the `setup_world` setup port, the `step_model!` go port (see `MDR-0010`), the working-time `model_metrics`, the `config_to_dict` echo, and the `_parse_network_table`, `_parse_utility_table`, `_parse_gender_pair`, `_network_to_dict`, and `_utility_to_dict` table helpers (see `ADR-0012`) | Included |

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
| `calculate_norm_perception!` | `src/systems/norm_perception.jl` | Compute and store `PerceptionNormDivisionOfLabor` and `NormParameter` for every agent. |
| `outside_options` | `src/systems/household_bargaining.jl` | Zero-transfer outside options of both partners: the first lines of `set-theta`. |
| `maximize_1d` | `src/resources/utility_functions.jl` | In-repo Brent 1-D maximization with the seeded variant: the continuous solver behind `best_response_1d` and `bargain_transfer`. |
| `_brent_maximize` | `src/resources/utility_functions.jl` | Core Brent search behind `maximize_1d`, returning the best finite sample. |
| `best_response_1d` | `src/resources/utility_functions.jl` | Labour best response on `[0, 1]`, seeded at the current hours with `BEST_RESPONSE_TOL`/`BEST_RESPONSE_WINDOW` (`MDR-0002`). |
| `nash_product` | `src/systems/household_bargaining.jl` | Nash product of the two utility gains over the outside options; `-Inf` when a gain is negative (port of `calculate-payoff`). |
| `equilibrium_payoff` | `src/systems/household_bargaining.jl` | Labour equilibrium at one transfer plus its Nash product. |
| `bargain_transfer` | `src/systems/household_bargaining.jl` | Continuous transfer search: `maximize_1d` Brent maximization of the Nash product over `[-1, 1]` with the `TRANSFER_TOL` tolerance and the status quo as the fallback. |
| `payoff_params` | `src/systems/household_bargaining.jl` | Build one transient `AgentPayoffParams` from an agent's traits and perceived norms. |
| `set_theta!` | `src/systems/household_bargaining.jl` | World loop: extract the household components with `Ark.Query`, run the transfer stage, and commit the bargained hours and transfer. |
| `update_old_working_time_and_transfer!` | `src/systems/statistics.jl` | Lag copy of `update-statistics`: copy `current` to `old` for `WorkingTime` and `TransferToWoman` on every agent carrying both `WorkingTime` and `TransferToWoman` (`MDR-0007`). |
| `update_global_working_times!` | `src/systems/statistics.jl` | Contemporaneous men/women/gap working-time means of `update-statistics` into `WorkingTimeStats` (`MDR-0007`). |
| `update_preferences` | `src/systems/preferences.jl` | Clipped adaptation of `PreferencePrivate` toward own working time. |
| `Shock` | `src/resources/shock.jl` | Abstract dispatch root of the shock-mode resources; never a field or resource type (`MDR-0009`, `ADR-0011`). |
| `WageShock` | `src/resources/shock.jl` | Wage-shock mode resource with `start` and `depreciation` (`MDR-0009`, `ADR-0011`). |
| `PreferenceShock` | `src/resources/shock.jl` | Preference-shock mode resource with `start`, `depreciation`, `delta_men`, and `delta_woman` (`MDR-0009`, `ADR-0011`). |
| `WageGrowth` | `src/resources/shock.jl` | Gap-closing wage-growth resource with `rate`; ported but unscheduled (`MDR-0009`, `ADR-0011`). |
| `DirectlyAffected` | `src/components.jl` | Empty tag marking the wage-shock target sets drawn at setup (`MDR-0009`, `ADR-0011`). |
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
| `model_metrics` | `src/runtime/model_interface.jl` | Model hook returning the metric name to world function mapping (see `ADR-0012`). |
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
