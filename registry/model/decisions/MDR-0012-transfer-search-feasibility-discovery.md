---
id: MDR-0012
title: Transfer search feasibility discovery
status: superseded
date: 2026-09-29
supersedes: MDR-0005
superseded_by: MDR-0013
---

## Context

`MDR-0005` recorded the continuous transfer search porting NetLogo
`set-theta` with `calculate-payoff` (ODD section Transfer bargaining
(`set-theta`, `calculate-payoff`)): one unseeded in-repo Brent run
(`maximize_1d`) of the Nash product over the whole domain `[-1, 1]`,
with the status quo evaluated first and kept unless a feasible maximizer
beats it. That record named its own cost: a feasible band that the
sample points do not reach is not found and the household keeps the
status quo (the missed-feasible-band cost).

`benchmark/transfer_search_diagnosis.md` reproduces the cost on the
benchmark population (seed 1, 500 agents per gender, Watts-Strogatz
neighbors per side 2, rewiring 0.1, CES `beta = 0.5`): at initialization
the households at `SocialNetwork.women_entities` positions 85, 100, and
387 have strictly positive Nash payoffs at theta 0.0009, 0.0007, and
0.0001 (8.239360204105467e-9, 1.1554486667771662e-8, and
1.1575079773623812e-10) that the search misses: when every sample of the
unseeded Brent run returns `-Inf` (its first samples sit near
+/-0.236), it moves toward +1, never explores near zero, returns `NaN`,
and the household falls back to zero transfer. All sampled payoffs being
`-Inf` does not establish that all nonzero transfers are infeasible:
discovering feasible points is not what a local scalar optimizer
guarantees. Whether the tiny positive gains are labour-solver-tolerance
artifacts is assessed separately (`TASK-0014`).

The `MDR-0002` provisions touched here stay in force unchanged: the
continuous labour solver and its seeded window, and the box-free closure
discipline (a capture reassigned after closure creation boxes and turns
every objective sample into an allocating dynamic call).

## Decision

Supersede the search procedure of `MDR-0005` (this record supersedes
`MDR-0005`; `MDR-0005` is superseded by `MDR-0012`) with a staged
feasibility-discovery search in `bargain_transfer`
(`src/systems/household_bargaining.jl`): an explicit evaluation set
first, bounded refinement of promising regions second. This record
restates the transfer semantics it preserves and names the semantics it
changes.

Preserved exactly (restated from `MDR-0005`, still governed here):

- Objective: the `calculate-payoff` Nash product of the two utility
  gains over the outside options, computed by the unchanged
  `nash_product`, `equilibrium_payoff`, `individual_utility`, and
  `mutual_best_response` chain; `-Inf` when either gain is negative or
  non-finite (the `-1` sentinel replacement of `MDR-0005`). The
  evaluation record carries both gains and the solved hours but never
  forks payoff semantics.
- Feasible domain: the transfer stays bounded to `[-1, 1]` and
  `theta0 = clamp(theta_init, -1.0, 1.0)` is the status quo.
- Outside options: the zero-transfer labour equilibrium and its two
  utilities; the outside-option solve is reused bitwise as the
  status-quo labour equilibrium exactly when `theta0 === 0.0` (the
  strict bitwise guard keeps `-0.0` on its own solve).
- Warm-start rule: every candidate labour solve starts from the
  status-quo labour equilibrium `(hw_status, hm_status)`.
- Fallback and commit: the status quo is evaluated first and the status
  fallback `(theta0, hw_status, hm_status)` is returned unless a
  candidate beats the status-quo payoff strictly
  (`payoff_best > status_payoff`); the committed hours are the cached
  solve of the committed transfer, never a re-solve through the
  certificate. This keeps the ODD quirk 3 fix of `MDR-0005` (the status
  quo is evaluated and kept instead of resetting to zero transfer).
