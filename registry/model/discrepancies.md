# Model versus code discrepancies and open questions

Concrete discrepancies and unwired items found while mapping the ODD
(`odd_model_description.typ`) and the reference implementation
(`gender_model_shocks_preferences.nlogox`) onto `src/`. Nothing here is
fixed, only recorded. Each item cites evidence as a file with line number or
an ODD section.

| Item | Evidence (file:line or ODD section) | Suggested resolution |
| --- | --- | --- |
| `MeanPreference.men` is 0.44 but the ODD default for `preference-private-mean-male` is 0.45 | `src/resources/properties.jl:19`; ODD Parameters table | Decide the intended default in an MDR and change one side to match |
| `src/resources/shock.jl` references undefined `ShockType` and `SHOCK_NO`, so the file cannot load | `src/resources/shock.jl:2` | Define the shock-type enum (or reuse the NetLogo chooser strings) in an MDR-backed port of Shocks |
| `src/resources/shock.jl` is not included in the module | `src/GenderNorms.jl:9-16` (no include for `shock.jl`) | Include it once it loads, at the right layer per `registry/code/architecture.md` |
| `Theta` component is declared but never used (`set-theta` / `calculate-payoff` not ported) | `src/components.jl:36-38`; ODD Transfer bargaining | Port Transfer bargaining in a follow-up, then wire or remove `Theta` |
| `WorkingTimeStats` is declared but never computed (`update-statistics` not ported) | `src/resources/observers.jl:1-5`; ODD Statistics | Port Statistics in a follow-up, then wire or remove `WorkingTimeStats` |
| `ProbeCouple` (`specific-couple` / `*-in-question` override) is declared but never used | `src/resources/properties.jl:29-36`; ODD Initialization item 7 | Port the probe override in a follow-up, then wire or remove `ProbeCouple` |
| ODD Known implementation quirks items 1-12 are not yet reflected as MDRs | ODD Known implementation quirks | Add one MDR per quirk that the port keeps or fixes; `MDR-0003` is the umbrella rule |
| ODD quirk 12: BehaviorSpace experiments reference a `rho` slider absent from the Interface tab | ODD Known implementation quirks item 12; ODD Parameters, experiments, and output | Record whether `rho` is the intended `lambda` in an MDR before porting experiments |
| Infeasibility penalty is `-Inf` in Julia but `-200` in NetLogo | `src/resources/utility_functions.jl:56-58`; ODD Material utility and conformity multiplier | Record under `MDR-0003` whether `-Inf` is an accepted deviation or must become `-200` |
| Norm perception (`calculate_norm_perception!`) and the labour solver (`mutual_best_response`) are implemented but not yet scheduled in a `go` loop | `src/systems/norm_perception.jl`; `src/systems/household_bargaining.jl`; ODD Process overview and scheduling | Wire both into the model loop when `go` and the transfer stage are ported |
