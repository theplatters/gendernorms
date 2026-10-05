---
id: MDR-0017
title: Safeguarded derivative labour best responses
status: accepted
date: 2026-09-30
supersedes: MDR-0002
superseded_by: ""
---

## Context

`MDR-0002` solves the labour best response of NetLogo `choose-bundle`
(ODD section Labour best response) by seeded continuous Brent
maximization of the prepared own-hours objective `BestResponseObjective`
(`MDR-0013`, `ADR-0018`): three objective samples at a stationary seed
(the seed and its two `BEST_RESPONSE_TOL` probes), otherwise a windowed
Brent search of 15 to 55 samples. Labour solves dominate the bargaining
kernel (59 percent of the `MDR-0014` anatomy), and the seeded search is
path-anchored: it returns the seed when no neighbour probe improves,
so a household stuck at a discrete local maximum stays there.

The objective (ODD sections Material utility and conformity multiplier
and Labour best response; NetLogo `calculate-utility`) is smooth on its
positive feasible interior and admits closed-form log-derivatives. Write
`x = A*h + B` (recipient `A = wage_self`, `B = transfer_income`; payer
`A = wage_self * one_minus_transfer`, `B = 0`; the `x` and `Q` VALUES
keep the exact expression grouping of the `(obj::BestResponseObjective)(h)`
call overload, `MDR-0013` rounding discipline, `A` and `B` enter the
derivative FORMULAS only), `Q = Q0 - h` with `Q0 = 2 - h_spouse`, and
`k = conformism * norm_weight` so the norm exponent is
`norm = -conformism * (norm_weight * (h - norm_hours)^2 + norm_transfer +
norm_spouse)` and `n'(h) = -2*k*(h - norm_hours)`, `n''(h) = -2*k`. For
`g = d log(U)/dh` and `g' = d2 log(U)/dh2` the material parts are:

- Multiplicative: `g = A/(2x) - 1/(2Q)`,
  `g' = -A^2/(2x^2) - 1/(2Q^2)`.
- MultiplicativeWeighted (both roles since `MDR-0019` removed the
  preserved NetLogo quirk branch `(x^alpha * Q)^(1-alpha)` of
  `MDR-0003`, `individual_utility`): `g = alpha*A/x - (1-alpha)/Q`,
  `g' = -alpha*A^2/x^2 - (1-alpha)/Q^2`. Historical quirk form of the
  payer: `g = (1-alpha)*(alpha*A/x - 1/Q)`,
  `g' = -(1-alpha)*(alpha*A^2/x^2 + 1/Q^2)`.
- Additive (and the `CES` `beta == 0.5` inner form of `MDR-0013`): with
  `r = sqrt(x)`, `s = sqrt(Q)`, `m = alpha*r + (1-alpha)*s`,
  `m' = 0.5*(alpha*A/r - (1-alpha)/s)`,
  `m'' = -0.25*(alpha*A^2/(x*r) + (1-alpha)/(Q*s))`:
  `g = m'/m`, `g' = m''/m - (m'/m)^2`. The `beta == 0.5` specialization
  of `material` is `m*m`, so `log(U) = 2*log(m) + norm` and
  `g = 2*m'/m`, `g' = 2*(m''/m - (m'/m)^2)`.
- CES with `0 < beta <= 1`: `S = alpha*x^beta + (1-alpha)*Q^beta`,
  `D = alpha*A*x^(beta-1) - (1-alpha)*Q^(beta-1)`,
  `T = alpha*A^2*x^(beta-2) + (1-alpha)*Q^(beta-2)`,
  `g = D/S`, `g' = (beta-1)*T/S - beta*(D/S)^2`. `beta == 1` is a
  special case that avoids the `0 * Inf` of `T` at the boundary:
  `S = alpha*x + (1-alpha)*Q`, `D = alpha*A - (1-alpha)`,
  `g = D/S`, `g' = -(D/S)^2`.

Totals are `g_total = g_material + n'(h)` and
`g'_total = g_material' - 2*k`.

