---
id: MDR-0023
title: Fix the multiplicative-weighted donor-branch quirk
status: accepted
date: 2026-10-05
supersedes: ""
superseded_by: ""
---

## Context

ODD section Material utility and conformity multiplier defines
`multiplicative including weights` as the intended Cobb-Douglas form
`x_i^(alpha_i) Q^(1-alpha_i) dot exp(norm)`, and its bullet records the
shipped NetLogo fact: the recipient branch of `calculate-utility`
matches that intent while the donor (payer) branch binds the outer
exponent to the whole product and computes
`((x_i^(alpha_i) dot Q))^(1-alpha_i)` (the wrong-parenthesis quirk).
ODD section Known implementation quirks item 4 lists that donor-branch
parenthesisation. Per `MDR-0003` the documented quirks are preserved as
reference behavior "unless a dedicated MDR explicitly fixes one", and
"Any quirk fix needs its own MDR stating which quirk item changes, what
the corrected behavior is, and what happens to comparability"; this
record is that MDR.

The quirk is not cosmetic: it makes the two partners of a household
face different utility surfaces for the same utility-function option
(the donor's material becomes `x^(alpha*(1-alpha)) * Q^(1-alpha)`).
`MDR-0017` recorded the log-derivative formulas of the safeguarded
derivative best responses with a separate `MultiplicativeWeighted` payer
row for the quirk branch (`g = (1-alpha)*(alpha*A/x - 1/Q)`,
`g' = -(1-alpha)*(alpha*A^2/x^2 + 1/Q^2)`), the matching multiplied-
through sign form `(1-alpha)*(alpha*A*Q - x) + n'*x*Q` with
`den = x*Q`, and the quirk-specific `_material_envelope` maximizer
`2*alpha/(1+alpha)` (the intended form's maximizer is `2*alpha`).

## Decision

ODD Known implementation quirks item 4 is FIXED in the Julia port.
For `MultiplicativeWeighted` both roles compute the intended
`x^alpha * Q^(1-alpha) dot exp(norm)` of the ODD bullet (the NetLogo
`calculate-utility` recipient form); the shipped donor form
`((x^alpha * Q))^(1-alpha)` is not replicated. Concretely:

- The prepared objective `BestResponseObjective` evaluates the one
  intended material `x^alpha * Q^(1-alpha)` for both roles (the
  `material(::MultiplicativeWeighted, ...)` method already computed
  that form; the quirk lived in the role branch of the pre-change
  `individual_utility`).
- The `_material_envelope(::MultiplicativeWeighted, ...)` maximizer of
  the certified `-Inf` transfer-objective certificate is
  `v* = clamp(2*alpha, 0, d)` for both roles (was
  `2*alpha/(1+alpha)` for the payer).
- The `MDR-0017` derivative formulas are unified on the intended form
  for both roles: `g = alpha*A/x - (1-alpha)/Q`,
  `g' = -alpha*A^2/x^2 - (1-alpha)/Q^2`, and the sign residual
  `alpha*A*Q - (1-alpha)*x + n'*x*Q` with `den = x*Q`. The payer quirk
  rows are removed from `MDR-0017`, which is amended in place under
  this record.

## Consequences

- Comparability is broken deliberately and visibly for the
  `multiplicative including weights` donor/payer cases: results diverge
  from NetLogo runs (which keep the quirk) and from pre-change Julia
  runs (which replicated it). This is an intended behavior fix, not an
  accident; the divergence is recorded in
  `registry/model/discrepancies.md` and in the `calculate-utility` row
  of `registry/model/processes.md`.
- The frozen test oracle `test/reference_bargaining.jl` is re-synced to
  the fixed spec in the same change (gender-marker dispatch; unified
  `MultiplicativeWeighted` material), and the 42
  `multiplicative_weighted` rows of
  `test/fixtures/bargaining_baseline.toml` are regenerated (they froze
  the quirk behavior); provenance is noted in the fixture header.
- `MDR-0017` is amended in place (the quirk rows of the derivative
  formulas, the concavity argument, the boundary-limit coefficients,
  and the sign forms are replaced by the unified forms; historical
  measurements keep their evidence, marked historical).
  `MDR-0003` cross-references this record as the quirk fix its clause
  requires.
- The ODD is updated alongside: the `multiplicative including weights`
  bullet and quirk item 4 now state the NetLogo fact and point at this
  record for the port.
- Historical benchmark measurements (`benchmark/report.md`,
  `benchmark/derivative_solver_validation.md`,
  `benchmark/bargaining_kernel_report.md`) were taken under the quirk
  surface and are marked historical there; nothing measured before this
  record is re-measured or reworded.
- Placement note (`ADR-0028`): the file references above predate the
  `optim` layer split; `material`, `BestResponseObjective`, and
  `_material_envelope` stay in `src/resources/utility_functions.jl` in
  the post-split layout. Placement only, the behavior fix recorded here
  is unchanged.

## References

- `odd_model_description.typ`, Material utility and conformity
  multiplier, Known implementation quirks item 4
- `gender_model_shocks_preferences.nlogox`, `calculate-utility`
- `src/resources/utility_functions.jl`
- `registry/model/decisions/MDR-0003-preserve-netlogo-quirks.md`,
  `registry/model/decisions/MDR-0017-safeguarded-derivative-best-responses.md`
- `test/reference_bargaining.jl`, `test/fixtures/bargaining_baseline.toml`
