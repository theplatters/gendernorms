#set document(title: "ODD Model Description — Endogenous Heterogeneous Gender Norms", author: "Hager, Mellacher & Rath")
#set page(paper: "a4", margin: (x: 2.2cm, y: 2cm))
#set heading(numbering: "1.1")
#set par(justify: true, leading: 0.55em)
#set text(size: 10.5pt)

#align(center)[
  #text(size: 17pt, weight: "bold")[Endogenous Heterogeneous Gender Norms and Female Labor Supply in an Intra-Household Bargaining Model]
  #v(0.3em)
  #text(size: 11pt)[ODD-style model description of `gender_model_public_final.nlogo`]
  #v(0.2em)
  #text(size: 10pt, fill: gray)[Theresa Hager, Patrick Mellacher and Magdalena Rath — NetLogo 6.4.0]
]

#outline(title: "Contents", depth: 2)
#v(1em)

// OOD vs ODD note: user wrote "ood-style" — this is the ODD (Overview, Design concepts, Details) protocol sensu Grimm et al. 2006/2010/2020.

= Overview

== Purpose

The model explains female (and male) labor supply as the joint outcome of (a) intra-household Nash bargaining over market work and an income transfer, and (b) endogenous, heterogeneous gender norms transmitted through same-sex social networks.

Heterogeneity in wages, preferences for private vs.\ public consumption, and conformism, interacted with network structure, generates dispersion and persistence in working time and transfers. Comparative experiments vary the female wage, preference distributions, conformism, utility specification, and network topology (random, Watts–Strogatz, preferential attachment, similarity-based, homophily, none, homogenous mixing).

The implementation analysed here is `gender_model_public_final.nlogo`, procedures `setup`, `go`, `set-theta`, `choose-bundle`, `calculate-utility`, `calculate-payoff`, `update-statistics`.

== Entities, state variables, and scales

There are two agent breeds plus two link/collection entities:

#table(
  columns: (2.8cm, 6.2cm, 6.2cm),
  inset: 6pt,
  align: (left, left, left),
  table.header([*Entity*], [*State variables*], [*Notes*]),
  [women \ men \ (turtle breeds)], [`current-working-time in [0,1]` \ `old-working-time` \ `current-transfer-to-woman theta in [-1,1]` \ `old-transfer-to-woman` \ `spouse` (partner pointer) \ `wage >= 0` \ `preference-private in [0.01,0.99]` \ `conformism >= 0` \ `current-utility`, `memory-change`, `number`], [One woman + one man = one household. `number` only used in `import-csv` mode. `memory-change` is solver scratch state.],
  [Household \ (implicit)], [`(woman, man, theta)` triple; `theta>0` = transfer man→woman], [No separate NetLogo agent; bargaining unit in `set-theta`. Outside option defined at `theta=0`.],
  [Social links \ (`links` breed)], [Undirected same-sex ties], [Single breed shared by both sexes but only linked within sex, except via spouse-of-neighbour perception.],
  [Observer \ (globals)], [`global-mean-working-time-men/women`, `global-mean-transfer`, `history-*`, `average-mean-*`, subgroup agentsets], [Subgroup agentsets fixed at `setup` from initial medians; histories are 10-period moving windows.],
)

*Scales.* No explicit space matters: `layout-circle` is visualisation only. Time is discrete ticks; one `go` = one round of household re-bargaining + norm updating. Experiments run 10–100 ticks. Labour and transfer are normalised fractions, not hours.

== Process overview and scheduling

