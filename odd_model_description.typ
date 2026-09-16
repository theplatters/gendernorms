#set document(title: "ODD Model Description — Endogenous Heterogeneous Gender Norms", author: "Hager, Mellacher & Rath")
#set page(paper: "a4", margin: (x: 2.2cm, y: 2cm))
#set heading(numbering: "1.1")
#set par(justify: true, leading: 0.55em)
#set text(size: 10.5pt)

#align(center)[
  #text(size: 17pt, weight: "bold")[Endogenous Heterogeneous Gender Norms and Female Labor Supply in an Intra-Household Bargaining Model]
  #v(0.3em)
  #text(size: 11pt)[ODD-style model description of `gender_model_shocks_preferences.nlogox`]
  #v(0.2em)
  #text(size: 10pt, fill: gray)[Theresa Hager, Patrick Mellacher and Magdalena Rath — NetLogo 7.0.3]
]

#outline(title: "Contents", depth: 2)
#v(1em)

// OOD vs ODD note: user wrote "ood-style" — this is the ODD (Overview, Design concepts, Details) protocol sensu Grimm et al. 2006/2010/2020.

= Overview

== Purpose

The model explains female (and male) labor supply as the joint outcome of (a) intra-household Nash bargaining over market work and an income transfer, and (b) endogenous, heterogeneous gender norms transmitted through same-sex social networks.

Heterogeneity in wages, preferences for private vs.\ public consumption, and conformism, interacted with network structure, generates dispersion and persistence in working time and transfers. Relative to the baseline (`gender_model_public_final.nlogo`), this variant adds (i) exogenous shocks at `shock-start` — a wage cut for directly affected households and/or a downward shift of `preference-private` — with gradual exponential recovery (`shock-depreciation`); (ii) continuous endogenous preference adaptation toward observed working time (`update-preferences`, weight `lambda`); (iii) an (inactive-by-default) gender-gap-closing wage-growth process (`update-wages`); and (iv) explicit shock-propagation observers (directly affected, their network neighbours, and household employment types). Comparative experiments vary the shock type, size, reach (`perc-affected-*`), recovery speed, preference baselines, conformism, utility specification, and network topology (random, Watts–Strogatz, preferential attachment, similarity-based, homophily, none, homogenous mixing).

The implementation analysed here is `gender_model_shocks_preferences.nlogox`, procedures `setup`, `go`, `start-shock`, `end-shock`, `set-theta`, `choose-bundle`, `calculate-utility`, `calculate-payoff`, `update-preferences`, `update-wages`, `update-statistics`.

== Entities, state variables, and scales

There are two agent breeds plus two link/collection entities:

#table(
  columns: (2.8cm, 6.2cm, 6.2cm),
  inset: 6pt,
  align: (left, left, left),
  table.header([*Entity*], [*State variables*], [*Notes*]),
  [women \ men \ (turtle breeds)], [`current-working-time in [0,1]` \ `old-working-time` \ `current-transfer-to-woman theta in [-1,1]` \ `old-transfer-to-woman` \ `spouse` (partner pointer) \ `wage >= 0` \ `wage-pre` (pre-shock wage memory) \ `preference-private in [0,1]` \ `preference-private-pre` (pre-shock preference memory) \ `preference-difference = h - alpha` (diagnostic) \ `conformism >= 0` \ `current-utility`, `memory-change`, `number` \ `norm-parameter`, `perception-norm-division-of-labor` (stored norm penalty/percept)], [One woman + one man = one household. `number` only used in `import-csv` mode. `memory-change` is solver scratch state. `wage-pre`/`preference-private-pre` are shock baselines for recovery. `norm-parameter`/`perception-norm-division-of-labor` were locals in the baseline and are now `turtles-own` so they can be traced/exported.],
  [Household \ (implicit)], [`(woman, man, theta)` triple; `theta>0` = transfer man→woman], [No separate NetLogo agent; bargaining unit in `set-theta`. Outside option defined at `theta=0`.],
  [Social links \ (`links` breed)], [Undirected same-sex ties], [Single breed shared by both sexes but only linked within sex, except via spouse-of-neighbour perception.],
  [Observer \ (globals)], [`global-mean-working-time-men/women`, `global-mean-transfer`, `history-*`, `average-mean-*`, subgroup agentsets \ `run-time`, `current_wage_gap` \ `directly-affected-men/women`, `neighbors-of-affected-men/women` + `mean-current-working-time-*` \ `single-earner-*-*`, `dual-earner-*`, `both-unemployed-*` + `mean-current-working-time-*`], [Median-split preference/wage subgroups fixed at `setup` as before. Shock-propagation and household-type agentsets also fixed at `setup` from the initial `directly-affected-*` draw; histories are 10-period moving windows.],
)

