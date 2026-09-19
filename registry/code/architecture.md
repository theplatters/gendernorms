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
7. `src/systems/initialisation.jl`
8. `src/systems/norm_perception.jl`

The module root is `src/GenderNorms.jl`.

## File map

| File | Layer | Responsibility | Status |
| ---- | ----- | -------------- | ------ |
| `src/GenderNorms.jl` | module root | Declares module `GenderNorms`, imports, and include list | Included |
| `src/main.jl` | entry point | Standalone entry point, currently empty | Empty standalone file |
| `src/components.jl` | components | Ark ECS components as plain structs: gender, working time, transfers, spouse, wage, preferences, conformism, utility, theta, `NormParameter`, `PerceptionNormDivisionOfLabor` | Included |
| `src/resources/utility_functions.jl` | resources | Utility specifications and payoff functions: `UtilitySpec` subtypes, `UtilityConfig`, `AgentPayoffParams`, `material`, `individual_utility`, `best_response_1d` | Included |
| `src/resources/social_network.jl` | resources | Network specifications and graph construction: `NetworkSpec` subtypes, `SocialNetwork`, `generate` methods, similarity and homophily builders | Included |
| `src/resources/observers.jl` | resources | Observer structs for aggregate working-time statistics | Included |
| `src/resources/properties.jl` | resources | Model properties and run state: `ModelProperties`, `PaidTime`, `MeanWage`, `MeanPreference`, `InitialConformism`, `ProbeCouple`, `GlobalStats` | Included |
| `src/resources/shock.jl` | resources | Shock configuration struct `ShockConfig`, currently unwired | Excluded, see note below |
| `src/systems/household_bargaining.jl` | systems | Household bargaining dynamics: `mutual_best_response` and `choose_bundles` | Included |
| `src/systems/initialisation.jl` | systems | Model setup: household creation, trait draws, and social network construction | Included |
| `src/systems/norm_perception.jl` | systems | Norm perception port of `calculate-utility`: `norm_global_means`, `norm_means`, `norm_penalty`, `calculate_norm_perception!`, and the `individual_utility` bridge `agent_payoff_params` | Included |

## Registration rule

Every new `.jl` file under `src/` must be added to the module include
list in `src/GenderNorms.jl` at the correct layer position and must be
added as a row to the file-map table above. The only exception is
`src/main.jl`, which is the standalone entry point and is intentionally
not included by the module.

## Excluded files

Excluded from module: `src/resources/shock.jl` is not included by `src/GenderNorms.jl` because it references undefined `ShockType` and `SHOCK_NO` and is therefore unwired dead code until a shock-model decision wires it up.

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
| `norm_means` | `src/systems/norm_perception.jl` | Perceived norms of one agent: same-sex neighbour means plus spouses-of-neighbours working time, with isolated fallbacks. |
| `norm_penalty` | `src/systems/norm_perception.jl` | Norm exponent of `calculate-utility`: weighted squared deviations from the perceived norms. |
| `calculate_norm_perception!` | `src/systems/norm_perception.jl` | Compute and store `PerceptionNormDivisionOfLabor` and `NormParameter` for every agent. |
| `agent_payoff_params` | `src/systems/norm_perception.jl` | Build the `AgentPayoffParams` for `individual_utility` from an entity's network-based norms. |
