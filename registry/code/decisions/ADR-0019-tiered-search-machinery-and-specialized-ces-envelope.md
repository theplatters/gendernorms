---
id: ADR-0019
title: Tiered search machinery and specialized CES envelope
status: accepted
date: 2026-09-30
supersedes: ""
superseded_by: ""
---

## Context

`MDR-0014` replaces the Stage A sample set of the staged transfer
search with a tiered set (fine 1e-4 window `+/- 0.002` around the
anchors `0.0` and `theta0`, coarse 1e-3 grid elsewhere). The code
structure behind it needs its own record: the sample enumeration of
`_transfer_search!`, the evaluation-cache insert discipline of
`TransferSearchScratch` (recorded per-call-then-task-owned by
`ADR-0016`/`ADR-0017`), and the envelope evaluation of
`_material_envelope(::CES, ...)`, which is the second-largest cost
share of the kernel (about 30%: 1426 `_payoff_upper_bound` calls per
household-tick at 149 ns each, 9 runtime `pow` calls per bound: three
in each of the three `_envelope_peak` candidates plus two in the
analytic maximizer).

Measured cost anatomy of the `ws_500` kernel before this record
(per household-tick, `/tmp/opencode/stage3_anatomy.jl` and
`stage3_scratch_probe.jl`, `benchmark/bargaining_kernel.jl`
medians): about 686 labour solves at 426 ns (41%), 1426
`_material_envelope` calls at 149 ns (30%, the pow-based general
`CES` path at `beta == 0.5`), and 29% search machinery (the Stage A
enumeration with one cache insert and one slab-membership scan per
sampled transfer, the `sort!` of the sampled sequence, the Stage B
scan, the interval-slab bisection of `ADR-0017`, and the per-chunk
`TransferSearchScratch` construction, measured at 4.7 us and 215 KB
each but only about 1% of kernel time after warmup). A micro
benchmark of the envelope at `beta == 0.5` measures 149 ns through
the live general path, 72 ns for the general peak form alone, and
9.2 ns for a sqrt/square prototype, so the pow-based envelope and
its pow-based maximizer are the whole overhead.

## Decision

1. **Tiered sample enumeration.** `_transfer_search!` enumerates the
   `MDR-0014` sample set in the recorded order: anchors `-1.0`,
   `0.0`, `theta0`, `+1.0`; the fine tier `anchor +/- k *
   TRANSFER_FINE_STEP`, `k = 1..TRANSFER_FINE_STEPS`, around `0.0`
   and `theta0`, clipped to `[-1, 1]`; the coarse grid
   `-1.0:TRANSFER_COARSE_STEP:1.0` ascending. The `TRANSFER_LOCAL_*`
   constants are removed (the fine window replaces the local grids;
   `test/reference_transfer_search.jl` keeps its frozen value
   copies). `_transfer_prepare_slabs!` partitions the two fine runs
   at `TRANSFER_FINE_STEP` spacing and the domain run at
   `TRANSFER_COARSE_STEP` spacing as before (the bisection floor
   `TRANSFER_SLAB_MIN_SAMPLES` is per-run in samples); the
   enumeration loops, `_transfer_sample!`, and `_transfer_covered`
   are structurally unchanged.
2. **Evaluation-cache insert discipline.** `TransferSearchScratch`
   gains a parallel `samples::Vector{Tuple{Float64,Float64}}` (the
   sampled transfer and its cached payoff) replacing the
   `thetas::Vector{Float64}`; `_transfer_sample!` appends every
   Stage A transfer to `samples` but inserts only EVALUATED entries
   (pointwise-certified or solved) into the cache. Slab-covered
   samples keep their exact cached `-Inf` payoff in `samples` only:
   they are uniform `-Inf` sentinels by the interval certificate and
   no later stage reads them from the cache. Stage B sorts `samples`
   once (`sort!` on the reused buffer, `isless` order, `-0.0` before
   `+0.0`) and collapses adjacent `isequal` transfers (exact key
   semantics, signed zeros stay distinct), then runs the unchanged
   weak-local-maximum, plateau, bracket, and refinement logic over
   the sorted distinct pairs; a refinement probe
   (`_transfer_eval!`) still inserts its evaluation, and a probe at
   a slab-covered transfer re-certifies through the pointwise
   `_objective_prunable` inside `evaluate!` to the identical `-Inf`
   sentinel (pointwise parity, `ADR-0017`) at the cost of one
   certificate decision instead of one cache hit. Candidate
   selection still iterates the cache (every finite payoff), and the
   seeded `theta0` entry is still recorded before the search and
   appended to `samples` from the cache keys (the caller-owned-cache
   entry point may seed more than one key). Consequences recorded
   honestly: the cache key set no longer equals the sampled sequence
   (slab-covered samples are absent), so the cache contents are not
   a search-contract observable any more; the sampled sequence,
   every cached VALUE, every refinement bracket, and the commit are
   unchanged.
