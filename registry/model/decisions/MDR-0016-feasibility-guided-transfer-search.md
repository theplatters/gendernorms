---
id: MDR-0016
title: Feasibility-guided budgeted transfer search
status: accepted
date: 2026-09-30
supersedes: MDR-0015
superseded_by: ""
---

## Context

ODD section Transfer bargaining and NetLogo `set-theta` and
`calculate-payoff` define the objective. The bounded anchor-local search of
`MDR-0015` found the demonstrated near-zero feasible bands of benchmark
households 85, 100, and 387 (`test/fixtures/transfer_feasibility_households.toml`,
`benchmark/transfer_search_diagnosis.md`) but cost 0.236 s on the `ws_500`
kernel at one thread versus the historical pre-change level of 0.0627 s
(`benchmark/bargaining_kernel_report.md`).

Fair in-tree baseline measurement (`/tmp/opencode/gn_anatomy.jl`, `ws_500`,
20 ticks, 500 households, one thread, five measured repetitions, fresh
seed-1 worlds, discarded warmups, per household-tick): the pre-change
semantics driven through today's objective chain (one unseeded
`maximize_1d(objective, -1, 1, 1e-3)` plus status seed and
strict-improvement commit, with the certified pointwise pruning of
`ADR-0015`) measure R = 0.028-0.032 s kernel, about 2.8-3.2 us per
household-tick, NOT near the 6.3 us implied by the historical 0.0627 s
measurement: today's prepared objectives and specialized envelopes run the
same semantics about twice as fast. Their anatomy is 18.0 objective
records, 1.5285 full labour solves, and 16.4715 certified prunes per
household-tick (identical counts in the independent round-1 replica that
recorded R = 0.032239426 s). Acceptance is therefore
`max(0.0627, 1.10 * R)` = 0.0627 s. Extraction-only floor is 0.77 us per
household-tick (1373 allocation bytes), 1.36 us including the outside and
status labour solves.

The infeasible payoff plateau hides real near-zero feasible bands, but the
utility gains carry probe-placement information across their edges: true
stored gains at solved probes and certified bound gains at pruned probes.
Household 85 additionally showed that the guidance landscape is not
globally smooth (branch discontinuity, below), so guidance-based Brent
alone cannot be the discovery path.

## Decision

Production probe placement of `bargain_transfer` is feasibility guidance
(`ADR-0021`); the objective chain, warm starts, certified pointwise
pruning, the strict commit and tie rules (`_transfer_better`), cached
solved hours, task-owned `TransferSearchScratch`, and the explicit
`:discovery` mode are unchanged (`MDR-0014`, `ADR-0015`, `ADR-0017`,
`ADR-0019`). The gains `_transfer_gains` computes exactly once per
evaluation feed both the unchanged Nash payoff `_nash_from_gains`
(bitwise identical to `nash_product`) and the guidance values.

Final schedule constants (`src/systems/household_bargaining.jl`):

- Stage A anchors: `-1.0`, `0.0`, `theta0`, `+1.0`; then the exploration
  ladder `TRANSFER_EXPLORE_OFFSETS` = (0.0001, 0.001, 0.003, 0.03, 0.1,
  0.3) on both signs: near-anchor offsets cover 1e-4..3e-3 (the
  demonstrated bands: household 85 contains 0.001, household 387 contains
  0.0001, both hit directly and verified) and remote offsets cover
  0.03..0.3 coarse coverage. Both anchors get a ladder when
  `abs(theta0) > TRANSFER_ANCHOR_OVERLAP` = 0.002; otherwise one ladder
  only. Then the adaptive `TRANSFER_ADAPTIVE_OFFSET` = 0.0003 probe on
  exactly those sides of an anchor where guidance at `+/- 0.001` is
  `>= TRANSFER_GUIDANCE_MIN` = -2e-5 and strictly exceeds guidance at
  `+/- 0.0001`; this restores the sampled-neighbour bracket of
  household-100-style hidden bands (household 100 contains no ladder
  point and is rescued by Stage B) without two unconditional full solves
  per anchor.
- Guidance: `min(guidance_w / scale_w, guidance_m / scale_m)` with
  `scale_i = max(abs(outside option_i), 1.0)`, non-finite values worst.
  Solved probes store their true gains; certified probes keep the exact
  `-Inf` payoff and `NaN` hours and store the partner bound
  `_payoff_upper_bound` minus that partner's outside option as separate
  guidance gains (they never rank or commit a point). Positive guidance
  implies a solved feasible point; a finite non-negative payoff
  corresponds to non-negative guidance.