- The non-finite-outside fast path (skip the search and return the
  status fallback) and the certified `-Inf` payoff-only objective
  certificate (`_objective_prunable`, `_payoff_upper_bound`,
  `OBJECTIVE_CERT_MARGIN`, `ADR-0015`) are unchanged: the certificate
  may still prune exactly the points whose computed objective is `-Inf`,
  never the committed-hours path.

Changed:

- Search procedure: the single unseeded Brent run over `[-1, 1]` is
  replaced by two stages over one per-call evaluation cache keyed by the
  exact theta (`Dict{Float64,TransferObjectiveValue}`; the structure is
  recorded in `ADR-0016`):
  - Stage A (explicit evaluation set, deterministic order): the anchors
    `-1.0`, `0.0`, `theta0`, `+1.0`; then the anchor-neighbourhood grids
    `anchor + k * TRANSFER_LOCAL_STEP` and
    `anchor - k * TRANSFER_LOCAL_STEP` for `k = 1..TRANSFER_LOCAL_STEPS`
    around `0.0` and `theta0`, clipped to `[-1, 1]`; then the coarse
    grid `-1.0:TRANSFER_COARSE_STEP:1.0` ascending. Points already in
    the cache are deduplicated there; the cache is seeded at `theta0`
    with the status-quo evaluation itself (`status_payoff`,
    `hw_status`, `hm_status`), so the comparison base and the
    current-transfer evaluation are the same entry. A point skipped by
    the certificate is recorded as `-Inf`, soundly equal to the true
    objective there.
  - Stage B (bounded refinement): sort the sampled thetas; a sampled
    point is a weak local maximum when its cached payoff is finite and
    `>=` both neighbours' payoffs (a domain boundary compares its one
    neighbour; an isolated finite point qualifies). Adjacent
    equal-payoff weak maxima form a plateau; only the plateau member
    with the smallest `abs(theta - theta0)`, then smallest theta, is
    refined, and every plateau member stays a candidate. Each refined
    point gets one bounded `maximize_1d` run on the bracket `[lo, hi]`
    of its previous and next distinct sampled thetas, clamped to
    `[-1, 1]` (one-sided at the domain boundaries), with argument
    tolerance `TRANSFER_REFINE_TOL`. No unbounded Brent run over the
    domain remains anywhere.
- Candidate set and tie rule: candidates are every cached evaluation
  with finite payoff (all sampled points, including isolated feasible
  points and boundaries, plus the refinement results). The best is the
  largest payoff; an exact tie is broken by the smallest
  `abs(theta - theta0)`, then the smallest theta.
- Solver parameters (parameters of the numerical transfer search, not
  model parameters; changing them requires a follow-up MDR):
  `TRANSFER_COARSE_STEP = 1.0e-3` (coarse domain grid spacing),
  `TRANSFER_LOCAL_STEP = 1.0e-4` (anchor-neighbourhood grid spacing),
  `TRANSFER_LOCAL_STEPS = 200` (k range, giving +/- 0.02), and
  `TRANSFER_REFINE_TOL = 1.0e-5` (bounded-Brent argument tolerance of
  the refinement brackets, finer than the local grid).
  `TRANSFER_TOL` of `MDR-0005` is folded into `TRANSFER_COARSE_STEP`
  (the same value in the same role: the reference
  `delta-theta = 0.001` resolution); the `bargain_transfer` keyword
  `tol` now carries the refinement tolerance and defaults to
  `TRANSFER_REFINE_TOL`.