*Scales.* No explicit space matters: `layout-circle` is visualisation only. Time is discrete ticks; one `go` = shock check + household re-bargaining + norm updating + preference adaptation. `shock-start` defaults to 60; recovery runs for all later ticks. BehaviorSpace runs use 1000–4000 ticks (time limits 1000–4000). Labour and transfer are normalised fractions, not hours.

== Process overview and scheduling

#table(
  columns: (2.5cm, 12.7cm),
  inset: 6pt,
  table.header([*Phase*], [*What happens*]),
  [`setup`], [Clear, `reset-timer`, seed RNG if `fixed-rs`. Generate same-sex networks (for `random-network`, `watts-strogatz`, `preferential-attachment`). Create agents, pair spouses, draw `wage / preference-private / conformism / theta` from truncated normals around slider means. Optionally override one `specific-couple` or overwrite from CSV. Fix median-split subgroup agentsets. Optionally build similarity networks (`preference-private`, `wage`, `conformism`, `homophily`). Initialise `global-mean-working-time-*`. Draw `directly-affected-women/men` via `n-of (N * perc-affected-*/100)`; derive `neighbors-of-affected-*` from `link-neighbors` and household-type sets (`single-earner-*`, `dual-earner-*`, `both-unemployed-*`). `reset-ticks`.],
  [`go`, shock block], [If `ticks = shock-start`, run `start-shock` once; if `ticks > shock-start`, run `end-shock` every tick (partial recovery toward `wage-pre` / `preference-private-pre` at rate `shock-depreciation`).],
  [`go`, `set-theta`], [For each woman in sequence: (1) compute outside options via `choose-bundle(self, spouse, 0)`; (2) hill-climb `theta` up then down in steps of `0.001` using `calculate-payoff`; (3) commit `best-theta` and the associated `choose-bundle` labour pair to both spouses.],
  [`go`, `choose-bundle`], [Iterated best response: woman and man alternately hill-climb own `h` by `current-delta = 0.0001` while partner `h` is held fixed, until joint change `<= convergence_epsilon` (default 0.001). Evaluates `calculate-utility`.],
  [`go`, `update-preferences`], [Every tick, including `shock = "no"` runs: `preference-difference = h - alpha`; then `alpha <- (1-lambda) * alpha + lambda * h`, clipped to `[0,1]`. With default `lambda = 0.002` this is slow endogenous preference formation toward own behaviour.],
  [`go`, `update-statistics`], [Copy `current-*` to `old-*`. Recompute global means, 10-period histories and moving averages. Recompute means for `directly-affected-*`, `neighbors-of-affected-*`, and household-type sets.],
  [`go`, `tick` + I/O], [Advance clock; optionally append per-turtle row via `print-agent-positions`; set `run-time = timer`. `update-wages` exists but is commented out in `go`.],
)

Ordering is sequential over households within a tick. Norm perception uses lagged `old-*` values, so intra-tick ordering does not directly enter norms, but `choose-bundle` reads partner `current-working-time` while it is being mutated.

= Design concepts