- Stage B: weak local maxima of the sampled guidance sequence (negative
  values participate; a tiny-negative peak like -1e-5 is the
  "almost-feasible" signal, so the floor is `TRANSFER_GUIDANCE_MIN`),
  equal-guidance plateaus collapsed nearest to status, ranked by the
  unchanged candidate order; the top `TRANSFER_GUIDANCE_REFINEMENTS` = 1
  peak is refined with seeded Brent on the guidance over its
  sampled-neighbour brackets. The exact both-zero-gain zero point never
  refines (it is the outside point and conveys no positive or
  almost-feasible signal) but stays a candidate. A guidance weak maximum
  whose neighbors are infeasible must not be a discontinuous cliff: the
  certified bound gains decay smoothly, so Brent cannot shrink its
  bracket away from a hidden band as it does with an artificial `-Inf`
  guidance cliff.
- Stage C: only when a cached finite payoff strictly beats the status
  quo; the top `TRANSFER_MAX_REFINEMENTS` = 1 strictly improving
  candidate is refined with seeded Brent on the true payoff over its
  sampled-neighbour brackets. No-band households cost zero Stage C
  probes. Each refinement has at most `TRANSFER_REFINE_MAX_ITER` = 6
  iteration probes at the caller's tolerance (default
  `TRANSFER_REFINE_TOL` = 1e-5).
- Record cap `TRANSFER_SEARCH_MAX_EVALS` = 44: the status seed, three
  more anchors, `4 * 6` ladder records, four adaptive records, and
  `2 * 6` refinement iteration probes (refinement seeds are cached
  Stage A points). The worst case is exercised exactly by
  `test/test_transfer_local_search.jl`. Budget exhaustion never
  fabricates an infeasible value; every finite cached probe remains
  eligible for the final ranking.

Branch-discontinuity finding and its consequence: household 85's guidance
has a discontinuous labour-fixed-point branch; a refinement seeded near
0.000422 converged to an infeasible guidance peak and missed its band near
0.0009. Therefore guidance Brent is a refinement path only: direct ladder
hits remain part of the schedule (85 at 0.001, 387 at 0.0001), and the
dense-doubling and single-ladder-shape variants that dropped those points
missed fixtures. This returns the best candidate found within the record
budget, not a global optimum; there is no zero-transfer shortcut and no
automatic discovery fallback.

Measured acceptance evidence (same methodology as the baseline above;
`/tmp/opencode/gn_anatomy.jl`, `/tmp/opencode/gn_fixtures.jl`,
`/tmp/opencode/gn_ladder_hits.jl`, `benchmark/bargaining_kernel.jl`, 20
ticks, 500 households, five measured repetitions): `ws_500` kernel median
0.0549-0.0569 s at one thread (gate 0.0627 s) and 0.0153 s at eight
threads; `heterogeneous` 0.0524 s and 0.0141 s (historical references
0.0562/0.0121 s). Anatomy per household-tick: 15.02 objective records,
9.51 full labour solves (including the outside/status solve and 0.0006
separate status solves), 5.51 certified prunes, 1662 allocation bytes
(5.10 allocations). Fixture payoffs: 1.077029407459327e-8 (85, demo
8.239360204105467e-9 and demo2 2.1406731321933553e-9),
1.4766184762379934e-8 (100, demo 1.1554486667771662e-8),
4.424091598165963e-10 (387, demo 1.1575079773623812e-10); all three beat
their demonstrated values and 85/387 are hit by ladder points directly
while 100 is rescued by Stage B.

Test adjustments: `test/test_transfer_local_search.jl` was rewritten to
this driver contract (schedule constants, sampling order including the
adaptive rule, guidance/refinement budgets, record cap, hidden-band
rescue, demo-beating fixtures, cached hours, scratch reuse, mode
validation). Its schedule enumeration (`local_stage_a` /
`local_bracket`) is built from the test's own literal schedule
constants without calling the driver's enumeration helpers, and the
hidden-band synthetic uses production-realizable records only (solved
`-Inf` probes with tiny negative guidance flanking the band, finite
payoffs only with non-negative guidance). `test/test_bargaining_equivalence.jl`'s
`replay_search` is an integration replay of the `MDR-0016` evaluation
driving the production driver (both partner bounds computed per probe,
certified probes storing bound-minus-outside guidance gains,
production normalization scales); it verifies integration and ranking
while the schedule itself is pinned by the local-search contract test.
Before the mirror update its old evaluation diverged from live
production in 9 of 200 solver cases. No
assertion was weakened. `test/test_household_bargaining.jl` needed no
assertion changes (its invariants are search-agnostic); only stale
mechanism comments were re-cited.

## Consequences

Remote, disconnected, or narrow bands between ladder probes and unrefined
peaks can be missed (the explicit missed-band contract test keeps this
visible); failed probes never establish global infeasibility and the
result is the best candidate found, not a global optimum. The
search-resolution limitation of `MDR-0012`/`MDR-0014` (bands narrower
than the local spacing between samples) now applies to the coarser
production ladder as well and is recorded in
`registry/model/discrepancies.md`. Discovery mode is unchanged and stays
the explicit validation option for full-domain quality comparisons.
Fixtures 85/100/387 still beat their demonstrated payoffs; the full test
suite passes at one and eight threads; `TASK-0021` closes. Matched-state
NetLogo interpretation remains open under `TASK-0014`.