Sign argument (why a root of `g` brackets the optimum): on the positive
feasible interior every material function above is positive and concave
in `h` for `alpha` in `[0, 1]`, `A, B >= 0`, and `0 < beta <= 1`.
Multiplicative is `sqrt(x*Q)` with `(x*Q)'' = -2A <= 0` and `sqrt`
concave and increasing; the weighted Cobb-Douglas form
`x^alpha*Q^(1-alpha)` is concave (a weighted geometric mean with
exponent sum `<= 1`; the removed payer quirk form
`x^(alpha*(1-alpha))*Q^(1-alpha)` of `MDR-0019` was one as well);
Additive is a positive combination of `sqrt` of affine
functions; the CES aggregator `(alpha*x^beta + (1-alpha)*Q^beta)^(1/beta)`
is concave for `beta <= 1` (linear at `beta == 1`). The log of a
positive concave function is concave, and `norm` is concave for
`k >= 0`, so `log(U)` is concave and `g` is non-increasing on the
feasible interior. An interior root of `g` is therefore the unique
interior optimum, `g > 0` left of it and `g < 0` right of it, and the
signs of `g` at two feasible points bracket the root.

## Decision

Supersede `MDR-0002` (`MDR-0017` supersedes `MDR-0002`; `MDR-0002` is
superseded by `MDR-0017`). The solver of eligible cases becomes a
safeguarded derivative root solve of `g` over `[0, 1]`; the seeded Brent
path of `MDR-0002` remains in force verbatim as the documented fallback
and is run EXACTLY as before on every ineligible or failed case.

Preserved exactly (restated from `MDR-0002` and the preserved clauses of
`MDR-0013`/`MDR-0014`, still governed here):

- Objective: the `individual_utility` of NetLogo `calculate-utility` via
  the prepared `BestResponseObjective` arithmetic of `MDR-0013`/`MDR-0014`
  (exact expression grouping, the `CES` `beta == 0.5` sqrt/square
  `material`; the `MultiplicativeWeighted` payer quirk recorded here as
  preserved was later removed under `MDR-0019`, which unified both
  roles on the intended form). The objective
  chain is untouched by this record; only the search over it changes.
- Alternating loop: `mutual_best_response` keeps its update order,
  `eps = 1.0e-3`, `max_sweeps = 100`, the clamping to `[0, 1]`, and the
  keep-hours-when-no-feasible-sample rule (a `NaN` best response keeps
  the current hours).
- Fallback semantics: ineligible cases and any failed derivative solve
  run `maximize_1d(obj, 0.0, 1.0, h_start, BEST_RESPONSE_WINDOW,
  BEST_RESPONSE_TOL)`, the exact `MDR-0002` expression, so they are
  bitwise identical to the pre-change solver, including `NaN` and signed
  zeros. `BEST_RESPONSE_TOL` (the NetLogo `current-delta` resolution)
  and `BEST_RESPONSE_WINDOW` keep their `MDR-0002` values and meaning
  for that path. `best_response_1d` never returns `-Inf`; the `NaN`
  contract is unchanged.
- Guard semantics: `-Inf` on `x <= 0`, `Q <= 0`, own hours outside
  `[0, 1]`, or spouse hours outside `[0, 1]`, with the trigger
  conditions of `individual_utility`.

Changed:

- Eligible cases (all of the following): the spec is `Additive`,
  `Multiplicative`, `MultiplicativeWeighted`, or `CES` with finite
  `CES_DERIVATIVE_MIN_BETA <= beta <= 1`; `h_start` is finite;
  `h_spouse` in `[0, 1]`; `alpha` in `[0, 1]`; every objective field is
  finite; `wage_self`, `conformism`, and `norm_weight` are `>= 0`; the
  consumption coefficients satisfy `A >= 0`, `B >= 0`, and
  `A > 0 || B > 0`. Every other case (unknown `UtilitySpec`, `CES`
  `beta < CES_DERIVATIVE_MIN_BETA` or `beta > 1` or non-finite `beta`,
  `alpha` outside `[0, 1]`, negative conformism or norm weight,
  `A == B == 0`, `h_spouse` outside `[0, 1]`, non-finite fields) falls
  back bitwise. The `CES` floor `CES_DERIVATIVE_MIN_BETA = 1.0e-3`
  protects the computed-utility non-degradation of the equivalence
  protocol below: the computed utility evaluates `S^(1/beta)` from the
  rounded inner sum `S = alpha * x^beta + (1 - alpha) * Q^beta`, whose
  condition number `1 / beta` amplifies the inner-sum rounding of the
  two compared objective evaluations to the relative gap
  `(1 / beta) * n_ops * eps` (`n_ops = 10` the combined error budget,
  `eps = 2^-53`; the `CES_CERT_MIN_BETA` conditioning argument of
  `ADR-0015` applied to the non-degradation envelope instead of the
  certificate margin), so a certified analytic root can sit in a
  computed-utility valley and lose up to that amount against the legacy
  Brent sample. Measured sweep (log grid of `beta` in [1.0e-6, 1.0],
  4000 random parameter draws per beta over roles, wages, transfer,
  spouse hours, conformism, `alpha`, weights, and seeds): the worst
  relative loss of the derivative result versus the legacy result
  follows about `2.0e-16 / beta`, crossing the `1.0e-11` envelope
  between `beta = 2.0e-5` (1.11e-11) and `2.5e-5` (9.4e-12) and
  measuring 1.5e-13 at `beta = 1.0e-3`. The floor is taken at the
  `CES_CERT_MIN_BETA` decade, where the analytic bound (1.1e-12) and
  the measured worst loss sit an order of magnitude inside the
  `1.0e-11` envelope (at the measured crossing a finite-sample worst
  case would certify with zero margin); the sub-floor band runs the
  bitwise fallback. The other specs have O(1) value condition numbers
  and need no floor.
