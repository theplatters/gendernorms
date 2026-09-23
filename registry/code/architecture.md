# Architecture

This file maps every Julia source file under `src/` to its layer,
responsibility, and wiring status. It is normative: the table below
is the single source of truth for where code lives.

## Layers

The package uses the layering `components` -> `resources` -> `systems`.

- `components`: plain data structs used as Ark ECS components.
  No behaviour, no dependencies on other layers.
- `resources`: shared configuration, utility functions, network
  construction, observers, and properties. May depend on `components`.
- `systems`: initialisation and model dynamics that operate on the
  Ark world using `components` and `resources`. May depend on both
  layers below it.
- Dependency direction is downward only: `systems` may use `resources`
  and `components`; `resources` may use `components`; `components`
  must not depend on either layer above it. No include cycles.

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

The module root is `src/GenderNorms.jl`.

## File map

| File | Layer | Responsibility | Status |
| ---- | ----- | -------------- | ------ |
| `src/GenderNorms.jl` | module root | Declares module `GenderNorms`, imports, and include list | Included |
| `src/main.jl` | entry point | Standalone entry point, currently empty | Empty standalone file |
| `src/components.jl` | components | Ark ECS components as plain structs: gender, working time, transfers, spouse, wage, preferences, conformism, utility, `NormParameter`, `PerceptionNormDivisionOfLabor`, `Lambda`, `DirectlyAffected` | Included |
| `src/resources/utility_functions.jl` | resources | Utility specifications and payoff functions: `UtilitySpec` subtypes, `UtilityConfig`, the transient `AgentPayoffParams` parameter object of `mutual_best_response` and `individual_utility`, `material`, `individual_utility`, the in-repo Brent search `maximize_1d` with its seeded variant and the `_brent_maximize` core, the seeded `best_response_1d`, and the solver constants `BEST_RESPONSE_TOL` and `BEST_RESPONSE_WINDOW` | Included |
| `src/resources/social_network.jl` | resources | Network specifications and graph construction: `NetworkSpec` subtypes, `SocialNetwork`, `generate` methods, similarity and homophily builders | Included |
| `src/resources/observers.jl` | resources | Observer structs for aggregate working-time statistics | Included |
| `src/resources/properties.jl` | resources | Model properties and run state: the non-parametric `ModelProperties` resource that carries the `NetworkSpec` (`ADR-0010`), `PaidTime`, `MeanWage`, `MeanPreference`, `InitialConformism`, `ProbeCouple` | Included |
| `src/resources/shock.jl` | resources | Shock-mode resources: the abstract dispatch root `Shock` plus the concrete `WageShock`, `PreferenceShock`, and `WageGrowth` resources (see `MDR-0009`, `ADR-0011`) | Included |
| `src/systems/household_bargaining.jl` | systems | Household bargaining dynamics: the pure solvers `mutual_best_response` (labour stage, port of `choose-bundle`), `bargain_transfer` with the `TRANSFER_TOL` tolerance and the `maximize_1d` search plus the helpers `outside_options`, `equilibrium_payoff`, `nash_product`, and `payoff_params` (transfer stage, port of `set-theta` and `calculate-payoff`), and the Query-based world loop `set_theta!`, which extracts the components, builds the transient `AgentPayoffParams`, and commits the bargained hours and transfer | Included |
| `src/systems/initialisation.jl` | systems | Model setup: household creation, trait draws, and social network construction from the world's `ModelProperties` (`ADR-0010`) | Included |
| `src/systems/statistics.jl` | systems | Statistics core (port of `update-statistics`, see `MDR-0007`): the lag copy `update_old_working_time_and_transfer!` and the contemporaneous men/women/gap means `update_global_working_times!` into `WorkingTimeStats` | Included |
| `src/systems/shocks.jl` | systems | Shock dynamics (port of `start-shock` and `end-shock`, see `MDR-0009`): the `WAGE_CUT` factor, `select_affected!`, `start_shock!`, `recover_shock!`, the `update_shocks!` tick scheduler, and the ported-but-unscheduled `update_wages!` | Included |
| `src/systems/preferences.jl` | systems | Preference dynamics: `update_preferences`, the clipped adaptation of `PreferencePrivate` toward own working time | Included |
| `src/systems/norm_perception.jl` | systems | Norm perception port of `calculate-utility`: `norm_global_means`, `norm_means`, `norm_penalty`, and `calculate_norm_perception!` | Included |

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