#table(
  columns: (2.8cm, 12.4cm),
  inset: 6pt,
  table.header([*Concept*], [*Realisation in this model*]),
  [Basic principle], [Collective household model with Nash bargaining + conformity-augmented CES/additive utility + social norms, extended with exogenous shocks and adaptive preferences. Norms are local means, hence heterogeneous and endogenous; preferences are now also endogenous via `lambda`.],
  [Emergence], [Gender gaps in hours, transfer distributions, norm clusters, and shock-propagation gradients (affected vs.\ neighbours vs.\ rest) emerge from bargaining + network topology + adaptation; not imposed beyond initial means `norm-paid-time-male/female` and the `shock-start` intervention.],
  [Adaptation], [Households adapt `h_w, h_m, theta` by myopic hill-climbing. Preferences adapt toward own hours via `lambda`. Wages/shock memories recover toward pre-shock baselines via `shock-depreciation`. No forward-looking search, no link rewiring after `setup`.],
  [Objectives], [Maximise own `calculate-utility` (labour stage) and Nash product `(U_m - U_out_m)(U_w - U_out_w)` (transfer stage). Individual rationality required, else payoff `-1`.],
  [Learning / Prediction], [None, except backward-looking preference assimilation (`alpha` follows `h`) and lagged imitation via norm penalty. No expectation formation.],
  [Sensing], [Agents sense: own + spouse wage/preference/conformism; partner current `h`; mean `old-h` and `old-theta` of same-sex `link-neighbors`; mean `old-h` of spouses-of-neighbors. If isolated: own lag, or global mean under `homogenous mixing`. Stored in `perception-norm-division-of-labor` / `norm-parameter` for inspection.],
  [Interaction], [Direct: intra-household bargaining. Indirect: inter-household via norm penalty `exp(norm-parameter)`. Shocks propagate indirectly through norms and bargaining; no market clearing.],
  [Stochasticity], [Initial draws (truncated normals), spouse matching `one-of`, network generators, `rnd:weighted-n-of` noise (`N(0,0.001)`), and `n-of` sampling of `directly-affected-*`. Reproducible via `fixed-rs` + `random-seed-fixed`.],
  [Collectives], [Household (bargaining unit); same-sex neighbourhood (reference group); median-split subgroups for observation only; shock-propagation sets (`directly-affected-*`, `neighbors-of-affected-*`) and employment-type sets (`single-earner-*`, `dual-earner-*`, `both-unemployed-*`) for observation only.],
  [Heterogeneity], [Continuous heterogeneity in `wage`, `preference-private`, `conformism`; structural heterogeneity via degree/position; treatment heterogeneity via affected/neighbour status.],
  [Observation], [Means/medians/SD/p25/p75 of utility, hours, transfers; subgroup means by wage/preference; moving averages; shock-propagation means and `current_wage_gap`; `preference-difference` time series/histograms; per-agent CSV trace (now with spouse hours, `norm-parameter`, perceived norm); time-series plots + histograms.],
)

= Details

== Initialization (`setup`, `set-initials-*`)

1. `ca`; `reset-timer`; set `current-delta = 0.0001` (was `0.00001` in baseline), clear histories.
2. If `fixed-rs`, `random-seed random-seed-fixed`.
3. Build `random-network / watts-strogatz / preferential-attachment` networks via `nw` extension *before* agents get traits; other modes create unlinked turtles first.
4. `layout-circle` (visual only); re-seed if `fixed-rs` so trait distributions are comparable across topologies.
5. Pair each woman with `one-of men with [spouse = 0]`; reciprocal `spouse` pointers.
6. Women: `h = norm-paid-time-female/100`, `theta ~ N(initial-transfer, initial-transfer * std-dev-values)` clipped to `[0,1]`, `wage ~ N(wage-female, mean(wage-male,wage-female)*std-dev-values)` clipped at 0, `conformism ~ N(conformism-female, ...)` clipped at 0, `preference-private ~ N(preference-private-mean-female, ...)` clipped to `[0.01,0.99]`. Men symmetric with male sliders and `norm-paid-time-male/100`; man inherits initial `theta` from spouse.
7. Optional `specific-couple` override; median splits for high/low public-goods households and above/below-median wages (static snapshots).
8. Zero `mean-current-working-time-directly-affected-*` / `neighbors-of-affected-*`; optional similarity/`homophily` network construction.
9. Initialise `global-mean-working-time-men/women` from initial hours (used as perceived norm under `homogenous mixing`).
10. Draw `directly-affected-women = n-of (N * perc-affected-female/100) women` (default 30%) and `directly-affected-men` (default 0%); build `neighbors-of-affected-*` as non-affected `link-neighbors` of affected turtles; build household-type sets by cross-tabulating own vs.\ spouse affected status.
11. Optional CSV overwrite (`initialTransfer.csv`, `moderatePreferences.csv`, `highConformity.csv`, `moderateConformity.csv` — note: preferences file is read twice, second read overwrites the first).
12. `reset-ticks`; optionally open `agent_position_<exp>_<run>.csv` with extended header `agentid,agenttype,period,workingtime,workingtimespouse,transfer,networkstructure,norm,perceivednorm`.