- Solver algorithm (the derivative solve), a two-tier accuracy
  contract: tier-1 returns are enclosure-certified within
  `BEST_RESPONSE_TOL` of the true optimum (the `MDR-0002`
  `current-delta` resolution, i.e. the model's documented
  best-response resolution); tier-2 (the full solve) returns are
  certified at `DERIVATIVE_RESPONSE_TOL = 1.0e-8` hours (a solver
  constant, not a model parameter) or are a certified boundary point.
  In the tier-1 rules below `tol1 = BEST_RESPONSE_TOL` and "the
  optimum" reads as the maximizer of `U` over the closure of the
  feasible interval (where the maximum sits at a guard-removed
  endpoint, its supremum point); the returned hours are always
  feasible.
  1. Tier-1 seed certificate (runs first, right after the
     applicability gate): two cheap derivative sign probes
     `g(h_start - tol1)` and `g(h_start + tol1)` (the
     `_best_response_gradient_sign` probes of step 5; no objective
     value, no curvature; a probe that leaves the guarded domain is
     skipped as `NaN`) certify the seed and return it. Rules, sound
     under the non-increasing `g` certificate: both probes evaluable
     -- certify iff `g(h - tol1) >= 0 >= g(h + tol1)` (a root lies in
     `[h - tol1, h + tol1]`); only the right probe evaluable and
     `h_start <= tol1` (the feasible interval extends at most `tol1`
     to the left of the seed) -- certify iff `g(h + tol1) <= 0`;
     only the left probe evaluable and `h_start >= 1 - tol1` --
     certify iff `g(h - tol1) >= 0`. The one-sided rules include the
     feasible boundary seeds `h_start == 0` and `h_start == 1`, which
     certify at ONE probe cost (the out-of-domain probe is skipped at
     once); the `h_start <= tol1` / `h_start >= 1 - tol1` domain
     conditions are required for soundness (a probe skipped by a
     numerical guard far from the domain end must not certify a seed
     whose optimum lies outside the window). A FEASIBLE seed is
     required: at a guard-removed endpoint (`x(0) == 0` with
     `h_start == 0`, `Q(1) == 0` with `h_start == 1`) the seed is
     infeasible and the optimum may be the unattainable supremum of
     step 2, so no tier-1 certificate exists and the full solve runs.
     A flat objective (`g == 0` at both probes) certifies and keeps
     the seed, which is bitwise the legacy tie/seed return. The
     previous initial fast path of this solve (a seed Newton step
     `abs(g/g') <= DERIVATIVE_RESPONSE_TOL` confirmed by the probes at
     `h +/- DERIVATIVE_RESPONSE_TOL`) is SUBSUMED and dropped: under
     the non-increasing `g` certificate an enclosure at `+/-
     DERIVATIVE_RESPONSE_TOL` implies the tier-1 enclosure at `+/-
     tol1` wherever the seed is feasible and the wider probes are
     evaluable, the one-sided tier-1 rules cover the domain-end cases,
     and the residual case (computed-`g` noise rejecting the wide
     probes while the narrow ones enclose) is re-checked at the same
     probe cost by the tier-2 Newton-step certificate of step 5, so no
     case is lost.
  2. Feasible interval `[0, 1]` intersected with `x > 0`, `Q > 0`
     under the exact guards: the lower endpoint is removed only by
     `x(0) == 0` (`B == 0` with `A > 0`) and the upper only by
     `Q(1) == 0` (`h_spouse == 1`). At a guard-infeasible endpoint the
     analytic one-sided LIMIT of `g` is used for bracketing only when
     it is unambiguous in the bracketing direction: positive at the
     lower end (`+inf` at `x -> 0+` for Multiplicative, for the
     weighted specs when the `1/x` coefficient `alpha*A` is positive
     (the `(1-alpha)*alpha*A` coefficient of the payer quirk branch
     disappeared with `MDR-0019`), for
     `Additive` and `CES` `beta < 1` when `alpha > 0`, for `CES`
     `beta == 1` at `alpha == 1`; or a finite positive limit, e.g. the
     `CES` `beta == 1` value `D / ((1-alpha) * Q(0))` plus the norm
     slope `n'(0)`), negative at the upper end (`-inf` at `Q -> 0+`
     whenever a `1/Q` or `1/sqrt(Q)` coefficient is negative, i.e.
     `alpha < 1` outside `CES` `beta == 1`; or a finite negative limit,
     e.g. `alpha == 1` with material `x` or the `CES` `beta == 1` value
     `D / (alpha * x(1))` plus `n'(1)`). When the limit is zero, points
     toward the infeasible endpoint (the unattainable supremum, e.g.
     `alpha == 0` with `B == 0` at the lower end, where `U` rises
     toward the infeasible `h -> 0+`), or is indeterminate the solve
     falls back to legacy. (A near-boundary SEED in that corner, `0 <
     h_start <= tol1`, is tier-1-certified by the one-sided rule of
     step 1 when `g(h_start + tol1) <= 0`, which keeps it within
     `tol1` of the unattainable supremum point and is bitwise the
     legacy anchor return there; only the infeasible seed
     `h_start == 0` and interior seeds reach this step.)
  3. Boundary optima: a feasible endpoint with a strictly signed
     derivative is the optimum (`g <= 0` at the lower end selects
     `h = 0`, `g >= 0` at the upper end selects `h = 1`). The endpoint
     sign comes from the cheap derivative sign probe; the endpoint
     objective value is evaluated only when that endpoint is selected
     and is validated there (see the acceptance rule). An exactly zero
     boundary derivative (the demonstrably flat objective; the
     historical example was the `MultiplicativeWeighted` payer with
     `alpha == 1`, constant under the quirk branch removed by
     `MDR-0019`, while the unified form there is `x` and no longer
     flat) falls back to the legacy tie/seed behavior (a fully
     flat objective is already kept by the tier-1 certificate of step
     1, bitwise the legacy tie/seed return).
  4. Interior: bracket `[a, b]` with `g(a) > 0 > g(b)` (seed sign on
     one side, the opposite endpoint or its analytic sign on the other;
     one endpoint evaluation is skipped when the seed sign already
     covers that side). Safeguarded Newton from the feasible interior
     point nearest `h_start` (or the midpoint): `h_new = h - g/g'` only
     when `g' < 0` is finite, `h_new` lies strictly inside `[a, b]`,
     and the step moves the current point by more than
     `DERIVATIVE_RESPONSE_TOL` (a stalled step bisects), otherwise
     bisection; each new evaluation tightens the bracket by the
     derivative sign, so every step shrinks the bracket strictly and
     the width certificate of step 5 terminates within the cap. (An
     earlier draft restricted Newton to the central 90 percent of
     `[a, b]`; that guard degenerates to pure bisection whenever the
     root hugs a bracket edge - the typical geometry, because
     undershooting Newton steps keep one endpoint glued to the root -
     and measures at 20+ evaluations instead of 5 to 8, failing the
     `TASK-0023` performance gate. The strict-interior test with the
     stall floor keeps the safeguard's purpose and restores quadratic
     convergence.) At most 40 iterations; on the cap, non-finite
     curvature, unrepresentable progress, or any failed intermediate
     check the solve falls back.
  5. Termination and candidate certification (two certificate kinds):
     (a) the probe sign-enclosure - `abs(g/g') <= DERIVATIVE_RESPONSE_TOL`
     (the Newton-step exit) or an exact computed root of `g`, with both
     enclosure probes at `h +/- DERIVATIVE_RESPONSE_TOL` evaluable and
     enclosing (`g(h-tol) >= 0 >= g(h+tol)`); (b) at the width exit -
     the maintained sign bracket `g(a) > 0 > g(b)` of width `<=
     DERIVATIVE_RESPONSE_TOL` with the current `h` in `[a, b]`, which
     encloses the root within `DERIVATIVE_RESPONSE_TOL` of `h`. At the
     width exit, WHERE BOTH probes at `h +/-
     DERIVATIVE_RESPONSE_TOL` are evaluable (inside the guarded domain)
     the enclosure signs `g(h-tol) >= 0 >= g(h+tol)` are required
     before acceptance; a violation is possible only under numerical
     non-monotonicity of the computed `g` (e.g. the small-beta
     jaggedness that the `CES` floor above removes) and falls back to
     legacy. Under the non-increasing `g` certificate this check can
     never fail at a width exit (`h - tol <= a` and `h + tol >= b`), so
     it is a pure noise guard and rejects no legitimate case. WHERE a
     probe is skipped by the feasible-boundary guards (returns `NaN`,
     e.g. the open-boundary geometry `x(0) == 0` where `h - tol` leaves
     the feasible interval) the sign-bracket certificate is accepted. A
     bracket-converged point that satisfies neither certificate falls
     back. The idempotence (a re-solve at a returned point returns it
     bitwise) applies to the probe-certified exits and to tier-1
     returns (the same probes re-certify), which is what makes the
     alternating loop settle on bitwise fixed points; a
     sign-bracket-certified width-exit point is within
     `DERIVATIVE_RESPONSE_TOL` of the root but need not re-certify
     through the probe enclosure (it usually does through tier 1).
  6. Acceptance: the candidate must be feasible with a finite positive
     objective value computed in the same pass; the sign certificates
     (bracket signs, enclosure) are re-checked from their stored
     evidence without redundant evaluations (the width-exit enclosure
     probes of step 5 are that evidence, evaluated once at
     termination), and a selected boundary endpoint re-confirms its
     probed sign in the full evaluation that computes its value; the
     candidate
     value must reach every evaluated feasible endpoint value and the
     evaluated seed value to within 32 ulps at the comparison scale.
     Any inconsistency falls back.
