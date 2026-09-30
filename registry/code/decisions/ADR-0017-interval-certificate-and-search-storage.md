---
id: ADR-0017
title: Interval-exclusion certificate and task-owned search storage
status: accepted
date: 2026-09-29
supersedes: ""
superseded_by: ""
---

## Context

The staged transfer search of `MDR-0012` (driver and per-call
evaluation cache of `ADR-0016`) dominates the `set_theta!` kernel. A
fresh profile of `benchmark/bargaining_kernel.jl ws_500 20 5` at 1
thread attributes the per-household-tick cost as follows: 2375
objective evaluations = about 1682 pointwise certificate rejections
(`_objective_prunable`, about 200 ns each, 28% of the kernel) plus
about 693 full `mutual_best_response` solves (about 1.7 us each, 69%
of the kernel, 99.6% of them proving `-Inf` that the envelope could
not), and 3-8% cache and sort churn (a fresh `Dict` fill of 268 KB and
a 47 KB `sort!(collect(keys(cache)))` of the 324 KB allocated per
`bargain_transfer` call; GC only 2.4%). Stage 1, recorded here,
addresses the certificate and the storage shares only; the solve share
needs cheaper solves and fewer samples and is deferred (`TASK-0018`).

`ADR-0016` specifically records a PER-CALL `Dict` cache and a fresh
sorted-keys vector per search, so replacing that storage strategy needs
its own record (`ADR-0008`); the search semantics of `MDR-0012` are
unchanged and this record does not touch them.

## Decision

1. **Interval-exclusion certificate (Stage A prefilter).**
   `_objective_interval_prunable(lo, hi, uw_out, um_out, pw, pm,
   config)` in `src/systems/household_bargaining.jl` returns `true`
   only when EVERY transfer of the closed interval `[lo, hi]` has
   computed Nash payoff exactly `-Inf`, failing open (`false`) on any
   doubt; `_payoff_interval_bound` computes the per-partner bound. The
   construction separates consumption and norm effects (neither
   endpoint's pointwise bound alone is valid: the two can oppose and an
   interior product can dominate): on a nonzero-sign slab with `r =
   abs(theta)` in `[a, b]` the payer bound uses `q = wage_self * (1 -
   a)`, `v = h_self`, `d = 1` and the recipient bound `q =
   max(wage_self, b * wage_spouse)`, `v = h_self + h_spouse`, `d = 2`,
   through the unchanged `_material_envelope`, times `exp(-z_min)`
   where `z_min = conformism * w_transfer * (closest - N_theta)^2` is
   the minimum norm penalty of the slab at `closest = clamp(N_theta,
   lo, hi)` in the operation order of `individual_utility`. `[lo, hi]`
   is split at zero: the zero point (both signed zeros) is a payer
   point for both partners under the strict `relevant_transfer < 0`
   test and is excluded only when the pointwise `_objective_prunable`
   would exclude it. One partner suffices (`nash_product` needs both
   gains non-negative); the payer is tested first and the recipient
   envelope is skipped when the payer certifies. The comparison is
   strict (a zero gain, including a signed zero, yields the finite
   payoff `0.0`) and inflated by `OBJECTIVE_CERT_MARGIN` twice: once
   for the Float64 bound error of `ADR-0015`, once for the few-ulp
   slack between the slab bound and the pointwise bound at a covered
   transfer. The soundness discipline of `ADR-0015` is kept unchanged:
   this bounds the computed Float64 utility, not the real formula; the
   normal-range and intermediate guards, the CES `beta >=
   CES_CERT_MIN_BETA` band, the alpha-endpoint rules, the zero-wage
   `q == 0` rule (exact `x <= 0 -> -Inf` by IEEE monotonicity), the
   unknown-`UtilitySpec` fail-open, and the non-finite-input fail-open
   all apply.
