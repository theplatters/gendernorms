# Model processes

Mapping of NetLogo procedures in `gender_model_shocks_preferences.nlogox` to
their ODD section and Julia counterpart(s) in `src/`.

| NetLogo procedure | ODD section | Julia symbol(s) | File | Status |
| --- | --- | --- | --- | --- |
| `setup` | Initialization (`setup`, `set-initials-*`) | `initialize_household`, `get_agent`, `get_woman`, `get_men`, `generate_social_network` | `src/systems/initialisation.jl` | partial: agent creation and pairing ported, CSV import, specific-couple override, subgroup and affected sets missing |
| `generate-network` | Network formation | `generate`, `generate_similarity`, `sample_nodes` | `src/resources/social_network.jl` | ported |
| `generate-homophilic-network` | Network formation | `generate_homophily`, `sample_nodes` | `src/resources/social_network.jl` | ported |
| `choose-bundle` | Labour best response | `mutual_best_response` plus `best_response_1d` | `src/systems/household_bargaining.jl`, `src/resources/utility_functions.jl` | ported with documented deviation, see `MDR-0002` |
| `calculate-utility` | Norm perception; Material utility and conformity multiplier | `material`, `individual_utility`; norm perception: `calculate_norm_perception!`, `norm_means`, `norm_penalty`, `agent_payoff_params`, `norm_global_means` | `src/resources/utility_functions.jl`, `src/systems/norm_perception.jl` | partial: utility evaluation and norm perception implemented, not yet scheduled in a `go` loop |
| `calculate-utility` (norm perception system) | Norm perception (`calculate-utility`) | `norm_global_means`, `norm_means`, `norm_penalty`, `calculate_norm_perception!`, `agent_payoff_params` | `src/systems/norm_perception.jl` | ported, see `MDR-0004` |
| `calculate-payoff` | Transfer bargaining | none (only the `Theta` component exists) | `src/components.jl` | not ported |
| `set-theta` | Transfer bargaining | none (only the `Theta` component exists) | `src/components.jl` | not ported |
| `start-shock` | Shocks | none (only `ShockConfig` fields exist, file not included) | `src/resources/shock.jl` | unwired |
| `end-shock` | Shocks | none (only `ShockConfig` fields exist, file not included) | `src/resources/shock.jl` | unwired |
| `update-preferences` | Endogenous preference adaptation and wage growth | none (only `ShockConfig.lambda` exists, file not included) | `src/resources/shock.jl` | not ported |
| `update-wages` | Endogenous preference adaptation and wage growth | none (only `ShockConfig.wage_growth` exists, file not included) | `src/resources/shock.jl` | not ported |
| `update-statistics` | Statistics | `WorkingTimeStats` | `src/resources/observers.jl` | stub: struct declared, never computed or updated |
| `choose_bundles` (Julia stub, no NetLogo namesake) | Labour best response; Transfer bargaining | `choose_bundles(world)` | `src/systems/household_bargaining.jl` | stub: empty loop body with typo `TranferToWoman` (should be `TransferToWoman`), a latent runtime error |