- Numerical gate (fail open to legacy): every full derivative
  evaluation computes `(g, g', value)` in one pass over the exact
  `x`, `Q`, and `norm` groupings of the call overload (the value is
  bitwise `obj(h)`), and requires `x >= floatmin`, `Q >= floatmin`, the
  material intermediates finite and normal, finite `g` and `g'`, and a
  finite positive value at least `floatmin` (the `_envelope_peak`
  subnormal-guard style of `ADR-0015`). A violation abandons the solve.
  Derivative sign probes (the enclosure checks of steps 1 and 5) need
  only the SIGN of `g` and compute it division-free: the probe result is
  the sign-equivalent residual of `g` multiplied through by the spec's
  positive denominator `den` (with `n' = -2 * conformism * norm_weight
  * (h - norm_hours)`, `r = sqrt(x)`, `s = sqrt(Q)`, `m = alpha*r +
  (1-alpha)*s`, `D = alpha*A - (1-alpha)`, `S = alpha*x + (1-alpha)*Q`
  for `beta == 1` and `S = alpha*x^beta + (1-alpha)*Q^beta` otherwise):
  Multiplicative (`den = 2*x*Q`) `A*Q - x + 2*n'*x*Q`;
  MultiplicativeWeighted (`den = x*Q`, both roles since `MDR-0019`
  removed the payer quirk branch) `alpha*A*Q -
  (1-alpha)*x + n'*x*Q` (the historical quirk form of the payer was
  `(1-alpha)*(alpha*A*Q - x) + n'*x*Q`); Additive
  (`den = m*r*s`) `0.5*(alpha*A*s - (1-alpha)*r) + n'*m*r*s`; CES
  `beta == 0.5` (`den = m*r*s`) `alpha*A*s - (1-alpha)*r + n'*m*r*s`;
  CES `beta == 1` (`den = S`) `D + n'*S`; CES general (`den = S*x*Q`)
  `alpha*A*x^beta*Q - (1-alpha)*Q^beta*x + n'*S*x*Q` (two `pow` calls,
  no division). The probes carry the point guards (`h` in `[0, 1]`,
  `x >= floatmin`, `Q >= floatmin`, no spouse guard), require the
  positive denominator products (`x * Q`, or `sqrt(x) * sqrt(Q)`)
  finite and normal and the residual finite, and are skipped rather
  than fatal when they fail, so a numerically odd probe cannot abort an
  otherwise sound solve; it can only withhold the enclosure, which
  routes the case to the interior iteration or to legacy. Soundness of
  the sign form: the probe sign is the analytic sign of `g` up to the
  rounding of this MULTIPLIED-THROUGH form, a different rounding of the
  same analytic expression than the Newton loop's `g`. Every residual
  term is exactly `den` times the corresponding `g` term, so the
  scaling does not change the signal-to-noise ratio of the probe
  signals (the probe signals at `+/- DERIVATIVE_RESPONSE_TOL` sit
  `tol / eps` above the rounding noise of the residual form, as the
  direct form's signals sat above the computed-`g` noise through the
  `1 / Q` terms; the tier-1 signals at `+/- BEST_RESPONSE_TOL` scale
  likewise). A spurious sign flip therefore needs BOTH probe signals
  within rounding noise of zero, in which case the true root lies in
  the probe window up to noise / `|g'|`, the same class of argument as
  the recorded noise-constant note above. Measured: the adversarial
  scan of the sign forms (3,835,040 draws over every eligible spec and
  the adversarial corners, BigFloat analytic-sign reference) finds no
  probe sign flip at all (6,162,489 probe signs exact), no tier-1
  enclosure violation (959,227 certified seeds, all strict analytic
  enclosures within `BEST_RESPONSE_TOL`), and no tier-2 exit
  certificate violation (2,344,692 accepted candidates, all strict).