2. **Pointwise parity (solve-count and entry identity).** The
   prefilter must never remove a solve or change a cached evaluation:
   wherever the interval certificate returns `true`, the pointwise
   `_objective_prunable` returns `true` as well and the pre-change
   search would have recorded the identical `-Inf` sentinel. The
   certificate therefore verifies every `_payoff_upper_bound` guard at
   the slab's TIGHTEST corner too (smallest consumption `q_tight`,
   largest norm penalty `z_max`, their product above `2 * floatmin`),
   so the pointwise bound is finite at every covered transfer, and the
   doubled margin closes the boundary race of the strict comparison.
   The tight-corner material guard `_interval_normal_ok` admits one
   exact exception: when a partner's consumption range over the whole
   slab is exactly zero (`iszero(q_slack)` of `_payoff_interval_bound`),
   parity holds through that identical exact rule alone. The pointwise
   `_payoff_upper_bound` returns the same exact `0.0` bound through its
   own `iszero(q) && return 0.0` rule at every covered transfer (IEEE
   rounding is monotone, so zero slack consumption means zero
   consumption everywhere on the slab and `individual_utility` is
   exactly `-Inf` there by its `x <= 0` guard), never consulting the
   material envelope, so the identical strict `0.0 < outside`
   comparison certifies on both sides, spec-independently: a pure-zero
   slab of an unenveloped `UtilitySpec` certifies soundly. Mixed
   zero/nonzero consumption ranges (`q_slack > 0` with `q_tight == 0`)
   do not qualify: the pointwise certificate certifies only the
   exactly-zero transfers there, so parity genuinely fails and both
   paths fail open. Consequences of the parity discipline, recorded
   honestly: slabs
   mixing exactly-zero consumption (`abs(theta) == 1`) with positive
   consumption fail open (the subnormal-consumption band there makes
   the pointwise certificate fail open on real transfers), slabs whose
   tight corner has subnormal consumption or subnormal/underflowing
   `exp` fail open (the extreme-conformism and extreme-transfers
   regime), and below the CES band and on unenveloped specs the
   material path fails open (only the exact zero-consumption rule
   still certifies there). Nothing of this is reachable in the
   measured model workloads (wages `>= 0.05`-scale, conformism `<=
   50`, so `z <= ~200` and every bound stays normal); the cost is
   extra bisection near the domain boundaries.
3. **Prefilter use in `_transfer_search!`.** The Stage A grid runs
   (the anchor neighbourhoods at `TRANSFER_LOCAL_STEP` and the coarse
   grid at `TRANSFER_COARSE_STEP`) are partitioned into certified
   slabs before the enumeration by `_transfer_cover_slabs!`, a simple
   adaptive bisection split at zero that stops below
   `TRANSFER_SLAB_MIN_SAMPLES = 32` grid samples (an interval decision
   costs about one to two pointwise decisions, and the floor is the
   measured break-even of the `ws_500` workload: below about 32 samples
   per leaf the probe overhead dominates while the certifiable tail
   slabs are found at coarse bisection levels either way). The
   enumeration loops'
   arithmetic and order are untouched: `_transfer_sample!` consults the
   slabs per sample, records every covered transfer with its exact-key
   cached `-Inf` sentinel without an `evaluate!` call, and appends the
   key to the sampled sequence either way (deleting an infeasible
   neighbour would enlarge a finite maximum's Brent bracket and change
   probes and results). The status-quo entry stays independently
   seeded; the pointwise `_objective_prunable` covers the uncovered
   samples and every Stage B probe. Neither certificate ever touches
   the committed-hours path. The cheap prefilter variant (a
   `q`-only sanity check in front of the full envelope) was evaluated
   and skipped: the envelope call is already the cheaper half of the
   decision and a second sound guard would only add branches.
4. **Task-owned search storage.** `TransferSearchScratch` in
   `src/systems/household_bargaining.jl` replaces the per-call
   `Dict{Float64,TransferObjectiveValue}` churn of `ADR-0016`: the
   evaluation cache plus reusable sorted-theta, weak-maximum-index, and
   certified-slab vectors. One scratch is constructed per
   `Threads.@threads :greedy` chunk body of `set_theta!` (the
   `spouse_seen` precedent of `ADR-0015`; never `threadid()`-indexed,
   dynamic scheduling preserved), reset per household by
   `_reset_scratch!` (`empty!` plus `sizehint!` without shrinking),
   and never retains a household's parameters or evaluation closure;
   the interval certifier is passed per call, not stored. Stage B sorts
   the reused sampled vector once (`append` of distinct samples in
   enumeration order; never `collect(keys(...))` or a fresh `Int[]`).
   The storage is a capacity-hinted reusable `Dict` (hint 2400, the
   measured fill-cost optimum) with `Dict`'s own `isequal` key
   semantics (`-0.0` distinct from `+0.0`); a task-owned open-addressed
   table was not needed: measured, lookup and clearing are no longer
   material after the hint and the reuse, and the `Dict` keeps the
   semantics exact for free. The public `bargain_transfer` entry point
   stays standalone (one scratch per call), the cache-probing tests
   keep their caller-owned `Dict` method of `ADR-0016`, and closure
   captures stay single-assignment (`MDR-0002`).

## Consequences