3. **Specialized `CES` envelope for `beta == 0.5`.**
   `_material_envelope(::CES, ...)` evaluates the exact `beta == 0.5`
   case (the `material(::CES, ...)` dispatch condition `u.beta == 0.5`)
   with the sqrt/square form `t = alpha * sqrt(q * v) + (1 - alpha) *
   sqrt(2 - v); t * t` per `_envelope_peak` candidate and the closed
   form `v* = clamp(2 * alpha^2 * q / (alpha^2 * q + (1 - alpha)^2),
   0, d)` of the analytic maximizer (the same real function as the
   general `R = (alpha * q^beta / (1 - alpha))^(1 / (1 - beta))`,
   `v* = 2R / (1 + R)` form at `beta == 0.5`, and identical to the
   `Additive` maximizer because `material_CES(beta=0.5) =
   material_Additive^2`); every other `beta` keeps the general
   pow-based form and the general maximizer unchanged. Guards and
   fail-open discipline are unchanged (`_envelope_peak`'s input and
   normal-floor guards, the `CES_CERT_MIN_BETA` band, the
   `beta >= 1` inner-sum guard, the alpha endpoint rules).
   Margin arithmetic re-derived (the `CES_CERT_MIN_BETA` comment is
   updated accordingly):
   - Domination of the computed utility: the envelope candidate at
     `v` evaluates EXACTLY the expression `material(::CES, beta=0.5,
     ...)` evaluates at `(q * v, 2 - v)` (same sqrt/square grouping),
     so the candidate and the computed material round identically at
     identical inputs; the gap to the computed material at `(x <= q
     * v, Q <= 2 - v)` is then only the rounding of the computed
     consumption and leisure against their analytic bounds, the
     monotonicity of correctly rounded `sqrt` and `*`, and the norm
     factor - the same few-ulp budget `OBJECTIVE_CERT_MARGIN` covers
     for the pow path, with strictly fewer rounding stages than
     before (two `sqrt` and one multiply against three `pow`; the
     old path additionally differed from `material`'s `s * s` by up
     to one ulp of `pow(x, 2)`).
   - Amplification: `material` at `beta == 0.5` is the square of its
     inner sum, so the inner-sum rounding is amplified by the factor
     `1 / beta = 2`, unchanged by this specialization; the certified
     band `beta >= CES_CERT_MIN_BETA` and the whole in-band rounding
     budget below `OBJECTIVE_CERT_MARGIN` (about 4500 ulps of
     headroom at the floor) are unchanged.
   - Subnormal intermediates: `_envelope_peak` rejects non-finite
     candidates and requires the largest candidate to be at least
     `floatmin`; at interior `v` both `sqrt` inputs are at least
     `floatmin` (guarded) so the inner sum is normal (its two
     weighted summands cannot both be subnormal), and at `v == 0` or
     `v == 2` the zero side term is exact; a subnormal candidate
     squares below the floor and can never dominate a certified
     bound (the `0 < beta < 1` discipline of `ADR-0015`). Overflow
     of `t * t` fails open via `_envelope_peak`.
   The bound still dominates the computed utility for every
   `UtilitySpec` and both partner roles; the brute-force-grid,
   bound-versus-computed-utility, small-beta fail-open, and soundness
   fuzz tests stay green and are extended with an explicit
   specialized-path case set (a bound that does not dominate the
   computed utility is a stop).