- The seeded-window path anchoring of `MDR-0002` no longer applies to
  eligible seeds OUTSIDE the tier-1 enclosure: such a seed is moved to
  the certified optimum of its objective, so the result there is no
  longer path-dependent on `h_start`. Seeds inside the tier-1
  enclosure keep their hours (tier 1), like the legacy anchor, but
  with a derivative sign certificate instead of the legacy
  value-probe heuristic: the legacy anchor kept a seed whenever its
  `+/- BEST_RESPONSE_TOL` value probes found no improvement (a
  two-sample heuristic that accepts seeds up to that resolution off
  the optimum), the tier-1 certificate proves the same resolution
  claim from the analytic sign enclosure. Only fallback cases keep the
  `MDR-0002` anchoring entirely.
- Equivalence protocol (the acceptance bar of this record): (1)
  ineligible cases are bitwise identical to the `MDR-0002` fallback
  expression (including `NaN` and signed zeros); (2) eligible solutions
  carry the two-tier accuracy certificates above (tier 1: the
  `BEST_RESPONSE_TOL` sign enclosure of the seed; tier 2: the
  own-response first-order condition at `DERIVATIVE_RESPONSE_TOL` or a
  certified boundary point) and a MEASURED two-sided value envelope
  against the legacy solve. Pointwise value dominance
  (`obj(new) >= obj(legacy) - 32 ulps`) is NOT a universal contract
  anymore: a tier-1 return and the legacy return both sit within the
  shared `BEST_RESPONSE_TOL` quality window of the optimum and can
  differ inside it (asymmetric peaks: value differences up to the
  window's value variation). The measured envelope
  `|U(new) - U(legacy)|` (relative at the comparison scale) over the
  200 fixture cases at their frozen reference state, the asserted
  regime grid of `test/test_utility_solver.jl`, and 32,728
  random-draw cases (all specs, roles, and parameter edges, half of
  them production-like seeds within 3e-4 of the optimum) is 1.85e-4
  (median 1.6e-10, 99% at or below 1.73e-4, no case above 2e-4); the
  envelope is the window's value variation at sharp peaks, mostly
  where the new solve wins and legacy's Brent search cannot resolve
  the optimum to its own `BEST_RESPONSE_TOL` argument tolerance. The
  loss side (legacy better) measures 9.35e-5 at its single worst draw
  with 99.9% of cases at or below 9.4e-7; the fixture stratum
  measures 6.8e-7. The test tolerances
  (`BEST_RESPONSE_VALUE_RTOL` in `test/test_utility_solver.jl` and
  `VE_OBJ_RTOL` in `test/test_bargaining_equivalence.jl`) are that
  envelope with headroom (5.0e-4). Draws above 1e-5 relative are
  reported with their parameters rather than hidden by a looser
  tolerance: the two-sided class (3,240 of 31,855) is the sharp-peak
  geometry of the draw grid (e.g. `conformism = 50`, `N_h = 1`,
  `alpha = 1` boundary optima at 1.76e-4; a `CES` `beta = 0.9` payer
  draw at `h_spouse = 0.999999`, `wage_self = wage_spouse = 0.05`,
  `h_start = 0.0121` at 1.85e-4, where the new solve returns the
  near-zero root and legacy's search samples the window edge), and the
  single loss draw above 1e-5 is the asymmetric-peak mode of tier 1
  (a `CES` `beta = 1e-3` payer at `alpha = 1e-6`, `wage_self = 0.01`,
  `wage_spouse = 0.0501`, `h_spouse = 0.999999`, `conformism = 1e-8`,
  `N_h = 0.039`, seed `1.0001e-4`: the seed certifies within
  `BEST_RESPONSE_TOL` of the sharp root at `1.3e-7` and legacy's
  probe finds a marginally better point inside the same window, a
  9.35e-5 relative value gap). The `CES` computed-jaggedness story
  (`CES_DERIVATIVE_MIN_BETA`, `CES_DERIVATIVE_LOSS_TOL`) governs
  computed-value comparisons in both tiers unchanged, and the
  feasible/non-finite classification is unchanged;
  (3) `mutual_best_response` outputs stay within two `eps` sweep
  budgets of the frozen reference per partner (2e-3 hours) and the
  downstream utility and gain deltas are measured and bounded
  explicitly in `test/test_bargaining_equivalence.jl`; (4) determinism
  of repeated runs and across thread counts is bitwise (new versus
  new).

## Consequences

- `src/resources/utility_functions.jl` owns the specialized
  `best_response_1d(::BestResponseObjective, ::Float64)` method and the
  private derivative helpers; the generic `best_response_1d(U::F, ...)`
  method and `maximize_1d` are unchanged and keep serving every generic
  caller and the fallback bit-exactly (`ADR-0022`).
- Model results change for eligible cases where the seeded search was
  path-anchored and the seed sits outside the tier-1 enclosure:
  committed hours move to the continuous optimum of the same objective
  there, at most two `eps` sweep budgets per partner in the measured
  comparisons (worst measured hours delta against the frozen reference
  9.6e-5 per partner). Seeds inside the tier-1 enclosure keep their
  hours at the `BEST_RESPONSE_TOL` resolution (bitwise the legacy
  anchor return wherever the legacy anchor also kept them). Fallback
  cases (the `alpha == 0` unattainable-supremum corner at interior and
  guard-open boundary seeds, unsupported betas including the
  `CES_DERIVATIVE_MIN_BETA` sub-floor band, and the
  injected numerical trouble paths) are bitwise
  unchanged; the flat `alpha == 1` payer quirk case (the quirk-branch
  flat objective removed under `MDR-0019`; the unified form is `x`
  there and no longer flat) was tier-1-certified and
  kept the seed, bitwise the legacy tie/seed return.
  Sub-validated-scale transfer gains can flip sign under the measured
  divergence (the `MDR-0016` fixture household 100 hidden band at
  1e-8 gains commits nothing on the live chain now; its demonstrated
  rescue stays pinned on the `MDR-0002` chain in
  `test/test_transfer_search.jl`). The `registry/model/discrepancies.md`
  row on the discrete
  NetLogo hill-climb versus the Julia solver is updated accordingly,
  and the ODD section Labour best response carries a short Julia-port
  note.
- The solver constant `DERIVATIVE_RESPONSE_TOL = 1.0e-8` is a
  numerical search parameter, not a model parameter; the same holds
  for the applicability floor `CES_DERIVATIVE_MIN_BETA = 1.0e-3`
  (`registry/model/parameters.md`).
- Validation and the performance gate are tracked in `TASK-0023`
  (implementation, equivalence battery, and the paired micro-benchmark
  of `benchmark/derivative_solver_benchmark.jl`). Measured same-revision
  gate after the review fixes (median of 31 rounds x 201 calls,
  7 specs x 2 roles x 2 parameter sets x 4 seeds: certified seed, warm
  start `+0.002`, and far starts `0.05`/`0.95`): applicable mix median
  2.43x to 2.5x across runs (379.7 ns to 156.5 ns in the final run),
  per-spec medians 1.44x (`CES` `beta == 0.5`) to 5.18x (`CES`
  `beta == 1`), routes 64.3 percent interior, 28.6 percent
  certified-seed, 7.1 percent boundary, 0.0 percent fallback (the
  width-exit noise guard never fired). Inapplicable cases, including
  the `CES_DERIVATIVE_MIN_BETA` sub-floor band, are bitwise identical
  at parity within measurement noise (0.99x to 1.01x), and both solver
  paths allocate nothing on every matrix cell and on the
  `mutual_best_response` pair. The converged-seed (fast-path) cost
  residual of the first implementation (the certified return cost
  1.1x to 1.7x of the legacy three-sample return for the sqrt-heavy
  specs, because one certified `(g, g', value)` pass plus the two
  enclosure sign probes evaluated more `sqrt`/division work than three
  plain objective samples) is closed by the follow-up optimization
  round: the division-free sign forms of the numerical gate above and
  the shared reciprocal per form between the `g_mat` and `g_prime_mat`
  divisions of the per-spec derivative pair (`ADR-0022`). Re-measured
  at the same paired matrix, every applicable cell is at or above
  parity (the previously sub-par `Additive` converged-seed cells at
  1.15x to 1.20x of the legacy anchor return), the applicable mix
  median is 3.42x, and the per-spec medians are 1.46x (`CES`
  `beta == 0.5`) to 4.33x (`CES` `beta == 1`) with `Additive` at
  1.48x; a lazy-value variant of the per-step derivative evaluation
  (objective value evaluated at acceptance instead of per step) was
  measured and dropped again (it regresses every interior cell), so
  the per-step `(g, g', value)` pass and its value guard stand as
  recorded. The final applicability
  narrowing is the `CES` floor `CES_DERIVATIVE_MIN_BETA = 1.0e-3` of
  the eligibility rule above (a correctness narrowing: sub-floor cases
  are bitwise legacy), recorded in `ADR-0022` alongside this record;
  the width-exit certificate is pinned by the reviewer repro (a
  skipped-probe sign-bracket exit within `DERIVATIVE_RESPONSE_TOL` of
  an independently bisected root of `g`) and the both-probe enclosure
  invariant of the regime grid (`test/test_utility_solver.jl`), the
  non-degradation envelope by the measured sweep and the widened
  quality checks over the eligible beta range.
- Kernel-level before/after (`benchmark/bargaining_kernel.jl`; full
  evidence in `benchmark/derivative_solver_validation.md`): `set_theta!`
  measures 0.0562 s to 0.0470 s on `ws_500` at one thread (1.20x) and
  1.04x to 1.17x across the workload/thread cells (no regression
  anywhere; the `ws_500` one-thread target of 1.15x is exceeded), and
  the production solver chain is 21.7 ms to 12.2 ms (1.78x). Because
  the chain is only about a third of this kernel after the `TASK-0021`
  transfer-search recovery, the kernel gain is Amdahl-bounded near
  1.2x, so the closing-phase `>= 1.5x` kernel aspiration is NOT
  reachable: the premise that labour solves dominate the bargaining
  kernel predates `TASK-0021`/`TASK-0022`. The justification of this
  record is therefore solution quality (the de-anchoring above) and
  worst-case solve cost, with a modest kernel win on top.

## References

- `odd_model_description.typ`, Material utility and conformity
  multiplier, Labour best response
- `gender_model_shocks_preferences.nlogox`, `calculate-utility`,
  `choose-bundle`
- `src/resources/utility_functions.jl`
- `src/systems/household_bargaining.jl`
- `benchmark/derivative_solver_benchmark.jl`,
  `benchmark/derivative_solver_validation.md`
- `MDR-0002`, `MDR-0003`, `MDR-0013`, `MDR-0014`, `ADR-0018`,
  `ADR-0022`, `TASK-0023`