#table(
  columns: (2.5cm, 12.7cm),
  inset: 6pt,
  table.header([*Phase*], [*What happens*]),
  [`setup`], [Clear, seed RNG if `fixed-rs`. Generate same-sex networks (for `random-network`, `watts-strogatz`, `preferential-attachment`). Create agents, pair spouses, draw `wage / preference-private / conformism / theta` from truncated normals around slider means. Optionally override one `specific-couple` or overwrite from CSV. Fix subgroup agentsets. Optionally build similarity networks (`preference-private`, `wage`, `conformism`, `homophily`). `reset-ticks`.],
  [`go`, `set-theta`], [For each woman in sequence: (1) compute outside options via `choose-bundle(self, spouse, 0)`; (2) hill-climb `theta` up then down in steps of `0.001` using `calculate-payoff`; (3) commit `best-theta` and the associated `choose-bundle` labour pair to both spouses.],
  [`go`, `choose-bundle`], [Iterated best response: woman and man alternately hill-climb own `h` by `current-delta = 0.00001` while partner `h` is held fixed, until neither changes. Evaluates `calculate-utility`.],
  [`go`, `update-statistics`], [Copy `current-*` to `old-*`. Recompute global means, 10-period histories and moving averages.],
  [`go`, `tick` + I/O], [Advance clock; optionally append per-turtle row via `print-agent-positions`.],
)

Ordering is sequential over households within a tick. Norm perception uses lagged `old-*` values, so intra-tick ordering does not directly enter norms, but `choose-bundle` reads partner `current-working-time` while it is being mutated.

= Design concepts

#table(
  columns: (2.8cm, 12.4cm),
  inset: 6pt,
  table.header([*Concept*], [*Realisation in this model*]),
  [Basic principle], [Collective household model with Nash bargaining + conformity-augmented CES/additive utility + social norms. Norms are local means, hence heterogeneous and endogenous.],
  [Emergence], [Gender gaps in hours, transfer distributions, and norm clusters emerge from bargaining + network topology; not imposed beyond initial means `norm-paid-time-male/female`.],
  [Adaptation], [Households adapt `h_w, h_m, theta` by myopic hill-climbing. No forward-looking search, no link rewiring after `setup`.],
  [Objectives], [Maximise own `calculate-utility` (labour stage) and Nash product `(U_m - U_out_m)(U_w - U_out_w)` (transfer stage). Individual rationality required, else payoff `-1`.],
  [Learning / Prediction], [None. One-period lagged imitation via norm penalty only. No expectation formation.],
  [Sensing], [Agents sense: own + spouse wage/preference/conformism; partner current `h`; mean `old-h` and `old-theta` of same-sex `link-neighbors`; mean `old-h` of spouses-of-neighbors. If isolated: own lag, or global mean under `homogenous mixing`.],
  [Interaction], [Direct: intra-household bargaining. Indirect: inter-household via norm penalty `exp(norm-parameter)`. No market clearing.],
  [Stochasticity], [Initial draws (truncated normals), spouse matching `one-of`, network generators, `rnd:weighted-n-of` noise (`N(0,0.001)`). Reproducible via `fixed-rs` + `random-seed-fixed`.],
  [Collectives], [Household (bargaining unit); same-sex neighbourhood (reference group); median-split subgroups for observation only.],
  [Heterogeneity], [Continuous heterogeneity in `wage`, `preference-private`, `conformism`; structural heterogeneity via degree/position.],
  [Observation], [Means/medians/SD/p25/p75 of utility, hours, transfers; subgroup means by wage/preference; moving averages; per-agent CSV trace; time-series plot + histograms.],
)

= Details

== Initialization (`setup`, `set-initials-*`)

1. `ca`; set `current-delta = 0.00001`, clear histories.
2. If `fixed-rs`, `random-seed random-seed-fixed`.
3. Build `random-network / watts-strogatz / preferential-attachment` networks via `nw` extension *before* agents get traits; other modes create unlinked turtles first.
4. `layout-circle` (visual only); re-seed if `fixed-rs` so trait distributions are comparable across topologies.
5. Pair each woman with `one-of men with [spouse = 0]`; reciprocal `spouse` pointers.
6. Women: `h = norm-paid-time-female/100`, `theta ~ N(initial-transfer, initial-transfer * std-dev-values)` clipped to `[0,1]`, `wage ~ N(wage-female, mean(wage-male,wage-female)*std-dev-values)` clipped at 0, `conformism ~ N(conformism-female, ...)` clipped at 0, `preference-private ~ N(preference-private-mean-female, ...)` clipped to `[0.01,0.99]`. Men symmetric with male sliders and `norm-paid-time-male/100`; man inherits initial `theta` from spouse.
7. Optional `specific-couple` override; median splits for high/low public-goods households and above/below-median wages (static snapshots).
8. Optional similarity/`homophily` network construction; optional CSV overwrite (`initialTransfer.csv`, `moderatePreferences.csv`, `highConformity.csv`, `moderateConformity.csv` — note: preferences file is read twice, second read overwrites the first).
9. `reset-ticks`; optionally open `agent_position_<exp>_<run>.csv`.