- Divergence from the reference implementation: NetLogo `set-theta`
  searches with two one-sided hill-climbs of step
  `delta-theta = 0.001` from the current transfer, stopping at the
  first non-improvement. The objective of ODD section Transfer
  bargaining is unchanged; the search is a numerical device. This
  record widens the deliberate search deviation recorded in
  `MDR-0005` (which replaced the climb and the first port's scan) to
  correct the missed-feasible-band cost that `MDR-0005` itself
  recorded.

Search-resolution limitation, recorded honestly: this is a sampled
feasibility discovery at the recorded resolution, not a certified
global optimizer. It guarantees evaluation of the anchors, the
+/- 0.02 anchor neighbourhoods at spacing `1.0e-4`, and the `1.0e-3`
domain grid, and it refines only around weak local maxima of that
sample; a feasible interval narrower than the sampling resolution and
separated from every sampled point and weak local maximum can still be
missed. The strict-improvement rule keeps the outcome safe (never worse
than the status quo) when that happens. This is a reference-quality
correction of the demonstrated misses, not a proof of global
optimality.

## Consequences

Model results change intentionally: households whose feasible transfer
band sits near zero (the demonstrated benchmark households 85, 100, and
387 at initialization) now discover it and commit a strictly improving
transfer instead of falling back to zero. Outcomes are no longer
bit-comparable to the `MDR-0005` search or to NetLogo; recorded
trajectory fixtures stay as baseline data and the old-versus-new deltas
are left to the follow-up validation package (`TASK-0014`).

The search costs about 2700 objective evaluations per household search
(each a full labour solve) instead of the 13 to 17 of `MDR-0005`, plus
one per-call evaluation cache and its refinement brackets; a kernel
regression of `set_theta!` is expected and accepted here
(`TASK-0014` tracks search-cost reduction). The evaluation closure
keeps single-assignment immutable captures, so the box-free discipline
of `MDR-0002` holds; the cache allocation is per call and per
household.

Tests follow the new contract: objective-level fixtures
(`mutual_best_response`, `outside_options`, `nash_product`,
`equilibrium_payoff`, `maximize_1d`) stay bitwise, `bargain_transfer`
is checked by result-validity invariants, determinism, the search
contract over the cache, and regression fixtures for the three
demonstrated households, with baseline-comparison statistics against
the frozen reference `test/reference_bargaining.jl` (a comparison
baseline since `ADR-0015`, not a correctness oracle). The ODD section
Transfer bargaining stays stale for the ported search as it did under
`MDR-0005` and `MDR-0002`.

Measured validation evidence (`benchmark/transfer_search_validation.md`,
`TASK-0014` package, in-place factual amendment allowed by
`ADR-0008`): the committed result is never beaten by a finer grid
(1e-4 over +/-0.02 around 0 and `theta0`, 2.5e-4 over `[-1, 1]`) on
44 benchmark households at tick 0, 1, and 5 (0/132 household-states;
all differences are same-band noise spikes within 3.5e-5 in theta).
The tiny gains are bitwise stable under tighter labour convergence
(`eps` 1e-3 to 1e-6, `max_sweeps` 100 to 1000, fixed-point residual
0.0) and the committed theta strictly improves the status quo at every
tolerance; they are genuine converged fixed points of the implemented
objective under the warm-start rule above, but the discrete
best-response map has several fixed points and a different warm start
can flip the smaller partner gain negative at the 1e-5 scale. On
matched household states (state injection verified bitwise through
identical initial-bundle utilities) NetLogo `set-theta` commits
`+0.001` for household 85 (rounded payoff 2.147e-9 against Julia's
2.141e-9 at the same transfer), commits zero for household 100 (its
objective has the improving band at 0.0005-0.0008 but the +/-0.001
probes miss it) and household 387 (whose band the reference's discrete
`choose-bundle` does not reproduce). Over 25-tick trajectories the new
search's nonzero commits are mostly transient (362 of 379 households
drop back to zero in the conformism-0 workload; the frozen old search
instead grows large transfers through the transfer-norm feedback).

## References

- `odd_model_description.typ`, Transfer bargaining (`set-theta`,
  `calculate-payoff`), Known implementation quirks
- `gender_model_shocks_preferences.nlogox`, `set-theta`,
  `calculate-payoff`
- `src/systems/household_bargaining.jl`
- `src/resources/utility_functions.jl`
- `benchmark/transfer_search_diagnosis.md`
- `MDR-0002`, `MDR-0005`, `ADR-0015`, `ADR-0016`, `TASK-0014`,
  `TASK-0016`