4. **Measured-and-dropped alternatives** (each measured before
   rejection):
   - Adaptive densification around finite samples: rejected; on the
     measured states it adds solves without new discovery (the
     narrow bands are already covered by the guaranteed fine window,
     the wide bands by the coarse grid).
   - Cross-household slab-decision caching: rejected; household
     parameters (wages, norms) do not repeat exactly across
     households, and a cache keyed by them would retain household
     state in the task-owned scratch (forbidden by `ADR-0017`).
   - Status-quo-relative payoff pruning (prune samples whose sound
     payoff upper bound cannot beat the status-quo payoff): not
     implemented; it would change the cached-value semantics beyond
     the sanctioned discovery change (the recorded values are part of
     the search contract) and can change results through skipped
     Stage B refinements on jagged objectives. Its measured potential
     (it would remove most of the remaining uncertified-span solves)
     is recorded in `TASK-0020`.
   - Thinning the coarse grid beyond 1e-3: rejected; outside the
     sanction of `MDR-0014` and it widens the missed-band class for
     little gain (the certified far field is already free of solves).
   - Scratch pooling across chunks: rejected for now; the per-chunk
     `TransferSearchScratch` construction is only about 1% of kernel
     time after warmup (an earlier profile spike was a first-call
     artifact), and a channel pool would add scheduling machinery for
     that share. The capacity hint is retuned to the new sample count.

## Consequences

- The `MDR-0014` search semantics hold by construction: the sampled
  sequence and its payoffs are unchanged (slab-covered samples keep
  their exact `-Inf` sentinel in the sequence), so Stage B brackets,
  weak maxima, plateaus, refinement probes, the tie rule, and the
  commit are identical to the pre-change tiered search on every
  input; only the cache key set shrinks. The search contract tests
  (`test/test_transfer_search.jl`,
  `test/test_transfer_search_reduction.jl`) assert this directly.
- The bitwise search-identity tests of `ADR-0017`
  (`test/test_transfer_search_identity.jl`) are retired with that
  record's oracle role: `test/reference_transfer_search.jl` stays
  frozen but becomes the reference-comparison baseline of
  `MDR-0014` (the `MDR-0013` staged search), like
  `test/reference_bargaining.jl` since `ADR-0015`; retiring the
  frozen file itself stays a separate recorded decision.
- Certificate values move by ulps where the `CES` `beta == 0.5`
  envelope applies (prune decisions flip only between the exact
  `-Inf` sentinel and a solve returning exactly `-Inf`, by the
  pointwise parity of `ADR-0017`); every other spec is bitwise
  unchanged. Measured effect (`benchmark/search_reduction_validation.md`,
  `benchmark/bargaining_kernel.jl ws_500 20 5`, 5 repetitions): the
  envelope call drops from 149 ns to 9.2 ns (the pow-based general
  path evaluated 9 runtime `pow` per bound against 6 `sqrt` and 3
  multiplies in the specialized one) and 1426 bounds per
  household-tick drop to 747.7; with the tiered sample set of
  `MDR-0014` the kernel median falls from 6.869 s to 2.510 s at 1
  thread (2.74x) and from 1.599 s to 0.608 s at 8 threads (2.63x),
  allocations from 100.2 KB to 55.0 KB per household-tick. The
  brute-force-grid, bound-versus-computed-utility, small-beta
  fail-open, and soundness fuzz tests stay green and are extended
  with the specialized-path case set
  (`test/test_bargain_certificate.jl`, 537 new assertions including
  bitwise candidate-identity with `material` and the closed-form
  maximizer). The remaining cost anatomy (59% labour solves in the
  uncertified span of the certificate) is recorded in
  `benchmark/search_reduction_validation.md` and `TASK-0020`.

## References

- `MDR-0012`, `MDR-0013`, `MDR-0014`
- `ADR-0015`, `ADR-0016`, `ADR-0017`, `ADR-0018`
- `TASK-0018`, `TASK-0020`
- `src/systems/household_bargaining.jl`
- `src/resources/utility_functions.jl`
- `test/reference_transfer_search.jl`, `test/test_transfer_search.jl`,
  `test/test_transfer_search_reduction.jl`,
  `test/test_bargain_certificate.jl`, `test/test_interval_certificate.jl`
- `benchmark/search_reduction_validation.md`
