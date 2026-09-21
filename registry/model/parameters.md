# Model parameters

Mapping of every parameter in the ODD table "Parameters, experiments, and
output" (`odd_model_description.typ`) to its Julia location and default.
NetLogo defaults are Interface-tab slider values in
`gender_model_shocks_preferences.nlogox`.

| Parameter | NetLogo default | Julia location | Julia default | Status/notes |
| --- | --- | --- | --- | --- |
| `number-agents-each-type` | 400 | `src/resources/properties.jl`: `ModelProperties.agents_per_gender` | 400 | ported |
| `wage-female` | 0.9 | `src/resources/properties.jl`: `MeanWage.woman` | 0.9 | ported |
| `wage-male` | 1.0 | `src/resources/properties.jl`: `MeanWage.men` | 1.0 | ported |
| `preference-private-mean-male` | 0.45 | `src/resources/properties.jl`: `MeanPreference.men` | 0.45 | ported, see `MDR-0006` |
| `preference-private-mean-female` | 0.48 | `src/resources/properties.jl`: `MeanPreference.woman` | 0.48 | ported |
| `conformism-female` | 10.0 | `src/resources/properties.jl`: `InitialConformism.woman` | 10.0 | ported |
| `conformism-male` | 10.0 | `src/resources/properties.jl`: `InitialConformism.men` | 10.0 | ported |
| `std-dev-values` | 0.2 | `src/resources/properties.jl`: `ModelProperties.std_dev` | 0.2 | ported |
| `norm-paid-time-female` | 36 (percent) | `src/resources/properties.jl`: `PaidTime.woman` | 0.36 (fraction) | ported, rescaled percent to fraction |
| `norm-paid-time-male` | 77 (percent) | `src/resources/properties.jl`: `PaidTime.men` | 0.77 (fraction) | ported, rescaled percent to fraction |
| `initial-transfer` | 0.0 | `src/resources/properties.jl`: `ModelProperties.initial_transfer` | 0.0 | ported |
| `utility-function` | CES | `src/resources/utility_functions.jl`: `UtilityConfig.func` | `CES()` | ported, all four specs exist (`Additive`, `CES`, `Multiplicative`, `MultiplicativeWeighted`) |
| `CES_beta` | 0.5 | `src/resources/utility_functions.jl`: `CES.beta` | 0.5 | ported |
| `weight-working-time-self` | 1 | `src/resources/utility_functions.jl`: `UtilityConfig.w_self` | 1.0 | ported |
| `weight-transfer` | 1 | `src/resources/utility_functions.jl`: `UtilityConfig.w_transfer` | 1.0 | ported |
| `weight-working-time-partner` | 1 | `src/resources/utility_functions.jl`: `UtilityConfig.w_partner` | 1.0 | ported |
| `network-structure` | watts-strogatz | `src/resources/properties.jl`: `ModelProperties.network` | `WattsStrogatz()` | ported, all 7 specs exist in `src/resources/social_network.jl` |
| `random-network-prob` | 0.01 | `src/resources/social_network.jl`: `RandomNetwork.p` | 0.01 | ported |
| `watts-strogatz-neighbors` | 1 | `src/resources/social_network.jl`: `WattsStrogatz.neighbors_per_side` | 1 | ported |
| `watts-strogatz-rewiring` | 0.1 | `src/resources/social_network.jl`: `WattsStrogatz.rewiring` | 0.1 | ported |
| `preferential-attachment-min-degree` | 1 | `src/resources/social_network.jl`: `PreferentialAttachment.m`, `SimilarityNetwork.m`, `HomophilyNetwork.m` | 1 | ported, shared degree parameter on three structs |
| `convergence_epsilon` | 0.001 | `src/systems/household_bargaining.jl`: `mutual_best_response` kwarg `eps` | 1.0e-3 | ported as solver tolerance, see `MDR-0002` |
| `current-delta` | 0.0001 | none (continuous Brent maximization has no step size) | n/a | not ported by design, see `MDR-0002` |
| `lambda` | 0.002 | `src/resources/shock.jl`: `ShockConfig.lambda` | 0.002 | unwired: `shock.jl` is not included in `src/GenderNorms.jl` |
| `shock` | no | `src/resources/shock.jl`: `ShockConfig.shock` | `SHOCK_NO` (undefined `ShockType`) | unwired: undefined type, file not included |
| `shock-start` | 60 | `src/resources/shock.jl`: `ShockConfig.start` | 60 | unwired: file not included in `src/GenderNorms.jl` |
| `shock-depreciation` | 0.005 | `src/resources/shock.jl`: `ShockConfig.depreciation` | 0.005 | unwired: file not included in `src/GenderNorms.jl` |
| `preference-private-shock-male` | 0.0 | `src/resources/shock.jl`: `ShockConfig.pref_shock_male` | 0.0 | unwired: file not included in `src/GenderNorms.jl` |
| `preference-private-shock-female` | 0.0 | `src/resources/shock.jl`: `ShockConfig.pref_shock_female` | 0.0 | unwired: file not included in `src/GenderNorms.jl` |
| `perc-affected-male` | 0 | `src/resources/shock.jl`: `ShockConfig.perc_male` | 0.0 | unwired: file not included in `src/GenderNorms.jl` |
| `perc-affected-female` | 30 | `src/resources/shock.jl`: `ShockConfig.perc_female` | 30.0 | unwired: file not included in `src/GenderNorms.jl` |
| `wage-growth-rate` | 0.0 | `src/resources/shock.jl`: `ShockConfig.wage_growth` | 0.0 | unwired: file not included in `src/GenderNorms.jl` |
| `fixed-rs`, `random-seed-fixed` | off, 10 | none (`src/systems/initialisation.jl` uses `Random.default_rng()`) | n/a | not ported, no seeded RNG path |
| `specific-couple`, `*-in-question` | off | `src/resources/properties.jl`: `ProbeCouple` (declared, never used) | wage 2.0/2.0, pref 0.5/0.5, conformism 1.0/1.0 | unwired probe override |
| `import-csv`, `output-locations` | off | none (no Julia symbol) | n/a | not ported |
