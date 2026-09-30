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
| `CES_beta` | 0.5 | `src/resources/utility_functions.jl`: `CES.beta` | 0.5 | ported; the exactly-`0.5` case uses the validated-equivalent sqrt/square `material` form of `MDR-0013` |
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
| `transfer-coarse-step` (solver parameter of the discovery search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_COARSE_STEP` | 1.0e-3 | offline `search=:discovery` only: the full-domain grid of `MDR-0014`; production no longer scans it (`MDR-0016`) |
| `transfer-fine-step` (solver parameter of the discovery search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_FINE_STEP` | 1.0e-4 | fine anchor-window grid spacing of `MDR-0014`, used by `search=:discovery` only (`MDR-0016`) |
| `transfer-fine-steps` (solver parameter of the discovery search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_FINE_STEPS` | 20 | k range, giving the fine window +/- 0.002 around 0 and the current transfer in discovery mode only (`MDR-0016`) |
| `transfer-explore-offsets` (solver parameter of the production search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_EXPLORE_OFFSETS` | 6 sparse offsets 0.0001, 0.001, 0.003, 0.03, 0.1, 0.3 | near-anchor and remote ladder on both signs of each production anchor, no global discovery guarantee (`MDR-0016`) |
| `transfer-anchor-overlap` (solver parameter of the production search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_ANCHOR_OVERLAP` | 0.002 | anchor-overlap threshold: below it one shared ladder replaces the two anchor ladders (`MDR-0016`) |
| `transfer-guidance-min` (solver parameter of the production search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_GUIDANCE_MIN` | -2.0e-5 | minimum normalized guidance of a refined peak (`MDR-0016`) |
| `transfer-adaptive-offset` (solver parameter of the production search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_ADAPTIVE_OFFSET` | 0.0003 | conditional probe restoring a hidden band's refinement bracket (`MDR-0016`) |
| `transfer-guidance-refinements` (solver parameter of the production search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_GUIDANCE_REFINEMENTS` | 1 | cap on refined guidance weak peaks (`MDR-0016`) |
| `transfer-max-refinements` (solver parameter of the production search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_MAX_REFINEMENTS` | 1 | cap on true-payoff refinements (`MDR-0016`) |
| `transfer-refine-max-iter` (solver parameter of the production search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_REFINE_MAX_ITER` | 6 | Brent iteration cap per production bracket (`MDR-0016`) |
| `transfer-search-max-evals` (solver parameter of the production search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_SEARCH_MAX_EVALS` | 44 | includes status seed; outside/status labour solves are separate (`MDR-0016`) |
| `transfer-refine-tol` (solver parameter of the transfer search) | none | `src/systems/household_bargaining.jl`: `TRANSFER_REFINE_TOL` | 1.0e-5 | bounded-Brent argument tolerance, unchanged in both modes; callers must supply a finite positive value (`MDR-0016`) |
| `lambda` | 0.002 | `src/resources/properties.jl`: `ModelProperties.initial_lambda`, via `src/components.jl`: `Lambda.amount` (created in `get_agent`, read by `update_preferences`) | 0.5 (used path; differs from NetLogo 0.002, see discrepancies); `lambda` stays out of the shock files, see `MDR-0009` | partial: the used path is wired but defaults to 0.5, not the NetLogo 0.002 (see discrepancies) |
| `shock` | no | `src/resources/shock.jl`: `WageShock` / `PreferenceShock` resource presence, dispatched by `update_shocks!` in `src/systems/shocks.jl` (neither present is the `no` no-op) | n/a | ported, see `MDR-0009` |
| `shock-start` | 60 | `src/resources/shock.jl`: `WageShock.start`, `PreferenceShock.start` (dispatched by `update_shocks!`) | 60 | ported, see `MDR-0009` |
| `shock-depreciation` | 0.005 | `src/resources/shock.jl`: `WageShock.depreciation`, `PreferenceShock.depreciation` (recovery rate of `recover_shock!`) | 0.005 | ported, see `MDR-0009` |
| `preference-private-shock-male` | 0.0 | `src/resources/shock.jl`: `PreferenceShock.delta_men` (global shift of `start_shock!`) | 0.0 | ported, see `MDR-0009` |
| `preference-private-shock-female` | 0.0 | `src/resources/shock.jl`: `PreferenceShock.delta_woman` (global shift of `start_shock!`) | 0.0 | ported, see `MDR-0009` |
| `perc-affected-male` | 0 | `src/systems/shocks.jl`: `select_affected!` setup argument `perc_male` (never stored, see `MDR-0009`) | 0.0 | ported as a setup argument, see `MDR-0009` |
| `perc-affected-female` | 30 | `src/systems/shocks.jl`: `select_affected!` setup argument `perc_female` (never stored, see `MDR-0009`) | 30.0 | ported as a setup argument, see `MDR-0009` |
| `wage-growth-rate` | 0.0 | `src/resources/shock.jl`: `WageGrowth.rate` (read by `update_wages!` in `src/systems/shocks.jl`) | 0.0 | ported-but-unscheduled: NetLogo `go` never calls `update-wages`, see `MDR-0009` |
| `fixed-rs`, `random-seed-fixed` | off, 10 | none (`src/systems/initialisation.jl` uses `Random.default_rng()`) | n/a | not ported, no seeded RNG path |
| `specific-couple`, `*-in-question` | off | `src/resources/properties.jl`: `ProbeCouple` (declared, never used) | wage 2.0/2.0, pref 0.5/0.5, conformism 1.0/1.0 | unwired probe override |
| `import-csv`, `output-locations` | off | none (no Julia symbol) | n/a | not ported |