Key defaults in the Interface tab: `wage-female=0.75`, `wage-male=1.0`, `norm-paid-time-male=80`, `norm-paid-time-female=20`, `number-agents-each-type=20` (experiments use 1 or 401), `preference-private-mean-{male,female}=0.5`, `initial-transfer=0.1`, `std-dev-values=0.2`, `conformism-male=3.0`, `conformism-female=0.0`, `utility-function=CES` with `CES_beta=0.5`, `weight-working-time-self/partner/transfer=1`.

== Input data

No time-series input. `import-csv=true` replaces random traits with files listed above. CSV handling assumes row order matches household `number` and provides no existence/length checks. All BehaviorSpace experiments shipped with the file use `import-csv=false`.

== Submodels

=== Norm perception (`calculate-utility`, lines 561–586)

Let $h_i$ be own hours, $h_j$ spouse hours, $theta$ transfer-to-woman.

$
N^h_i &= "mean old-h of link-neighbors of " i \
N^theta_i &= "mean old-theta of link-neighbors of " i \
N^(h_j)_i &= "mean old-h of spouses-of-neighbors" \
"norm-penalty"_i &= -c_i dot (omega_s (h_i - N^h_i)^2 + omega_theta (theta - N^theta_i)^2 + omega_p (h_j - N^(h_j)_i)^2)
$

$c_i$ is own `conformism`; $omega$ are the three `weight-*` sliders. Isolated agents use own lag; under `homogenous mixing` they use the global means instead.

=== Material utility and conformity multiplier

Define private consumption $x_i$ and domestic good $Q = 2 - h_i - h_j$:

- If recipient (`relevant-transfer < 0`, sign-flipped for women): $x_i = h_i w_i + |theta| w_j h_j$.
- If donor: $x_i = h_i w_i (1 - theta)$.
- If $x_i <= 0$ or $h > 1$: utility $= -200$ (infeasibility penalty).

Four `utility-function` options (with $alpha_i =$ `preference-private`, $beta =$ `CES_beta`):

- `additive`: $(alpha_i sqrt(x_i) + (1-alpha_i) sqrt(Q)) dot exp("norm-penalty"_i)$.
- `CES`: $(alpha_i x_i^beta + (1-alpha_i) Q^beta)^(1/beta) dot exp("norm-penalty"_i)$.
- `multiplicative`: $sqrt(x_i) sqrt(Q) dot exp("norm-penalty"_i)$.
- `multiplicative including weights`: intended $x_i^(alpha_i) Q^(1-alpha_i) dot exp(...)$; code as shipped computes $((x_i^(alpha_i) dot Q))^(1-alpha_i)$ — see code critique.

=== Labour best response (`choose-bundle`)

Holding $theta$ fixed, each partner steps $h_i$ by $plus.minus "current-delta"$ while it strictly improves own utility and stays in $[0,1]$. Partners alternate until a full round yields zero change. `memory-change` (last 10 steps) and `sum-memory-change` guard against 2-cycles. No step-size annealing is active in the shipped version (the `current-delta / 2` block is commented out).

=== Transfer bargaining (`set-theta`, `calculate-payoff`)

Outside options $U^0_w, U^0_m$ are the `choose-bundle` utilities at $theta = 0$. Candidate $theta$ values are tested in two one-sided hill-climbs from the current $theta$ with step $0.001$ over $[-1,1]$, stopping at the first decrease per side:

$ "payoff"(theta) = cases((U_m(theta)-U^0_m)(U_w(theta)-U^0_w) "if both" >= 0, -1 "otherwise") $

The $theta$ with the highest payoff and its `choose-bundle` hours are committed. Note: `best-payoff` is initialised to `0` and `best-theta` to `0`, so the status quo is never evaluated and a no-improvement search defaults to `theta=0`.

