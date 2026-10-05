---
id: ADR-0029
title: Parametric role and gender markers
status: accepted
date: 2026-10-05
supersedes: ""
superseded_by: ""
---

## Context

`AgentPayoffParams` (the transient per-agent parameter object of
`ADR-0007`) carried the agent's sex as an `is_woman::Bool` field, and
`BestResponseObjective` (the prepared own-hours isbits callable of
`ADR-0018`, extended by the zero-allocation derivative solve of
`ADR-0022`) carried the partner role as a `recipient::Bool` field. Both
values are fixed at construction: the gender marker comes from the
agent, and the role is the sign of the relevant transfer. Every use
site was a runtime branch (`obj.recipient ? ... : ...`) selecting the
recipient or payer arithmetic inside evaluation and derivative helpers
that must stay zero-allocation and type-stable.

## Decision

Replace the two runtime marker fields with compile-time markers (this
record does not supersede `ADR-0018` or `ADR-0022`; it changes how the
role and gender facts are carried):

- Gender becomes a phantom type parameter `G<:Gender` on
  `AgentPayoffParams` (the `Male`/`Female` subtypes of the
  `Gender` dispatch root in `src/components.jl`), replacing the deleted
  `is_woman::Bool` field. `payoff_params(..., ::G) where {G<:Gender}`
  builds `AgentPayoffParams{G}`; the gender-dependent transfer sign is
  dispatched on the marker.
- The recipient role becomes the `Recipient::Bool` type parameter of
  `BestResponseObjective{S<:UtilitySpec,Recipient}`, replacing the
  deleted `recipient::Bool` field. The constructor splits statically
  into `BestResponseObjective{S,true}` and `BestResponseObjective{S,false}`
  returns, and `best_response_1d` takes `BestResponseObjective{S,R}`.
- The role-dependent arithmetic moves into a role-dispatch helper
  family (methods on the two type-parameter variants): the
  gender-dispatched transfer sign `_get_relevant_transfer`, the shared
  objective body `_eval_objective_function` behind the two call
  overloads, `_x_for_gradient` and `_A_for_gradient` for the derivative
  evaluation's `x` and `A`, `_consumption_slope`, `_consumption_at_upper`,
  and `_consumption_intercept` for the consumption geometry of the seed
  certificate and the boundary limits, and the per-spec endpoint limits
  `_lower_material_gradient` and `_upper_material_gradient` consumed by
  `_one_sided_gradient`.
- The now-dead `recipient::Bool` argument is dropped from
  `_material_envelope` (the envelope never used it after the
  `MultiplicativeWeighted` maximizer unified under `MDR-0023`).

Contracts unchanged: the zero-allocation solver chain, the exact
expression grouping of the objective (the `MDR-0013` rounding
discipline), the fail-open-to-legacy policy of `ADR-0022`, and the
`material(spec, x, Q, alpha)` extension signature all stay as recorded.

## Consequences

- Construction sites that passed `is_woman=` or set the `recipient`
  field (tests and benchmarks) migrate to the marker types:
  `AgentPayoffParams{Male}`/`AgentPayoffParams{Female}` via
  `payoff_params(..., Male())`/`payoff_params(..., Female())` and
  `BestResponseObjective{S,true}`/`BestResponseObjective{S,false}`.
- The rows of `registry/code/architecture.md` for
  `src/resources/utility_functions.jl`,
  `src/systems/household_bargaining.jl`, `BestResponseObjective`,
  `payoff_params`, and the internal helpers are updated to the
  parametric markers, with a row per helper of the role-dispatch family.
- Measured runtime impact (HEAD-vs-worktree, stabilized protocol, median
  of 4 processes): the prepared objective `obj(h)` and the solvers are
  neutral to much faster. For `MultiplicativeWeighted` the payer
  objective is about 20% faster, `best_response_1d` about 12% faster, and
  `mutual_best_response` about 42% faster, and payer/recipient symmetry is
  restored (both roles now share the `MDR-0023` Cobb-Douglas form). The
  zero-allocation contract of `ADR-0018`/`ADR-0022` holds throughout.
- The one-shot `individual_utility` (construct + evaluate; on the
  bargaining hot path `nash_product`/`equilibrium_payoff`/`set_theta!`)
  regressed by about 3 ns/call (~33%) for the cheap specs (multiplicative
  9.2 -> 12.5 ns, additive 9.5 -> 12.6 ns) and stays zero-allocation.
  Retained, not fixed: the cost is the small-union return of the static
  role split, not the 13-element `args` tuple hoist. A candidate codegen
  fix (two explicit constructor calls plus `@inline`, no tuple splat) was
  measured same-session and left the cheap specs unchanged while
  regressing `ces_beta_0.5`, so it was reverted.
- Future role-dependent objective arithmetic must go through the
  role-dispatch family instead of new `Recipient`-branching `if`s at
  call sites, so the static split stays in one place.
- Placement note (`ADR-0028`): the file placement stated above is
  historical (this record predates the `optim` layer split). In the
  post-split layout the role-dispatch family, `_get_relevant_transfer`,
  `AgentPayoffParams`, and `BestResponseObjective` stay in
  `src/resources/utility_functions.jl`, `payoff_params` in
  `src/systems/household_bargaining.jl`, and the `Gender` dispatch root
  in `src/components.jl`. Placement only, the markers recorded here are
  unchanged.

## References

- `registry/code/decisions/ADR-0007-set-theta-query-extraction.md`,
  `registry/code/decisions/ADR-0018-prepared-best-response-objective.md`,
  `registry/code/decisions/ADR-0022-specialized-derivative-best-response.md`
- `registry/model/decisions/MDR-0023-fix-multiplicative-weighted-donor-quirk.md`
- `src/components.jl`, `src/resources/utility_functions.jl`,
  `src/systems/household_bargaining.jl`