Key defaults in the Interface tab: `wage-female=0.9`, `wage-male=1.0`, `norm-paid-time-male=77`, `norm-paid-time-female=36`, `number-agents-each-type=400` (experiments use 10–500), `preference-private-mean-male=0.45`, `preference-private-mean-female=0.48`, `initial-transfer=0.0`, `std-dev-values=0.2`, `conformism-male=10.0`, `conformism-female=10.0`, `utility-function=CES` with `CES_beta=0.5`, `weight-working-time-self/partner/transfer=1`, `watts-strogatz-neighbors=1`, `preferential-attachment-min-degree=1`, `convergence_epsilon=0.001`, `lambda=0.002`, `shock=no` (chooser default index 3), `shock-start=60`, `shock-depreciation=0.005`, `preference-private-shock-male/female=0.0`, `perc-affected-female=30`, `perc-affected-male=0`, `wage-growth-rate=0.0`.

== Input data

No time-series input. `import-csv=true` replaces random traits with files listed above. CSV handling assumes row order matches household `number` and provides no existence/length checks. All BehaviorSpace experiments shipped with the file use `import-csv=false`.

== Submodels

=== Norm perception (`calculate-utility`)

Let $h_i$ be own hours, $h_j$ spouse hours, $theta$ transfer-to-woman.

$
N^h_i &= "mean old-h of link-neighbors of " i \
N^theta_i &= "mean old-theta of link-neighbors of " i \
N^(h_j)_i &= "mean old-h of spouses-of-neighbors" \
"norm-penalty"_i &= -c_i dot (omega_s (h_i - N^h_i)^2 + omega_theta (theta - N^theta_i)^2 + omega_p (h_j - N^(h_j)_i)^2)
$

$c_i$ is own `conformism`; $omega$ are the three `weight-*` sliders. Isolated agents use own lag; under `homogenous mixing` they use the global means instead. Unlike the baseline, the percept `perception-norm-division-of-labor` and the penalty `norm-parameter` are stored back to the calling turtle (`set`, not `let`), so they persist for plots, histograms, and the per-agent CSV. Note the stored values belong to whichever agent last called `calculate-utility` on that turtle (including counterfactual `choose-bundle`/`calculate-payoff` evaluations), not necessarily the last committed bundle.

=== Material utility and conformity multiplier

Define private consumption $x_i$ and domestic good $Q = 2 - h_i - h_j$:

- If recipient (`relevant-transfer < 0`, sign-flipped for women): $x_i = h_i w_i + |theta| w_j h_j$.
- If donor: $x_i = h_i w_i (1 - theta)$.
- If $x_i <= 0$ or $h > 1$: utility $= -200$ (infeasibility penalty).

Four `utility-function` options (with $alpha_i =$ `preference-private`, $beta =$ `CES_beta`):

- `additive`: $(alpha_i sqrt(x_i) + (1-alpha_i) sqrt(Q)) dot exp("norm-penalty"_i)$.
- `CES`: $(alpha_i x_i^beta + (1-alpha_i) Q^beta)^(1/beta) dot exp("norm-penalty"_i)$.
- `multiplicative`: $sqrt(x_i) sqrt(Q) dot exp("norm-penalty"_i)$.
- `multiplicative including weights`: intended $x_i^(alpha_i) Q^(1-alpha_i) dot exp(...)$; recipient branch matches this intent, donor branch as shipped computes $((x_i^(alpha_i) dot Q))^(1-alpha_i)$ — see code critique.

=== Labour best response (`choose-bundle`)

Holding $theta$ fixed, each partner steps $h_i$ by $plus.minus "current-delta"$ (`0.0001`) while it strictly improves own utility and stays in $[0,1]$. Partners alternate until joint absolute change `change-a + change-b <= convergence_epsilon` (default `0.001`). `memory-change` (last 10 steps) and `sum-memory-change` guard against 2-cycles. No step-size annealing is active in the shipped version (the `current-delta / 2` block is commented out). Relative to the baseline (`> 0` exact convergence, step `0.00001`), this converges earlier and more coarsely.

