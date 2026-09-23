# Model processes

Mapping of NetLogo procedures in `gender_model_shocks_preferences.nlogox` to
their ODD section and Julia counterpart(s) in `src/`.

| NetLogo procedure | ODD section | Julia symbol(s) | File | Status |
| --- | --- | --- | --- | --- |
| `setup` | Initialization (`setup`, `set-initials-*`) | `initialize_household`, `get_agent`, `get_woman`, `get_men`, `generate_social_network`, `setup_world` | `src/systems/initialisation.jl`, `src/runtime/gender_norms_model.jl` | partial: agent creation and pairing ported, CSV import, specific-couple override, subgroup and affected sets missing |
| `generate-network` | Network formation | `generate`, `generate_similarity`, `sample_nodes` | `src/resources/social_network.jl` | ported |
| `generate-homophilic-network` | Network formation | `generate_homophily`, `sample_nodes` | `src/resources/social_network.jl` | ported |
| `choose-bundle` | Labour best response | `mutual_best_response` plus `best_response_1d` and `maximize_1d` | `src/systems/household_bargaining.jl`, `src/resources/utility_functions.jl` | ported with documented deviation, see `MDR-0002` |
| `calculate-utility` | Norm perception; Material utility and conformity multiplier | `material`, `individual_utility`; norm perception: `calculate_norm_perception!`, `norm_means`, `norm_penalty`, `norm_global_means` | `src/resources/utility_functions.jl`, `src/systems/norm_perception.jl` | partial: utility evaluation and norm perception implemented, not yet scheduled in a `go` loop |
| `calculate-utility` (norm perception system) | Norm perception (`calculate-utility`) | `norm_global_means`, `norm_means`, `norm_penalty`, `calculate_norm_perception!` | `src/systems/norm_perception.jl` | ported, see `MDR-0004` |
| `calculate-payoff` | Transfer bargaining | `nash_product`, `equilibrium_payoff` plus `individual_utility`, `mutual_best_response` | `src/systems/household_bargaining.jl` | ported with documented deviation, see `MDR-0005` |
| `set-theta` | Transfer bargaining | `set_theta!`, `bargain_transfer`, `outside_options`, `payoff_params` | `src/systems/household_bargaining.jl` | ported with documented deviation, see `MDR-0005` |
| `start-shock` | Shocks | `start_shock!`, `recover_shock!`, `update_shocks!` | `src/systems/shocks.jl` (`src/resources/shock.jl` resources) | ported, see `MDR-0009` |
| `end-shock` | Shocks | `start_shock!`, `recover_shock!`, `update_shocks!` | `src/systems/shocks.jl` (`src/resources/shock.jl` resources) | ported, see `MDR-0009` |
| `update-preferences` | Endogenous preference adaptation and wage growth | `update_preferences` | `src/systems/preferences.jl` | partial: adaptation ported and preserving the `pre` shock baseline; the `lambda` default is still 0.5 instead of the NetLogo 0.002 (see `registry/model/discrepancies.md`), `TASK-0004` |
| `update-wages` | Endogenous preference adaptation and wage growth | `update_wages!` | `src/systems/shocks.jl` | ported-but-unscheduled: NetLogo `go` never calls `update-wages`, see `MDR-0009` |
| `update-statistics` | Statistics | `update_old_working_time_and_transfer!`, `update_global_working_times!` | `src/systems/statistics.jl` | partial-core-ported: lag copy plus contemporaneous men/women/gap means, see `MDR-0007`; histories, subgroup means, and `run-time` deferred under `TASK-0001` |
| `go` | Process overview and scheduling | `step_model!` (scheduling `update_shocks!`, `calculate_norm_perception!`, `set_theta!`, `update_old_working_time_and_transfer!`, `update_global_working_times!`, `update_preferences`) | `src/runtime/gender_norms_model.jl` | ported, see `MDR-0010`; `update-wages` stays unscheduled (see `MDR-0009`) and quirk 11 stays deferred under `TASK-0010` |
