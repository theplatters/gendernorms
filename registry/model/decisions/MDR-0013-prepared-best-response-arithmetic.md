---
id: MDR-0013
title: Prepared best-response objective arithmetic
status: superseded
date: 2026-09-29
supersedes: MDR-0012
superseded_by: MDR-0014
---

## Context

`MDR-0012` recorded the staged feasibility-discovery transfer search
and kept its objective chain (`nash_product`, `equilibrium_payoff`,
`individual_utility`, `mutual_best_response`) "unchanged" against
`MDR-0005`. Stage 2 of `TASK-0018` makes each individual labour solve
cheaper: the about 600 `mutual_best_response` solves per household-tick
are about 80 percent of the 12.5 s `ws_500` kernel
(`benchmark/bargaining_kernel.jl`, `MDR-0011`). Measured cost
breakdown (`benchmark/solver_equivalence_validation.md`): one
`individual_utility` evaluation costs about 55 ns and is dominated by
three runtime `pow` calls of the `CES` `beta == 0.5` material formula
(`x^beta`, `Q^beta`, `S^(1/beta)`, about 18.6 ns each against `sqrt`
1.9 ns and `exp` 3.1 ns); a near-equilibrium solve performs about 28
evaluations. This stage changes solver arithmetic (the material
formula and the objective's expression grouping), so the "objective
chain unchanged" claim of `MDR-0012` no longer holds and its record is
superseded here: bit-identity is replaced by a validated-equivalence
bar (the `MDR-0011` methodology class), with the equivalence protocol
and its measured evidence recorded below and in
`benchmark/solver_equivalence_validation.md`.

## Decision

Supersede `MDR-0012` (`MDR-0013` supersedes `MDR-0012`; `MDR-0012`
is superseded by `MDR-0013`). The transfer semantics are preserved and
restated below; the solver arithmetic changes are recorded as
validated-equivalent, not bitwise.

Preserved exactly (restated from `MDR-0012`, still governed here):

- Objective: the `calculate-payoff` Nash product of the two utility
  gains over the outside options, computed by `nash_product`,
  `equilibrium_payoff`, `individual_utility`, and
  `mutual_best_response`; `-Inf` when either gain is negative or
  non-finite. The evaluation record carries both gains and the solved
  hours but never forks payoff semantics.
- Feasible domain: the transfer stays bounded to `[-1, 1]` and
  `theta0 = clamp(theta_init, -1.0, 1.0)` is the status quo.
- Outside options: the zero-transfer labour equilibrium and its two
  utilities; the outside-option solve is reused bitwise as the
  status-quo labour equilibrium exactly when `theta0 === 0.0` (the
  strict bitwise guard keeps `-0.0` on its own solve).
- Warm-start rule: every candidate labour solve starts from the
  status-quo labour equilibrium `(hw_status, hm_status)`. Warm starts
  are not changed by this record.
- Fallback and commit: the status quo is evaluated first and the
  status fallback `(theta0, hw_status, hm_status)` is returned unless
  a candidate beats the status-quo payoff strictly
  (`payoff_best > status_payoff`); the committed hours are the cached
  solve of the committed transfer, never a re-solve through the
  certificate.
- Staged search (sample set, resolution, refinement, tie rule): the
  Stage A explicit evaluation set and deterministic order (anchors
  `-1.0`, `0.0`, `theta0`, `+1.0`, the anchor-neighbourhood grids at
  `TRANSFER_LOCAL_STEP` over `+/- TRANSFER_LOCAL_STEPS` steps around
  `0.0` and `theta0`, then the coarse grid at `TRANSFER_COARSE_STEP`),
  the Stage B weak-local-maximum plateaus with one bounded
  `maximize_1d` refinement per plateau at `TRANSFER_REFINE_TOL`, the
  candidate set of every cached finite payoff, and the tie rule
  (largest payoff, then smallest `abs(theta - theta0)`, then smallest
  theta) are all unchanged; the solver constants keep their
  `MDR-0012` values.
- Labour-solver semantics (`MDR-0002`): the seeded best-response
  window (`BEST_RESPONSE_TOL`, `BEST_RESPONSE_WINDOW`), the alternating
  update order, `eps`, `max_sweeps`, the clamping, and the
  keep-hours-when-no-feasible-sample rule are unchanged.
- Guard semantics: `individual_utility` returns `-Inf` on `x <= 0`,
  `Q <= 0`, own hours outside `[0, 1]`, or spouse hours outside
  `[0, 1]`, with identical trigger conditions; the certified `-Inf`
  objective certificate (`_objective_prunable`,
  `_payoff_upper_bound`, `OBJECTIVE_CERT_MARGIN`, `ADR-0015`, and the
  interval prefilter `ADR-0017`) still prunes exactly the points whose
  computed objective is `-Inf` and never touches the committed-hours
  path.

Changed:

- Prepared best-response objective (structure in `ADR-0018`):
  `mutual_best_response` now evaluates each 1-D best response through
  the isbits callable `BestResponseObjective`, which hoists every
  transfer- and spouse-dependent term (consumption coefficients,
  `Q` origin, the transfer/spouse norm products, the
  `MultiplicativeWeighted` payer exponent) out of the per-hours
  evaluation, and `individual_utility` delegates to it (one source of
  truth). This variant is CSE-style hoisting only: every formula keeps
  the exact expression grouping of the old `individual_utility`, so
  the evaluation is bitwise identical to it (the exact variant `1a` of
  the plan). The regrouped coefficient form (`x = A * h + B`,
  `Q = Q0 - h`, merged norm summand) and a hybrid were implemented and
  measured (evaluation kernels 9.8 / 8.9 / 7.9 ns for exact / hybrid /
  regrouped; end-to-end solve 463 vs 449 ns, about 3 percent) and are
  dropped here: the regrouped payer `x` flips the `x <= 0` guard
  trigger in subnormal-product corners (example: `wage_self = 1e-323`,
  `h = 0.6`, `1 - theta = 0.5` computes `x = 0` exactly and `-Inf` in
  the old grouping but `x = 5e-324` and a feasible bundle in the
  regrouped one), and the regrouped `Q`/norm flipped one zero-gain
  knife-edge commit in the fixture sample (solver case 116: the old
  chain commits theta 0 with payoff exactly 0.0, the regrouped chain
  falls back to theta -1 - a changed commit outside the accepted bar
  below). The measured gain does not justify that surface; the exact
  grouping keeps every guard trigger bit-exact on every input.
- `CES` material with exactly `beta == 0.5` is specialized to
  `s = alpha * sqrt(x) + (1 - alpha) * sqrt(Q); s * s`
  (`material(::CES, ...)` in `src/resources/utility_functions.jl`),
  replacing three runtime `pow` calls by two `sqrt` and one multiply.
  This is the single arithmetic change of this record and is
  validated-equivalent, not bitwise: `x^0.5` and `sqrt(x)` differ by
  up to one ulp on about 1 percent of values. Every other `beta` and
  every other `UtilitySpec` keeps its exact formula and evaluates
  bitwise as before.
- Equivalence protocol (the acceptance bar of this record): (1)
  same-state old-versus-new comparison of `individual_utility`,
  `best_response_1d`/`mutual_best_response` fixed points, gains,
  feasibility signs, `bargain_transfer` commits, and
  reference-evaluated payoffs at the committed bundles on the fixture
  cases and sampled `ws_500`/`heterogeneous`/`low_conformism`
  households at ticks 0/1/5; (2) fine-grid solution-quality rerun of
  `benchmark/transfer_search_validation.md` section 1 (the 0/132
  criterion); (3) the demonstrated households 85/100/387 of
  `test/fixtures/transfer_feasibility_households.toml`; (4) 25-tick
  old-versus-new trajectory aggregates on the three workloads; (5)
  determinism of repeated runs and across thread counts. A changed
  commit is accepted only when its reference-evaluated payoff is
  within the objective's measured jaggedness of the old one and in the
  same feasible band.
- A log-utility best-response objective (maximize `log(material) -
  norm penalty`) is NOT implemented: the two changes above already
  give a 3.7x solve speedup, and for `beta == 0.5` the specialized
  material leaves no transcendental for a log form to remove. A
  derivative or root solver stays a separate future decision.

## Consequences

Model results change only where the `CES` `beta == 0.5` material
applies, and only at ulp level; every other utility spec is bitwise
identical to the pre-`MDR-0013` chain (measured max delta exactly 0.0
over the fixture and workload sample). Measured equivalence evidence
(`benchmark/solver_equivalence_validation.md`, tables in
`benchmark/transfer_validation/st2_*.csv`):

- Same-state comparison (428 cases, 932,184 utility evaluations):
  zero feasibility-sign flips; for `CES` `beta == 0.5` utility deltas
  <= 1.2e-15 absolute (p99 2.2e-16), solver-hour deltas <= 9.6e-13,
  gain deltas <= 5.3e-13 with zero gain-sign flips; every other spec
  exactly 0.0. Of 428 commits, 397 are bitwise identical and 31
  changed (all `CES` `beta == 0.5`): 25 differ only in solved hours
  (<= 4.0e-13), 6 differ in theta by <= 3.7e-12 with
  reference-evaluated payoff deltas <= 2.9e-15 - all refinement
  jitter far inside one local-grid step and inside the objective's
  measured jaggedness.
- Fine-grid quality (132 household-states): the finer grid beats the
  committed result 0/132 (128 equal, 4 committed-beats-fine, maximum
  fine-grid theta distance 3.48e-5), identical to the `MDR-0012`
  criterion.
- Households 85/100/387 commit the same nonzero transfers as before
  (8.652475842498528e-4, 6.652475842498528e-4, 6.524758424985278e-5)
  with payoffs (1.002e-8, 1.452e-8, 4.23e-10) at or above the
  demonstrated candidates.
- 25-tick trajectories: `ws_500` and `heterogeneous` commit identical
  transfers in every household at every tick (hours jitter <= 2.6e-14);
  `low_conformism` differs in 224 household-ticks (out of 37,500),
  largest `|dtheta|` 8.7e-5, zero feasibility flips, reference
  payoffs within the measured local jaggedness, and the trajectories
  reconverge (no theta differences at tick 24). Hours-only jitter is
  <= 1.0e-7, below the solver's own 1e-4 resolution; at exactly
  zero-gain bundles the cross-evaluated payoff can flip between 0.0
  and `-Inf` at the 2e-15 level while the committed transfer is
  unchanged (documented knife edge).
- Determinism: repeated runs and 1-vs-8-thread runs are bitwise
  identical (state digests equal; `test/test_threading.jl`).

Performance (kernel medians of `benchmark/bargaining_kernel.jl ws_500
20 5`, `MDR-0011`): solve cost 1.7 us to 463 ns (3.7x, 28 utility
calls per solve unchanged), evaluation cost 55 ns to 12 ns; kernel
numbers and allocations in `benchmark/solver_equivalence_validation.md`.
The search's sample set, solve count, and objective-evaluation count
are unchanged by construction (the search driver is untouched).

Tests follow the validated-equivalence contract: objective-level
comparisons against `test/reference_bargaining.jl` and the fixture are
bitwise where the arithmetic is unchanged and tolerance-based (`veq`)
only for `CES` `beta == 0.5` (`test/test_bargaining_equivalence.jl`,
`test/test_bargain_certificate.jl`, `test/test_transfer_search.jl`);
the search-structure identity tests
(`test/test_transfer_search_identity.jl`) and the interval-certificate
soundness tests (`test/test_interval_certificate.jl`) are unaffected
(live-versus-live). Certificate soundness re-derivation: the
`_material_envelope` bounds of `ADR-0015` still dominate the computed
material - the sqrt/square path has fewer rounding stages than the
budgeted pow path (two `sqrt` and one correctly-rounded multiply
against three `pow`), the `beta == 0.5` amplification stays a factor
of two, and the whole in-band rounding budget remains far below
`OBJECTIVE_CERT_MARGIN` (about 4500 ulps of headroom), so the margin
and the envelope formulas are unchanged; the brute-force and
bound-versus-computed-utility tests assert this exactly.

## References

- `odd_model_description.typ`, Material utility and conformity
  multiplier, Transfer bargaining (`set-theta`, `calculate-payoff`),
  Labour best response
- `gender_model_shocks_preferences.nlogox`, `calculate-utility`,
  `choose-bundle`
- `src/resources/utility_functions.jl`
- `src/systems/household_bargaining.jl`
- `benchmark/solver_equivalence_validation.md`
- `MDR-0002`, `MDR-0012`, `ADR-0015`, `ADR-0017`, `ADR-0018`,
  `TASK-0018`, `TASK-0019`
