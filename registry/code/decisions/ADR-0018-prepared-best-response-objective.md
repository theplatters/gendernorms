---
id: ADR-0018
title: Prepared best-response objective
status: accepted
date: 2026-09-29
supersedes: ""
superseded_by: ""
---

## Context

`MDR-0013` makes each individual labour solve cheaper. The old
`mutual_best_response` (`src/systems/household_bargaining.jl`) passed a
per-iteration closure `h -> individual_utility(h, partner_h, theta, p,
config)` into `best_response_1d`, so every objective sample recomputed
the transfer- and spouse-dependent terms (consumption coefficients,
leisure origin, the transfer and spouse norm products) and relied on
the `MDR-0002` no-boxing discipline of a `let`-bound capture to stay
zero-allocation. The per-sample cost breakdown (see
`benchmark/solver_equivalence_validation.md`) showed the recomputed
setup and the three runtime `pow` calls of the `CES` `beta == 0.5`
material dominate the evaluation.

## Decision

Introduce the prepared own-hours objective `BestResponseObjective` in
`src/resources/utility_functions.jl` (resources layer, beside
`individual_utility`): an isbits callable struct parametric on the
`UtilitySpec` type `S`, constructed once per `best_response_1d` call
from `(theta, h_spouse, self_params, config)`, hoisting every
transfer- and spouse-dependent term out of the per-hours evaluation
(consumption terms of `x`, the fixed spouse hours of `Q`, the transfer
and spouse norm products, the `MultiplicativeWeighted` payer exponent
`1 - alpha`, and the spouse-hours guard). The alternating loop of
`mutual_best_response` passes the callable directly (no closures, no
captures); the `MDR-0002` no-boxing discipline is now structural
rather than a discipline.

`individual_utility(h_self, h_spouse, theta, self_params, config)` is
re-expressed as constructing one `BestResponseObjective` and
evaluating it at `h_self`: one implementation of the NetLogo
`calculate-utility` formula (`ODD` sections Material utility and
conformity multiplier and Norm perception) serves the solver and every
caller (`nash_product`, `outside_options`, the gain recomputation, the
tests), so the validated equivalence of `MDR-0013` is a single-source
claim. The `material(spec, x, Q, alpha)` signature is kept unchanged:
it is the extension point tests use for counting probe specs and the
function the `_material_envelope` certificate bounds.

Every formula in the prepared evaluation keeps the exact expression
grouping of the old `individual_utility` (the exact variant of
`MDR-0013`; the faster regrouped coefficient form was measured and
dropped there), so the prepared evaluation is bitwise identical to the
old per-sample computation and every guard trigger is preserved
exactly. The single arithmetic change is the `CES` `beta == 0.5`
sqrt/square `material` specialization of `MDR-0013`.

## Consequences

- `src/resources/utility_functions.jl` owns the struct, its
  constructor, the call overload, and the delegating
  `individual_utility`; `src/systems/household_bargaining.jl` loses
  the closure-based objective construction in `mutual_best_response`.
- Zero-allocation per solve is retained (`test/test_household_bargaining.jl`,
  `test/test_utility_solver.jl`); the struct is stack-allocated and
  specialized on `S`, so the material dispatch is static per call
  site.
- The counting probe specs of `test/test_bargain_certificate.jl`
  (methods on the unchanged `material` signature) keep counting every
  evaluation; the non-finite-outside fast-path count test is
  unaffected.
- Future objective changes must edit the single prepared evaluation
  and its `material` formula together; the validated-equivalence
  protocol of `MDR-0013` applies to any arithmetic change there.

## References

- `MDR-0002`, `MDR-0013`, `ADR-0003`, `ADR-0015`
- `src/resources/utility_functions.jl`
- `src/systems/household_bargaining.jl`