=== Network formation (`generate-network`, `generate-homophilic-network`)

Similarity networks connect each turtle to `preferential-attachment-min-degree` others sampled by `rnd:weighted-n-of` with weight $1\/abs(x_"myself" - x_"other" - N(0,0.001))$ for $x in ${`preference-private`, `wage`, `conformism`}. Homophily uses $1\/(abs(delta "conformism") + abs(delta "wage") + abs(delta "preference"))$. Ties are created once at `setup` and never updated.

=== Statistics (`update-statistics`)

Copies `current-*` to `old-*`, recomputes global means, pushes them onto 10-element histories, and reports their moving averages `average-mean-working-time-{women,men}`. `global-mean-transfer` is the contemporaneous mean over women.

= Parameters, experiments, and output

#table(
  columns: (4.2cm, 3.2cm, 7.8cm),
  inset: 6pt,
  table.header([*Parameter*], [*Default*], [*Meaning*]),
  [`number-agents-each-type`], [`20`], [Households; experiments use 1 (analytic) or 401.],
  [`wage-{female,male}`], [`0.75 / 1.0`], [Mean wage offers; dispersion via `std-dev-values`.],
  [`preference-private-mean-{female,male}`], [`0.5 / 0.5`], [Mean weight on private vs.\ domestic good.],
  [`conformism-{female,male}`], [`0.0 / 3.0`], [Mean norm sensitivity.],
  [`std-dev-values`], [`0.2`], [Relative SD scaler for all traits.],
  [`norm-paid-time-{female,male}`], [`20 / 80`], [Initial hours in percent.],
  [`initial-transfer`], [`0.1`], [Mean initial $theta$.],
  [`utility-function`, `CES_beta`], [`CES`, `0.5`], [Aggregator and substitution parameter.],
  [`weight-working-time-self`, `weight-transfer`, `weight-working-time-partner`], [`1 / 1 / 1`], [$omega_s, omega_theta, omega_p$.],
  [`network-structure`], [—], [`random-network`, `watts-strogatz`, `preferential-attachment`, `preference-private`, `wage`, `conformism`, `homophily`, `none`, `homogenous mixing`.],
  [`random-network-prob`, `watts-strogatz-neighbors/rewiring`, `preferential-attachment-min-degree`], [`0.01`, `2 / 0.1`, `2`], [Topology hyperparameters.],
  [`fixed-rs`, `random-seed-fixed`], [on/off, `1`], [Reproducibility switch and seed.],
  [`specific-couple`, `*-in-question`], [`off`], [Single-household probe overrides.],
  [`import-csv`, `output-locations`], [`off`], [CSV trait import; per-agent trace export.],
)

Shipped BehaviorSpace: `experiment_1` (single couple, wage/preference/$beta$ sweep); `experiment_2–9` (401 households $times$ 1000 seeds $times$ wage-female ${0.75,1.0,1.25}$ $times$ symmetric vs.\ asymmetric preferences, one network each); `different_conformism` (conformism-male 0–5). Metrics: mean/median/SD/p25/p75 of utility, hours, transfers, plus subgroup means. `runMetricsEveryStep=false` — end-of-run snapshots only.

= Known implementation quirks (for replicators)

1. Specific-woman conformism override uses the male probe value.
2. Preferences CSV block is duplicated.
3. `set-theta` never evaluates staying put; defaults to 0 on failure.
4. `multiplicative including weights` parenthesisation differs from the Cobb–Douglas intent.
5. `precision x 8` in `calculate-payoff` creates plateaus at the `1e-5` labour step.
6. `calc-pct` indexing is only safe for interior percentiles (used as 25/75).
7. Subgroup agentsets and Info-tab documentation are static/stub as shipped.

#v(1em)
#line(length: 100%)
#text(size: 9pt, fill: gray)[ODD protocol after Grimm et al. (2006, 2010, 2020). This description was reverse-engineered from code; ambiguous points are noted above rather than resolved. Source: `gender_model_public_final.nlogo` + Interface/BehaviorSpace sections.]
