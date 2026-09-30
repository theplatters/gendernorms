---
id: MDR-0014
title: Tiered transfer-search sample set
status: superseded
date: 2026-09-30
supersedes: MDR-0013
superseded_by: MDR-0015
---

## Context

Stage 3 of the transfer-search performance recovery (`TASK-0018`) is
about the remaining `set_theta!` kernel cost after the Stage 2 solve
reduction of `MDR-0013`: `benchmark/bargaining_kernel.jl ws_500 20 5`
measures 7.07 s at 1 thread (pre-`MDR-0012` baseline 0.0627 s), split
per household-tick about 41% labour solves (about 686 solves at 426
ns), 30% certified-envelope bound evaluations (about 1426
`_payoff_upper_bound` calls at 149 ns each, pow-based), and 29% search
machinery (evaluation cache, sort, interval-slab prefilter,
enumeration). The evaluated sample set is the Stage A set of
`MDR-0012`/`MDR-0013`: anchors `-1.0`, `0.0`, `theta0`, `+1.0`, the
anchor-neighbourhood grids `anchor +/- k * 1e-4` for `k = 1..200`
(+/- 0.02 around `0.0` and `theta0`), and the coarse grid
`-1.0:1e-3:1.0`, about 2371 unique transfers per search at
`theta0 = 0`.

Measured geometry behind this record (throwaway drivers in
`/tmp/opencode/`, tables in `benchmark/transfer_validation/st3_*`):

- Feasible-band geometry (true objective sweeps at 1e-5 within
  +/- 0.002 of the anchors and 2.5e-4 over `[-1, 1]`, 23 households x
  ticks 0/1/5 of `ws_500`, `heterogeneous`, `low_conformism`): every
  narrow band (width 7e-6 to 3e-4) lies within `|theta| <= 0.0011` of
  an anchor (`0.0` or `theta0`); one `low_conformism` band is 2.1e-3
  wide reaching 0.00225 (household 447, tick 0); all other bands are
  wide (0.067 to 0.438) and lie anywhere in `[-1, 1]`. `ws_500` and
  `heterogeneous` feasible sets are exactly `{0.0}` plus the three
  demonstrated near-zero bands of the diagnosis households.
- Band-loss scan at 1e-4 over +/- 0.02 of both anchors on 360
  household-states (43 households x ticks 0/1/5 x 3 workloads): the
  tiered sample set of this record loses ZERO finite bands and ZERO
  better-than-status payoffs on every measured state (the only
  unhit finite set is the status-quo point itself, which is always
  evaluated and seeded).
- Certificate reach (this corrects an assumption of the plan): the
  interval/pointwise `-Inf` certificate of `ADR-0015`/`ADR-0017` does
  NOT certify the near-anchor region; the uncertified span around the
  anchors is about +/- 0.2 at conformism 10 (`ws_500`, where
  `z = conformism * (theta - N_theta)^2` stays below the
  envelope-versus-outside-option gap), so every coarse-grid sample in
  that span costs a full labour solve. The "coarse coverage beyond
  +/- 0.02 is already cheap" reading of the plan is wrong for
  `|theta| <~ 0.2`: cheap applies only outside the uncertified span.

## Decision

Supersede `MDR-0013` (`MDR-0014` supersedes `MDR-0013`; `MDR-0013`
is superseded by `MDR-0014`) with a tiered Stage A sample set. The
transfer semantics `MDR-0013` preserved are preserved again and
restated below; the sample-set semantics change and are recorded
here.

Preserved exactly (restated from `MDR-0013`, still governed here):

- Objective: the `calculate-payoff` Nash product of the two utility
  gains over the outside options, computed by `nash_product`,
  `equilibrium_payoff`, `individual_utility`, and
  `mutual_best_response`, under the prepared best-response arithmetic
  of `MDR-0013` (`BestResponseObjective`, the `CES` `beta == 0.5`
  sqrt/square `material`; the objective chain is untouched by this
  record). `-Inf` when either gain is negative or non-finite; the
  evaluation record carries both gains and the solved hours but never
  forks payoff semantics.
- Feasible domain: the transfer stays bounded to `[-1, 1]` and
  `theta0 = clamp(theta_init, -1.0, 1.0)` is the status quo.