=== Transfer bargaining (`set-theta`, `calculate-payoff`)

For a household $(w, m)$ let the predetermined state in tick $t$ be wages $(w_w, w_m)$, preferences $(alpha_w, alpha_m)$, conformism $(c_w, c_m)$, and lagged norms $N$ (same-sex means of `old-h` / `old-theta` plus spouses-of-neighbours means). For fixed $theta$, `choose-bundle` returns the labour subgame outcome as the fixed point of alternating best responses:

$ (h^*_w (theta), h^*_m (theta)) = "choose-bundle"(w, m, theta), quad h^*_i (theta) in [0,1], $

where each $h^*_i$ maximises own `calculate-utility` $U_i (h_i, h_j, theta\,; w_i, w_j, alpha_i, c_i, N)$ holding partner hours and $theta$ fixed (hill-climb by `current-delta`, see above). Indirect utilities conditional on $theta$ are then:

$ U_w (theta) &= U_w (h^*_w (theta), h^*_m (theta), theta), \
  U_m (theta) &= U_m (h^*_w (theta), h^*_m (theta), theta). $

$theta$ is the transfer-to-woman in $[-1,1]$: $theta > 0$ is a transfer man$arrow.r$woman (the woman is `recipient`, `relevant-transfer = -theta < 0`); $theta < 0$ reverses the flow. It enters both material consumption $x_i (theta)$ and the norm penalty on $(theta - N^theta_i)^2$.

Outside options are the indirect utilities at zero transfer, evaluated through the same labour response:

$ U^0_w &= U_w (h^*_w (0), h^*_m (0), 0), \
  U^0_m &= U_m (h^*_w (0), h^*_m (0), 0). $

With $Delta_i (theta) = "precision"(U_i (theta), 8) - "precision"(U^0_i, 8)$, the Nash product implemented in `calculate-payoff` is:

$ "payoff"(theta) = cases((Delta_w (theta) dot Delta_m (theta)) "if" Delta_w (theta) >= 0 "and" Delta_m (theta) >= 0, -1 "otherwise") $

so the household solves, in exact terms,

$ max_(theta in [-1,1]) quad (U_w (theta) - U^0_w)(U_m (theta) - U^0_m) quad "s.t." quad U_w (theta) >= U^0_w , U_m (theta) >= U^0_m, $

with value $-1$ assigned to individually irrational $theta$ and with the $8$-decimal rounding above creating flat plateaus. Labour $(h^*_w, h^*_m)$ adjusts endogenously at every evaluated $theta$, i.e. this is bargaining over $theta$ anticipating the labour Nash equilibrium, not over the triple $(h_w, h_m, theta)$ jointly.

Numerically, `set-theta` approximates this with two one-sided hill-climbs from the status quo $theta_t$ with step $delta_theta = 0.001$ over $[-1,1]$, stopping at the first decrease per side:

The $theta$ with the highest payoff and its `choose-bundle` hours are committed. Note: `best-payoff` is initialised to `0` and `best-theta` to `0`, so the status quo is never evaluated and a no-improvement search defaults to `theta=0`. (Unchanged from baseline; `set-theta-index` exhaustive-grid alternative is still present but unused.)

=== Shocks (`start-shock`, `end-shock`)

At `ticks = shock-start`, `start-shock` fires once; for all later ticks `end-shock` fires:

- `shock = "preference"` or `"both"`: save `preference-private-pre = preference-private` for all turtles, then `preference-private <- max(0, preference-private - preference-private-shock-*)` by sex (`preference-private-shock-male/female`, Interface defaults `0.0`). Note this hits *all* men/women, not only `directly-affected-*`.
- `shock = "wage"` or `"both"`: save `wage-pre = wage` for all turtles, then `wage <- 0.6 * wage-pre` (40% cut) for `turtle-set directly-affected-men directly-affected-women` only.
- `shock = "no"`: neither fires meaningfully.
- Recovery (`end-shock`): `wage <- wage + shock-depreciation * (wage-pre - wage)` for wages below baseline; `preference-private <- preference-private + shock-depreciation * (preference-private-pre - preference-private)` for preferences below baseline. With default `shock-depreciation = 0.005` this is slow exponential decay of the shock gap. There is no overshoot: once the gap closes, updating stops.