- The `MDR-0012` search contract is unchanged and bitwise-verified
  against the frozen pre-`ADR-0017` oracle
  `test/reference_transfer_search.jl` (verbatim copy of the per-call
  `Dict` driver and `bargain_transfer`): on the regression fixture
  households, boundary and fail-open constructed cases, and sampled
  households of the `ws_500`, `heterogeneous`, and `low_conformism`
  workloads at ticks 0 and 2, run repeatedly at 1 and 8 threads, the
  full evaluation sequence (ordered keys, cached payoffs including
  every `-Inf` sentinel, the gains and hours of every entry, Stage B
  weak maxima, plateaus, brackets, and probes) and the
  commit-or-fallback decision are `isequal`, and the committed
  `(theta, hw, hm)` matches bitwise
  (`test/test_transfer_search_identity.jl`). The search solve count is
  identical between the pre- and post-change runs by construction
  (pointwise parity) and is asserted per case. An instrumented census
  over the same case families (throwaway counters, the
  `benchmark/bargaining_kernel_report.md` methodology) confirms the
  assertions at scale: 279 case comparisons at each of 1 and 8 threads
  (114 constructed boundary/fail-open cases, 3 fixture households, 162
  sampled workload cases), 639512 cached entries compared fieldwise
  including 343627 certified `-Inf` sentinels and 230257 solved `-Inf`
  payoffs, 3365 Stage B probes, and 649 plateau representatives and
  refinement brackets, plus a 10000 household-tick `ws_500` census (20
  ticks, 500 households, the exact `set_theta!` states; 23797450 cached
  entries compared): 0 sequence or entry mismatches, committed
  `(theta, hw, hm)` identical in 10000/10000 household-ticks, solve
  counts identical in every case (5832084 vs 5832084).
- Interval soundness fuzz (`test/test_interval_certificate.jl`, fixed
  seed): 16520 interval decisions (the test asserts `>= 10000`) over
  randomized slabs across all four utility specs (CES `beta` from `1e-12`
  through just below, at, and above `CES_CERT_MIN_BETA` to `1.5`, alpha
  0/0.1/0.5/0.9/1, zero, tiny, and 40:1 wages, conformism 0/10/50/1e4,
  `N_theta` on either side of and inside the slab, zero weights, signed
  zeros, non-finite guard paths); 1079 certified intervals (the test
  asserts `>= 1000`), every one confirmed to compute exactly `-Inf` at
  the endpoints, boundary-adjacent representable floats, and sampled
  interior points, with the pointwise certificate agreeing at every
  covered sample: 0 unsound, 0 pointwise-parity failures. The
  zero-wage, unknown-spec, and mixed-range paths are covered
  explicitly: 9 intervals certified under the unenveloped spec, all
  through the exact zero-consumption rule of Decision item 2; 2337
  decisions present a mixed zero/nonzero consumption range and none
  certifies through the affected role (9 of them certify through the
  other partner's intact normal bound and are sound); the constructed
  zero-wage cases of the "fail-open guards" testset pin the same split
  (a pure-zero slab certifies and computes `-Inf` at every transfer, a
  mixed slab declines and computes finite payoffs).
- The search semantics of `MDR-0012`, the objective chain of
  `MDR-0002`, and the committed-hours path are untouched, so no MDR is
  needed; `MDR-0012`'s recorded per-call cache wording predates the
  storage change of this record, which is a code-level strategy
  decision.
- Measured effect (ws_500, 20 ticks, 5 repetitions,
  `benchmark/bargaining_kernel.jl`, AMD Ryzen 7 5825U, Julia 1.12.7):
  kernel median from 16.50 s to 12.52 s at 1 thread and from 3.58 s to
  2.53 s at 8 threads (pre-change numbers re-measured on this change;
  the previously recorded values were 16.99 s / 3.74 s); allocations
  per household-tick from 40.9 / 331487 B to 20.8 / 100229 B. Evaluation
  accounting per household-tick (ws_500, instrumented injected
  evaluators over the workload households, 10000 household-ticks over 20
  ticks): 2378.7 objective evaluations before (1795.5 pointwise
  certificate rejections plus 583.2 full solves) become 1752.7 interval
  exclusions plus 42.8 pointwise rejections plus the identical 583.2
  solves after - the prefilter replaces exactly the pointwise
  certificate calls (17955366 = 17527267 + 428099 over the census) at
  58.1 interval decisions and 8.1 certified slabs per household-tick.
  The solve count is unchanged (5832084 frozen vs 5832084 live over the
  census, 583.2 per household-tick, identical in every case and
  asserted per case in `test/test_transfer_search_identity.jl`; the
  earlier ~693 estimate is an early-tick sample basis: the same census
  at tick 0 measures 672.5, inside the recorded 604-758 sample range of
  `benchmark/transfer_search_validation.md`, and the 20-tick mean is
  lower because later ticks certify more samples).
- Fail-open cost of the parity discipline is confined to slabs the
  model never produces (see Decision item 2); the certificate is not
  soundness-limited there, it simply declines to certify where the
  pointwise certificate would decline too.
- `test/reference_transfer_search.jl` is frozen; retiring the oracle
  requires a record that retires it together with this one.

## References

- `MDR-0002`, `MDR-0012`, `ADR-0008`, `ADR-0014`, `ADR-0015`,
  `ADR-0016`
- `TASK-0017`, `TASK-0018`
- `src/systems/household_bargaining.jl`
- `src/resources/utility_functions.jl`
- `test/reference_transfer_search.jl`, `test/test_interval_certificate.jl`,
  `test/test_transfer_search_identity.jl`
- `benchmark/bargaining_kernel.jl`