- Outside options and their reuse: the zero-transfer labour
  equilibrium and its two utilities; the outside-option solve is
  reused bitwise as the status-quo labour equilibrium exactly when
  `theta0 === 0.0` (the strict bitwise guard keeps `-0.0` on its own
  solve). The status-quo entry at `theta0` is always evaluated and
  seeded into the cache before the search and stays the comparison
  base of the commit rule.
- Warm-start rule: every candidate labour solve starts from the
  status-quo labour equilibrium `(hw_status, hm_status)`.
- Fallback and commit: the status fallback `(theta0, hw_status,
  hm_status)` is returned unless a candidate beats the status-quo
  payoff strictly (`payoff_best > status_payoff`); the committed
  hours are the cached solve of the committed transfer, never a
  re-solve through the certificate.
- Candidate set and tie rule: candidates are every cached evaluation
  with finite payoff (sampled points and refinement results alike);
  the best is the largest payoff, an exact tie broken by the smallest
  `abs(theta - theta0)`, then the smallest theta.
- Stage B refinement mechanism: weak local maxima of the sampled
  payoffs, one bounded `maximize_1d` run per plateau of adjacent
  equal-payoff weak maxima (the member with the smallest
  `abs(theta - theta0)`, then smallest theta refines; every plateau
  member stays a candidate) at the unchanged `TRANSFER_REFINE_TOL`,
  on the bracket of the previous and next distinct sampled transfers
  clamped to `[-1, 1]` (one-sided at the domain boundaries).
- Labour-solver semantics (`MDR-0002`): the seeded best-response
  window (`BEST_RESPONSE_TOL`, `BEST_RESPONSE_WINDOW`), the
  alternating update order, `eps`, `max_sweeps`, the clamping, and
  the keep-hours-when-no-feasible-sample rule.
- Guard semantics and certificate soundness: `individual_utility`
  returns `-Inf` on `x <= 0`, `Q <= 0`, own hours outside `[0, 1]`,
  or spouse hours outside `[0, 1]`, with identical trigger
  conditions; the certified `-Inf` objective certificate
  (`_objective_prunable`, `_payoff_upper_bound`, the interval
  prefilter `_objective_interval_prunable`, `OBJECTIVE_CERT_MARGIN`)
  still prunes exactly the points whose computed objective is `-Inf`
  and never touches the committed-hours path. The specialized `CES`
  `beta == 0.5` envelope of `ADR-0019` still upper-bounds the
  computed `material` for every spec and role under the unchanged
  margin arithmetic (re-derived in `ADR-0019`), so a pruned point's
  computed payoff is still exactly the returned `-Inf`.

Changed:

- Stage A sample set (the tiered set of this record), in the same
  deterministic order as before (anchors first, then the anchor
  neighbourhoods, then the coarse grid ascending), deduplicated
  through the cache:
  - anchors `-1.0`, `0.0`, `theta0`, `+1.0` (unchanged),
  - the fine tier `anchor +/- k * TRANSFER_FINE_STEP` for `k =
    1..TRANSFER_FINE_STEPS` around `0.0` and `theta0`, clipped to
    `[-1, 1]`: spacing 1e-4 over the window `+/- 0.002` of each
    anchor (was spacing 1e-4 over `+/- 0.02`),
  - the coarse grid `-1.0:TRANSFER_COARSE_STEP:1.0` (unchanged,
    spacing 1e-3 over the whole domain, the `MDR-0012` reference
    `delta-theta` resolution), with the interval-certified slab
    prefilter of `ADR-0017` covering it as before.
- Named solver parameters (numerical search parameters, not model
  parameters; `registry/model/parameters.md`):
  `TRANSFER_FINE_STEP = 1.0e-4` and `TRANSFER_FINE_STEPS = 20` (the
  fine anchor-window tier; they replace `TRANSFER_LOCAL_STEP` and
  `TRANSFER_LOCAL_STEPS`, which are retired), while
  `TRANSFER_COARSE_STEP = 1.0e-3` and `TRANSFER_REFINE_TOL = 1.0e-5`
  keep their `MDR-0012` values.
- Per-region resolution (the discovery guarantee of this record):
  within `+/- 0.002` of `0.0` or `theta0` the sample spacing is
  1e-4, elsewhere 1e-3; every feasible band of width at least the
  local spacing contains a sampled transfer, and a sampled transfer
  inside a band makes the band a weak local maximum of the sample
  that Stage B refines to within `TRANSFER_REFINE_TOL` (for a
  unimodal band). The fine window covers the measured narrow-band
  extent (`|theta| <= 0.0011`, measured widths up to 3e-4) with a
  factor of about two and includes the measured 0.00225 band edge of
  `low_conformism` household 447 at fine resolution.