`update-preferences` runs concurrently (see below), so post-shock preferences are pulled both toward `preference-private-pre` (recovery) and toward current `h` (adaptation).

=== Endogenous preference adaptation (`update-preferences`) and wage growth (`update-wages`)

- `update-preferences` (called every `go`): `preference-difference = current-working-time - preference-private`; `preference-private <- (1-lambda) * preference-private + lambda * current-working-time`, clipped to `[0,1]`. Default `lambda = 0.002`. This operates even when `shock = "no"`, making preferences endogenous in all runs.
- `update-wages` (defined but commented out in `go`): `current_wage_gap = 1 - mean(wage_women)/mean(wage_men)`; `wage_women <- wage_women * (1 + daily-growth)` with `daily-growth = (1 + wage-growth-rate)^(1/365) - 1` while the gap is positive. Interface default `wage-growth-rate = 0.0`. An older commented-out wage rule remains inside `update-statistics`.

=== Network formation (`generate-network`, `generate-homophilic-network`)

Similarity networks connect each turtle to `preferential-attachment-min-degree` (default `1`) others sampled by `rnd:weighted-n-of` with weight $1\/abs(x_"myself" - x_"other" - N(0,0.001))$ for $x in ${`preference-private`, `wage`, `conformism`}. Homophily uses $1\/(abs(delta "conformism") + abs(delta "wage") + abs(delta "preference"))$. Ties are created once at `setup` and never updated.

=== Statistics (`update-statistics`)

Copies `current-*` to `old-*`, recomputes global means, pushes them onto 10-element histories, and reports their moving averages `average-mean-working-time-{women,men}`. `global-mean-transfer` is the contemporaneous mean over women. Additionally, if the respective agentsets are non-empty, updates `mean-current-working-time-directly-affected-{men,women}`, `mean-current-working-time-neighbors-of-affected-{men,women}`, and the eight household-type means (`single-earner-women-women/men`, `single-earner-men-women/men`, `dual-earner-women/men`, `both-unemployed-women/men`; `0` if empty). Also sets `run-time = timer` in `go` after `tick`.

= Parameters, experiments, and output

#table(
  columns: (4.2cm, 3.2cm, 7.8cm),
  inset: 6pt,
  table.header([*Parameter*], [*Default*], [*Meaning*]),
  [`number-agents-each-type`], [`400`], [Households per sex; experiments use 10–500.],
  [`wage-{female,male}`], [`0.9 / 1.0`], [Mean wage offers; dispersion via `std-dev-values`.],
  [`preference-private-mean-{male,female}`], [`0.45 / 0.48`], [Mean weight on private vs.\ domestic good.],
  [`conformism-{female,male}`], [`10.0 / 10.0`], [Mean norm sensitivity (was `0.0 / 3.0`).],
  [`std-dev-values`], [`0.2`], [Relative SD scaler for all traits.],
  [`norm-paid-time-{female,male}`], [`36 / 77`], [Initial hours in percent (was `20 / 80`).],
  [`initial-transfer`], [`0.0`], [Mean initial $theta$ (was `0.1`).],
  [`utility-function`, `CES_beta`], [`CES`, `0.5`], [Aggregator and substitution parameter.],
  [`weight-working-time-self`, `weight-transfer`, `weight-working-time-partner`], [`1 / 1 / 1`], [$omega_s, omega_theta, omega_p$.],
  [`network-structure`], [`watts-strogatz`], [Same 9 options as baseline. Interface cursor on Watts–Strogatz; experiments fix it.],
  [`random-network-prob`, `watts-strogatz-neighbors/rewiring`, `preferential-attachment-min-degree`], [`0.01`, `1 / 0.1`, `1`], [Topology hyperparameters (neighbours/degree were `2` in baseline).],
  [`convergence_epsilon`], [`0.001`], [New: joint-change stopping tolerance in `choose-bundle` (baseline: exact `> 0`).],
  [`lambda`], [`0.002`], [New: preference-adaptation weight toward own hours.],
  [`shock`], [`no`], [New chooser: `wage`, `preference`, `both`, `no`. Preference shock is global; wage shock hits `directly-affected-*` only.],
  [`shock-start`, `shock-depreciation`], [`60`, `0.005`], [New: tick of one-off shock; per-tick exponential recovery rate.],
  [`preference-private-shock-{male,female}`], [`0.0 / 0.0`], [New: downward shift of `preference-private` by sex.],
  [`perc-affected-{male,female}`], [`0 / 30`], [New: % of each sex in `directly-affected-*` (wage-shock target + observer).],
  [`wage-growth-rate`], [`0.0`], [New: annual growth closing the gender wage gap in `update-wages` (currently inactive).],
  [`fixed-rs`, `random-seed-fixed`], [off, `10`], [Reproducibility switch and seed (was on/`1`).],
  [`specific-couple`, `*-in-question`], [`off`], [Single-household probe overrides.],
  [`import-csv`, `output-locations`], [`off`], [CSV trait import; per-agent trace export (extended columns).],
)

