---
id: MDR-0015
title: Bounded anchor-local production transfer search
status: superseded
date: 2026-09-30
supersedes: MDR-0014
superseded_by: MDR-0016
---

## Context

The user requests bounded-cost, anchor-seeded local search for production
instead of the full-domain discovery scan of `MDR-0014`. The latter costs
2.510 s for 500 households over 20 ticks at one thread, versus 0.063 s
for the historical unseeded Brent search. About 348 labour solves per
household-tick and enumeration of about 2038 transfers dominate that cost
(`benchmark/search_reduction_validation.md`).

ODD section 3.3.4 Transfer bargaining (`set-theta`, `calculate-payoff`)
defines the Nash objective and describes the reference's local +/-0.001
hill-climbs. ODD section 3.3.3 Labour best response describes `choose-bundle`.
The port already differs in the labour solver, payoff rounding, fixed
warm starts, and status fallback (`MDR-0002`, `MDR-0013`, `MDR-0014`).
The near-zero bands are real outputs of that implemented objective;
zero transfer is NOT an invariant (`benchmark/transfer_search_diagnosis.md`,
`benchmark/transfer_search_validation.md`).

## Decision

Supersede `MDR-0014` for production with a bounded anchor-local search
in `bargain_transfer`. Retain its discovery solver, unchanged, as an
explicit offline validation option (`search=:discovery`); the default
and `set_theta!` production path use `search=:local`. Structure is
recorded in `ADR-0020`.

Preserve the objective chain and arithmetic of `MDR-0013`, labour-solver
semantics of `MDR-0002`, domain `[-1, 1]`, clamped status quo, zero-transfer
outside options, exact reuse only at bitwise +0.0, fixed status-equilibrium
warm starts for every candidate, certified pointwise -Inf pruning, and
non-finite-outside fast path. Before any search, evaluate and seed the status quo;
commit only a finite candidate with strictly greater payoff, carrying
its cached solved hours without a re-solve. The candidate order remains
largest finite payoff, smallest `abs(theta - theta0)`, then smallest theta.

The production search contract is:

1. Sample anchors `-1.0`, `0.0`, `theta0`, `+1.0`, followed by the fine
   neighbourhoods around `0.0` and `theta0`: `anchor +/- k * 1e-4`,
   `k = 1..20`, clipped to the domain. These are the existing +/-0.002
   windows (`TRANSFER_FINE_STEP`, `TRANSFER_FINE_STEPS`). Overlaps,
   including coincident anchors, are evaluated once by exact cache keys;
   -0.0 and +0.0 remain distinct.
2. Instead of the unconditional 2001-point coarse grid, sample eight
   fixed exploration offsets on each side of each anchor:
   `TRANSFER_EXPLORE_OFFSETS = (0.004, 0.008, 0.016, 0.032, 0.064,
   0.128, 0.256, 0.512)`, clipped to the domain. These probes are a
   budgeted opportunity to reach broad remote bands, not global coverage.
   They are sampled even when all near-anchor probes fail.
3. Sort distinct sampled transfers. Identify finite weak local maxima
   and adjacent equal-payoff plateaus as in `MDR-0014`. A plateau's
   representative is its member nearest the status quo, then smallest
   theta. Only representatives with payoff >= the status payoff are
   promising; an equal-payoff status anchor can still refine.
4. Rank promising plateau representatives by the candidate order and
   refine at most `TRANSFER_MAX_REFINEMENTS = 4`. Each bounded Brent
   run uses the representative's previous and next distinct sampled
   neighbours (one-sided at domain boundaries), argument tolerance
   `TRANSFER_REFINE_TOL = 1e-5`, and
   `TRANSFER_REFINE_MAX_ITER = 24`. Every finite sampled or refinement
   evaluation remains a candidate, even if its plateau was not refined.
5. The explicit worst-case budget is `TRANSFER_SEARCH_MAX_EVALS = 216`
   distinct objective records including the seeded status quo: at most
   116 Stage A transfers and 4 * 25 new refinement probes. Brent's
   endpoints are already sampled and cached. The separate outside and
   status labour solves are not search probes. Reaching the iteration or
   refinement cap returns the best evaluated candidate; no unevaluated
   point is labelled infeasible or inserted as a fabricated -Inf value.

The discovery path retains the full `MDR-0014` sample set, interval
prefilter, unbudgeted plateau refinements, and its prior output semantics.
`TRANSFER_COARSE_STEP` now belongs to that validation path only. Changing
any production budget or offset requires a successor MDR, not silent
tuning. The optional `tol` must be finite and positive in both modes.

## Consequences

This deliberately removes the global 1e-3 discovery guarantee. Only the
fine anchor windows retain their sampling resolution; remote bands
between exploration probes, and even broad remote bands, can be missed.
At most four peaks receive refinement, which can also leave a better
off-grid peak unexamined. Failed probes are not evidence of global
infeasibility. A missed band keeps the exact status fallback, not a claim
of optimality. Outputs and trajectories may differ from the discovery
solver, especially at low conformism; this is an authorized search
tradeoff, not an arithmetic-equivalence claim.

Keep the demonstrated households 85, 100, and 387 improving above their
fixture candidates. Test exact sample order, deduplication, signed zeros,
ranking, caps (including tiny requested tolerances), cached commit hours,
fallbacks, scratch reuse, determinism, remote-band hits and explicit misses.
Compare identical states and trajectories against the retained discovery
solver on standard, heterogeneous, and low-conformism workloads and
measure the 500-household, 20-tick single-thread kernel. Record the measured
cost and solution losses in `benchmark/anchor_local_validation.md`.
`TASK-0020` tracks implementation and verification; no promise is made
that the old 0.063 s timing is recovered exactly.

The ODD continues describing NetLogo's reference algorithm, not this
production search deviation. No NetLogo code or model parameters change.

Measured implementation evidence (`benchmark/anchor_local_validation.md`,
tables `benchmark/transfer_validation/anchor_*.csv`): the existing ws_500
kernel harness improves from a freshly measured 2.47850 s to 0.23642 s
(10.48x, five repetitions, 500 households over 20 ticks, one thread).
The current-mode reproducible comparison measures local/discovery medians
0.23867/2.49490 s on ws_500, 0.21522/1.67510 s on heterogeneous, and
0.26706/6.56153 s on low_conformism. The old 0.063 s is not fully recovered.

Standard and heterogeneous outcomes match discovery bitwise on all 132
sampled states per workload and all 25 trajectory ticks. The three
near-zero fixtures still improve above their demonstrated candidates.
Low conformism has 11/132 changed sampled commits, seven below discovery
(maximum payoff deficit 6.85634e-6), and 664/12,500 changed trajectory
transfers. Shared-LOCAL-state checks reveal material search losses not
visible in the 44-household sample: household 71 at tick 0 has payoff
0.000634587 at local theta 0.128 versus discovery payoff 0.001275883 at
theta 0.117 (50.3% deficit), household 344 a 3.18056e-4 deficit.
These are accepted budgeted-search limitations, not numerical equivalence.
The largest trajectory |dtheta|, 0.911918 for household 83 at ticks 7/8,
is state-feedback divergence: both solvers return zero on that exact
local state. Discovery is the explicit option for experiments that cannot
accept lost search coverage. Repeat and 1/8-thread trajectory tables and
transfer/hours digests are identical across all three workloads; the
tests exercise the exact 216-record worst-case budget.
