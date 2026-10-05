---
id: ADR-0022
title: Specialized derivative best response
status: accepted
date: 2026-09-30
supersedes: ""
superseded_by: ""
---

## Context

`MDR-0017` replaces the seeded Brent labour best response of `MDR-0002`
with a safeguarded derivative root solve for eligible utility regimes,
falling back to the unchanged seeded path otherwise.
`ADR-0018` established the prepared own-hours objective
`BestResponseObjective` (isbits, parametric on
`{S<:UtilitySpec,Recipient}` after `ADR-0029`, exact expression
grouping, no closures in the alternating loop) and
the zero-allocation discipline of the solver chain; the new solve must
stay inside that discipline: no allocations, no closures in the hot
path, type-stable concrete returns.

## Decision

Extend `ADR-0018` with a specialized dispatch method (this record does
not supersede `ADR-0018`):

- `best_response_1d(obj::BestResponseObjective{S}, h_start::Float64)`
  in `src/resources/utility_functions.jl` (resources layer, beside the
  objective and the generic solver; no new source file) is more specific
  than the unchanged generic `best_response_1d(U::F, h_start::Float64)`
  method, which keeps serving every generic caller and the fallback
  bit-exactly. On any fallback the specialized method runs exactly the
  generic body: `maximize_1d(obj, 0.0, 1.0, h_start,
  BEST_RESPONSE_WINDOW, BEST_RESPONSE_TOL)`, so ineligible cases are
  bitwise identical to the pre-change results.
- Private helpers, all allocation-free isbits code with concrete
  `Float64`/`Bool` returns and no closures in the hot path:
  `_derivative_applicable(::BestResponseObjective, ::Float64)` (the
  applicability regime gate of `MDR-0017`, including the `CES`
  `CES_DERIVATIVE_MIN_BETA` conditioning floor: below it the computed
  utility is too jagged for the non-degradation envelope and the case
  runs the bitwise fallback), `_derivative_seed_certificate(
  ::BestResponseObjective, ::Float64)` (the tier-1 seed certificate of
  `MDR-0017` step 1: two `_best_response_gradient_sign` probes at
  `+/- BEST_RESPONSE_TOL` and their one-sided domain-end rules, no
  objective value and no curvature), `_best_response_derivatives(
  ::BestResponseObjective, ::Float64)` returning `(g, g_prime, value)`
  in one pass over the exact `x`, `Q`, and `norm` groupings (the value
  is bitwise `obj(h)`), `_best_response_gradient_sign(
  ::BestResponseObjective, ::Float64)` (the derivative sign probe of
  the enclosure checks: the division-free sign-equivalent residual of
  the `MDR-0017` sign form, `_gradient_sign_residual`, whose sign is
  the analytic sign of `g` up to the rounding of the multiplied-through
  form), `_one_sided_gradient(
  ::BestResponseObjective, ::Bool)` (the analytic one-sided limit of
  `g` at a guard-infeasible endpoint), and `_derivative_best_response(
  ::BestResponseObjective, ::Float64)` returning
  `(candidate::Float64, ok::Bool)`. Since `ADR-0029` the role-dependent
  arithmetic of these helpers is dispatched through the role-dispatch
  family `_get_relevant_transfer`, `_eval_objective_function`,
  `_x_for_gradient`, `_A_for_gradient`, `_consumption_slope`,
  `_consumption_at_upper`, `_consumption_intercept`,
  `_lower_material_gradient`, and `_upper_material_gradient` (methods
  on the `BestResponseObjective{S,R}` and `AgentPayoffParams{G}`
  markers), which replaced the inline `recipient`-field branches and
  split the material endpoint limits out of `_one_sided_gradient`.
- Failure-open-to-legacy policy: every numerical-gate violation, every
  unsupported regime, every unbracketable or uncertifiable case returns
  `ok == false` and the caller runs the legacy expression. That
  includes the width-exit certificate's noise guard of `MDR-0017`
  step 5 (both enclosure probes evaluable but not enclosing falls
  back; a probe skipped by the feasible-boundary guards accepts the
  maintained sign bracket instead). The solver never returns `-Inf` and
  never throws on a weird objective.
- The derivative formulas use the coefficient `A` (and `B` only for the
  feasibility bookkeeping) while the `x` and `Q` values keep the exact
  expression grouping of the objective call overload (`MDR-0013`
  rounding discipline): the derivative side may be algebraically
  rearranged, the objective side may not. `A` and `B` are read through
  the role-dispatch helpers `_consumption_slope` and
  `_consumption_intercept` (with `_A_for_gradient` and `_x_for_gradient`
  for the derivative evaluation itself) instead of a `recipient` field
  test (`ADR-0029`). The shipped rearrangements
  are the shared reciprocal per form between the `g_mat` and
  `g_prime_mat` divisions of `_material_log_derivatives` and the
  multiplied-through division-free probe sign forms of
  `_gradient_sign_residual` (ulp-level rounding changes of `g`/`g'`
  and of the probe signals; the probe sign stays the analytic sign of
  `g` up to that rounding, see the `MDR-0017` sign-form note).

## Consequences

- `src/resources/utility_functions.jl` grows the specialized method,
  the constants `DERIVATIVE_RESPONSE_TOL`,
  `DERIVATIVE_RESPONSE_MAX_ITER`, and `CES_DERIVATIVE_MIN_BETA`, and
  the private helpers;
  `src/systems/household_bargaining.jl` keeps its `mutual_best_response`
  signature and loop unchanged and gains only citation updates.
- The zero-allocation contract of the solver chain is pinned by tests
  (`test/test_utility_solver.jl`, `test/test_household_bargaining.jl`)
  across all specs, roles, and fallback routes; `@inferred` pins the
  concrete return types.
- The evaluation-count discipline matters: the legacy seeded path
  returns after about three objective samples near a stationary seed,
  so the tier-1 seed certificate is built from two sign probes (no
  objective value, no curvature; one probe at a boundary seed) and the
  tier-2 solve keeps combined `(g, g', value)` evaluations few and
  reuses same-pass values and stored sign certificates instead of
  redundant acceptance evaluations.

- Placement note (`ADR-0028`): the file placement stated above is
  historical. The specialized `best_response_1d` method,
  `_derivative_applicable`, `_derivative_seed_certificate`,
  `_seed_certificate_probes`, `_derivative_response_accept`, and
  `_derivative_best_response` and the constants
  `DERIVATIVE_RESPONSE_TOL`, `DERIVATIVE_RESPONSE_MAX_ITER`, and
  `CES_DERIVATIVE_MIN_BETA` now live in
  `src/optim/labour_optimization.jl`; the derivative helpers stay in
  `src/resources/utility_functions.jl`.

## References

- `MDR-0002`, `MDR-0017`, `ADR-0003`, `ADR-0018`
- `src/resources/utility_functions.jl`
- `src/systems/household_bargaining.jl`