- Honest limitation, restated and narrowed: this is a sampled
  feasibility discovery at the recorded resolution, not a certified
  global optimizer. The resolution guarantee of `MDR-0012`/`MDR-0013`
  (1e-4 over `+/- 0.02` of the anchors) is narrowed to 1e-4 over
  `+/- 0.002`: in the annulus `0.002 < |theta - anchor| <= 0.02` of
  each anchor, and everywhere outside the fine windows, bands
  narrower than 1e-3 can be missed when they fall between coarse
  samples, and Stage B brackets there widen from 1e-4 to 1e-3 so a
  jagged objective can settle on a different spike. Measured model
  bands never sit in the annulus (the band-loss scan above), and the
  validation battery below re-checks this on the full state sample.
  The strict-improvement rule keeps the outcome safe (never worse
  than the status quo) when a band is missed.
- Envelope specialization (`ADR-0019`): `_material_envelope(::CES,
  ...)` evaluates the exact `beta == 0.5` case in the sqrt/square
  form of `material` (three runtime `pow` calls replaced by two
  `sqrt` and one multiply, and the analytic maximizer in closed
  form); every other `beta` keeps the general form. Bound values move
  by ulps only; a certificate decision can flip only between the
  exact `-Inf` sentinel and a solve that returns exactly `-Inf`
  (soundness parity of `ADR-0015`), never between `-Inf` and a
  finite payoff, so no commit changes.
- Evaluation-cache discipline (`ADR-0019`): only evaluated transfers
  (Stage A evaluations and Stage B probes) enter the cache; slab-
  covered samples are recorded in the sampled sequence with their
  exact `-Inf` payoff only. The sampled sequence, the Stage B
  brackets, and every cached value are unchanged; the cached key set
  shrinks (a refinement probe at a slab-covered transfer re-certifies
  to the same `-Inf` sentinel through the pointwise certificate, by
  the pointwise parity of `ADR-0017`).