Shipped BehaviorSpace: 50 experiments, all `runMetricsEveryStep=true` (baseline was `false`), time limits 1000–4000 ticks: `experiment_shock_conformism_1–10`, `experiment_shock_ofat_1–10`, `experiment_shock_policy_1–10`, `experiment_all_parameters_1–10` (one seed each, Watts–Strogatz, `CES`, `N=100–400`, sweeping `shock`, `shock-depreciation`, preference baselines, conformism up to 500, `CES_beta`), plus `test_n`, `experiment_test`, `experiment_rho`/`conformism`/`CES`/`strength*`/`epsilon`/`equilibrium` diagnostics. Core metrics (42 in shock experiments): mean/median/SD/p25/p75 of utility, hours, transfers, subgroup means by wage/preference, `mean-current-working-time-directly-affected-*`, `neighbors-of-affected-*`, household-type means, and `current_wage_gap`. `experiment_all_parameters_*` / `test_*` variants track only 1–3 metrics and sweep `rho` (unbound slider reference), `CES_beta`, `convergence_epsilon`, and population size.

= Known implementation quirks (for replicators)

1. Specific-woman conformism override uses the male probe value (unchanged).
2. Preferences CSV block is duplicated (unchanged).
3. `set-theta` never evaluates staying put; defaults to 0 on failure (unchanged).
4. `multiplicative including weights` donor branch parenthesisation differs from the Cobb–Douglas intent (recipient branch is correct); unchanged from baseline.
5. `precision x 8` in `calculate-payoff` creates plateaus at the `1e-5` labour step (unchanged; labour step is now `1e-4` with `convergence_epsilon = 0.001` early stopping).
6. `calc-pct` indexing is only safe for interior percentiles (used as 25/75; unchanged).
7. Subgroup agentsets and Info-tab documentation are static/stub as shipped (unchanged).
8. `both-unemployed-men` duplicates the `dual-earner-men` definition (`not affected` + spouse `not affected`) instead of `member? ... and member? ...`; `both-unemployed-women` is correct.
9. Asymmetric shock reach: wage shock targets `directly-affected-*` only, preference shock shifts *all* turtles of each sex regardless of affected status.
10. `update-preferences` runs every tick even with `shock = "no"`, so `lambda > 0` always makes preferences endogenous; shock recovery and preference adaptation pull in different directions after a preference shock.
11. `perception-norm-division-of-labor` / `norm-parameter` persistence: stored values reflect the last `calculate-utility` call (including counterfactual evaluations), not necessarily the committed bundle.
12. `experiment_all_parameters_*`, `test_*`, and `experiment_rho/conformism/...` reference a `rho` slider that does not exist in the Interface tab; they will not run as shipped without adding it (presumably the intended `lambda`).

#v(1em)
#line(length: 100%)
#text(size: 9pt, fill: gray)[ODD protocol after Grimm et al. (2006, 2010, 2020). This description was reverse-engineered from code; ambiguous points are noted above rather than resolved. Source: `gender_model_shocks_preferences.nlogox` + Interface/BehaviorSpace sections.]
