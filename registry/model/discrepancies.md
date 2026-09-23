# Model versus code discrepancies and open questions

Concrete discrepancies and unwired items found while mapping the ODD
(`odd_model_description.typ`) and the reference implementation
(`gender_model_shocks_preferences.nlogox`) onto `src/`. Nothing here is
fixed, only recorded. Each item cites evidence as a file with line number or
an ODD section.

| Item | Evidence (file:line or ODD section) | Suggested resolution |
| --- | --- | --- |
| `WorkingTimeStats` core means are computed but histories and subgroup means are missing (`update-statistics` only core-ported) | `src/resources/observers.jl:1-5`; `src/systems/statistics.jl`; ODD Statistics; `MDR-0007` | Port the Statistics remainder under `TASK-0001` |
| `ProbeCouple` (`specific-couple` / `*-in-question` override) is declared but never used | `src/resources/properties.jl:29-36`; ODD Initialization item 7 | Port the probe override in a follow-up, then wire or remove `ProbeCouple` |
| ODD Known implementation quirks items 1-12 are not yet reflected as MDRs | ODD Known implementation quirks | Add one MDR per quirk that the port keeps or fixes; `MDR-0003` is the umbrella rule |
| ODD quirk 12: BehaviorSpace experiments reference a `rho` slider absent from the Interface tab | ODD Known implementation quirks item 12; ODD Parameters, experiments, and output | Record whether `rho` is the intended `lambda` in an MDR before porting experiments |
| Infeasibility penalty is `-Inf` in Julia but `-200` in NetLogo | `src/resources/utility_functions.jl:56-58`; ODD Material utility and conformity multiplier | Record under `MDR-0003` whether `-Inf` is an accepted deviation or must become `-200` |
| Norm perception (`calculate_norm_perception!`) and the household bargaining loop (`set_theta!`, `mutual_best_response`, `bargain_transfer`) are implemented but not yet scheduled in a `go` loop | `src/systems/norm_perception.jl`; `src/systems/household_bargaining.jl`; ODD Process overview and scheduling | Wire them into the model loop when `go` is ported |
| NetLogo `lambda` defaults to 0.002 but the used Julia path `ModelProperties.initial_lambda` defaults to 0.5 | `gender_model_shocks_preferences.nlogox` slider `lambda` default 0.002; `src/resources/properties.jl:11` (`initial_lambda` = 0.5) | Record the intended default in an MDR before aligning either side; do not change the default without a record |
| `update_preferences` does not clip the adapted preference to `[0, 1]` (NetLogo applies `max list 0 (min list 1 ...)`) | `gender_model_shocks_preferences.nlogox` `update-preferences`; ODD Endogenous preference adaptation; `src/systems/preferences.jl:11-14` | Add the clip under `TASK-0004`; in-range inputs keep the blend in range, so the gap is latent |