- Equivalence protocol (the acceptance bar of this record; the
  `MDR-0013` staged search of `test/reference_transfer_search.jl` is
  the reference, since `MDR-0013` supersedes `MDR-0012` but keeps
  its sample set): (1) fine-grid solution quality of
  `benchmark/transfer_search_validation.md` section 1 on at least 44
  households x ticks 0/1/5 of `ws_500`, `heterogeneous`, and
  `low_conformism` (the finer grid must not beat the committed
  result materially); (2) the demonstrated households 85/100/387
  still commit nonzero transfers at payoffs at or above the
  demonstrated candidates; (3) same-state new-versus-reference
  comparison on the solver fixtures (including the 2/118 jagged-peak
  counterexamples of `benchmark/transfer_search_validation.md`),
  workload households at ticks 0/1/5, and 25-tick trajectory
  aggregates on `ws_500`, `heterogeneous`, and `low_conformism`
  (changed commits accepted only with per-case justification: same
  band or within the objective's measured jaggedness); (4)
  constructed adversarial bands (the `windowed_peak` machinery of
  `test/test_transfer_search.jl`, widths 3e-5 to 3e-3 and offsets
  0.0001 to 0.02 from the anchors) encoding the documented guarantee
  above, not aspiration; (5) determinism of repeated runs and across
  thread counts. A change that loses a materially better feasible
  band on a MODEL state reverts the responsible tier change.

## Consequences

Production is superseded by `MDR-0015`: bounded anchor-local search is
the default, while the discovery solver and output semantics of this
record remain available explicitly for offline validation
(`search=:discovery`, `ADR-0020`). The measurements below are historical
evidence for this record, not current production performance.

Model results change intentionally where the annulus coarsening and
the widened Stage B brackets change which spike of the jagged
objective is committed; the strict-improvement rule preserves the
never-worse-than-status-quo property and every missed band is
recorded as a resolution miss, not hidden. Outcomes are no longer
bit-comparable to the `MDR-0013` search; `test/reference_transfer_search.jl`
stays frozen as the reference-comparison baseline (its role changes
from bitwise identity oracle to quality baseline) and the bitwise
identity tests of `ADR-0017` are retired in favour of the search
contract and guarantee tests of the new sample set
(`test/test_transfer_search_reduction.jl`).

Measured validation evidence (`benchmark/search_reduction_validation.md`,
tables in `benchmark/transfer_validation/st3_*.csv`):

- Fine-grid quality (396 household-states, 44 households x ticks
  0/1/5 x three workloads): `ws_500` 0/132 and `heterogeneous`
  0/132 fine-grid-beats-committed (identical to the `MDR-0013`
  criterion), `low_conformism` 2/132 with gaps 1.0e-8 and 5.0e-7,
  both same-band noise spikes below the objective's measured local
  jaggedness (5.2e-7 and 9.2e-7) and both inside the committed
  point's feasible band; no materially better band is missed on any
  model state.
- Households 85/100/387 commit bitwise the same nonzero transfers as
  under `MDR-0013` (8.652475842498528e-4, 6.652475842498528e-4,
  6.524758424985278e-5) at payoffs above the demonstrated candidates
  (1.002e-8, 1.452e-8, 4.23e-10); the coarse tier still discovers all
  three bands.
- Reference comparison (599 identical-state comparisons): 577
  bitwise identical commits, 22 changed (19 solver fixtures, 3
  workload states, 0 fixture households); 10 changed in the new
  search's favour, 12 below the reference bundle's cross-evaluated
  payoff and every one of those within the local jaggedness and one
  refinement bracket of the reference commit (largest deficits 8.7e-10
  against jaggedness 1.0e-9, 1.0e-6 against 1.2e-6). The 2/118
  jagged-peak counterexamples (solver 171, solver 182) keep the
  reference commits bitwise. Trajectories (25 ticks): `ws_500` and
  `heterogeneous` commit identical transfers in every household at
  every tick (the 5-tick `ws_500` digest is bitwise equal to the
  `MDR-0013` digest); `low_conformism` differs in 363 of 37,500
  household-ticks (mean `|dtheta|` <= 3.3e-5, max 0.01, reconverging
  to 4 differing households at tick 24) with the aggregates within
  2e-4 of the reference sums at tick 0 and 4.6e-6 at tick 24. The one
  fallback-without-band row (`low_conformism` tick 2 household 350) is
  a 1.0e-5-wide band missing from BOTH searches' sample sets on that
  state (the frozen reference and the old Brent fall back identically
  there), the documented narrow-band miss class of the sampled search.
- Constructed adversarial bands (140 windowed cases, widths 3e-5 to
  3e-3 at offsets 1e-4 to 2e-2 from both anchors): the tests encode
  the recorded rule exactly - found whenever the band contains a
  sampled transfer (22/28 cases per narrow width, 28/28 at widths
  >= 1e-3), missable otherwise (the 6 sub-spacing misses per narrow
  width sit between coarse samples outside the fine windows).
- Determinism: repeated runs and 1-vs-8-thread runs are bitwise
  identical (digest 0x831181860bdd48e0); the full suite is green at
  both thread counts, `registry_check --strict` reports 0 warnings
  and 0 errors.

Performance (`benchmark/bargaining_kernel.jl ws_500 20 5`, 5
repetitions, contemporaneous `MDR-0013` baseline re-measured on the
same machine): kernel median 6.869 s to 2.510 s at 1 thread (2.74x)
and 1.599 s to 0.608 s at 8 threads (2.63x), `GN.run` 6.717 s to
2.543 s and 1.655 s to 0.540 s, allocations 100.2 KB to 55.0 KB per
household-tick. Per household-tick counters: sampled transfers 2381
to 2037.5, `evaluate!` calls 715 to 376.5, solves 686 to 347.6,
envelope-bound calls 1426 to 747.7 (149 ns to 9.2 ns per bound),
interval decisions 58 to 32. The 5x target is NOT met; the remaining
anatomy is 59% labour solves (the uncertified span of the
certificate, about `+/- 0.2` around the anchors at conformism 10),
3% envelope bounds, 10% certificate machinery, and 28% search
machinery and household work (`TASK-0020`).

## References

- `odd_model_description.typ`, Transfer bargaining (`set-theta`,
  `calculate-payoff`), Labour best response
- `gender_model_shocks_preferences.nlogox`, `set-theta`,
  `calculate-payoff`
- `src/systems/household_bargaining.jl`
- `src/resources/utility_functions.jl`
- `benchmark/search_reduction_validation.md`
- `MDR-0002`, `MDR-0012`, `MDR-0013`, `ADR-0015`, `ADR-0017`,
  `ADR-0018`, `ADR-0019`, `TASK-0018`
