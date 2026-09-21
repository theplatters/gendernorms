# Model entities and state variables

Mapping of every entity and state variable in the ODD table "Entities, state
variables, and scales" (`odd_model_description.typ`) to NetLogo
(`gender_model_shocks_preferences.nlogox`) and to Julia (`src/`).

Status vocabulary: `ported`, `partial`, `stub`, `not ported`, `unwired`.
`unwired` means the Julia symbol exists but is not connected to any process.

| Model entity / state variable | NetLogo | Julia (file: symbol/field) | Status | ODD section |
| --- | --- | --- | --- | --- |
| Woman / man agent (breed) | `women`, `men` turtle breeds | `src/components.jl`: `Male`, `Female`; `src/systems/initialisation.jl`: `get_agent` | ported | Entities, state variables, and scales |
| current-working-time | `current-working-time` in [0,1] | `src/components.jl`: `WorkingTime.current` | ported | Entities, state variables, and scales |
| old-working-time | `old-working-time` | `src/components.jl`: `WorkingTime.old` | ported | Entities, state variables, and scales |
| current-transfer-to-woman | `current-transfer-to-woman`, theta in [-1,1] | `src/components.jl`: `TransferToWoman.current` | ported; the man's copy mirrors his wife's at all times (`initialize_household`, `set_theta!`) | Entities, state variables, and scales |
| old-transfer-to-woman | `old-transfer-to-woman` | `src/components.jl`: `TransferToWoman.old` | ported; mirrored on the man like `TransferToWoman.current` | Entities, state variables, and scales |
| spouse | `spouse` partner pointer | `src/components.jl`: `Spouse.entity` | ported | Entities, state variables, and scales |
| wage | `wage` >= 0 | `src/components.jl`: `Wage.current` | ported | Entities, state variables, and scales |
| wage-pre | `wage-pre` pre-shock wage memory | `src/components.jl`: `Wage.old` (exists but not wired as shock baseline) | partial | Entities, state variables, and scales; Details: Shocks |
| preference-private | `preference-private` in [0,1] | `src/components.jl`: `PreferencePrivate.current` | ported | Entities, state variables, and scales |
| preference-private-pre | `preference-private-pre` pre-shock preference memory | none (no Julia field) | not ported | Entities, state variables, and scales; Details: Shocks |
| preference-difference | `preference-difference` = h minus alpha, diagnostic | none (no Julia symbol) | not ported | Entities, state variables, and scales; Details: Endogenous preference adaptation |
| conformism | `conformism` >= 0 | `src/components.jl`: `Conformism.amount` | ported | Entities, state variables, and scales |
| current-utility | `current-utility` | `src/components.jl`: `CurrentUtility.amount` (created in `get_agent`, never updated) | unwired | Entities, state variables, and scales |
| memory-change | `memory-change` solver scratch state | none (algorithm sketch only in comments in `src/systems/household_bargaining.jl`) | not ported | Entities, state variables, and scales; Details: Labour best response |
| number | `number`, only used in `import-csv` mode | none (no Julia symbol) | not ported | Entities, state variables, and scales; Details: Input data |
| norm-parameter | `norm-parameter` stored norm penalty | `src/components.jl`: `NormParameter.amount`, set by `calculate_norm_perception!` in `src/systems/norm_perception.jl` | ported | Entities, state variables, and scales; Details: Norm perception (`calculate-utility`) |
| perception-norm-division-of-labor | `perception-norm-division-of-labor` stored percept | `src/components.jl`: `PerceptionNormDivisionOfLabor.amount`, set by `calculate_norm_perception!` in `src/systems/norm_perception.jl` | ported | Entities, state variables, and scales; Details: Norm perception (`calculate-utility`) |
| Household (implicit) | `(woman, man, theta)` triple, theta > 0 is man-to-woman transfer | `src/systems/initialisation.jl`: `initialize_household` spouse pairing | partial | Entities, state variables, and scales |
| Social links | `links` breed, undirected same-sex ties | `src/resources/social_network.jl`: `SocialNetwork` (men and women graphs plus entity vectors) | ported | Entities, state variables, and scales |
| Observer: global means | `global-mean-working-time-men/women`, `global-mean-transfer` | `src/resources/properties.jl`: `GlobalStats.mean_men`, `mean_women`, `mean_transfer` | partial | Entities, state variables, and scales; Details: Statistics |
| Observer: histories and moving averages | `history-*`, `average-mean-*` 10-period windows | `src/resources/properties.jl`: `GlobalStats.hist_men`, `hist_women` (no moving-average fields) | partial | Entities, state variables, and scales; Details: Statistics |
| Observer: run time and wage gap | `run-time`, `current_wage_gap` | `src/resources/properties.jl`: `GlobalStats.run_time`, `wage_gap` | partial | Entities, state variables, and scales; Details: Statistics |
| Observer: shock-propagation sets | `directly-affected-men/women`, `neighbors-of-affected-men/women` plus `mean-current-working-time-*` | none (no Julia symbol) | not ported | Entities, state variables, and scales; Details: Statistics |
| Observer: household employment-type sets | `single-earner-*-*`, `dual-earner-*`, `both-unemployed-*` plus means | none (no Julia symbol) | not ported | Entities, state variables, and scales; Details: Statistics |
| Observer: median-split subgroups | wage and preference subgroup agentsets fixed at `setup` | none (no Julia symbol) | not ported | Entities, state variables, and scales; Details: Initialization |
| Observer: working-time summary helper | n/a (Julia-side helper, no NetLogo global of that name) | `src/resources/observers.jl`: `WorkingTimeStats` (declared, never used) | stub | Details: Statistics |
