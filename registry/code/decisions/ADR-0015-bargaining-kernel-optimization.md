---
id: ADR-0015
title: Behavior-preserving bargaining kernel optimization
status: accepted
date: 2026-09-28
supersedes: ""
superseded_by: ""
---

# ADR-0015: Behavior-preserving bargaining kernel optimization

## Context

Profiling of the household bargaining kernel (`set_theta!` and
`bargain_transfer` in `src/systems/household_bargaining.jl`, ports of
NetLogo `set-theta` and `calculate-payoff`, ODD section Transfer
bargaining) shows that `bargain_transfer` dominates the kernel (~98% of
kernel time): every household-tick runs 19 `mutual_best_response`
solves, 17 of them for the transfer search, one for the outside options,
and one for the status quo. The solver semantics are bound by `MDR-0002`
and `MDR-0005`: objectives, feasible domains, tolerances, warm starts,
stopping rules, fallback behavior, and tie-breaking must be preserved
exactly, so this record governs a pure optimization with bit-identical
outputs as the acceptance criterion.

Two sources of avoidable work were identified. (a) The outside-option
solve (phase a) and the status-quo solve (phase b) have identical
arguments exactly when the clamped status-quo transfer `theta0` is
bitwise `+0.0`, so one of the two solves is redundant. (b) `set_theta!`
allocated its `spouse_seen` scratch vector once per household iteration,
although `norm_means` empties the buffer at the entry of its neighbour
branch and only the owning task needs it. The chunked
`Threads.@threads :greedy` scheduling of `ADR-0014` is retained
unchanged.

The zero-transfer regime finding (all transfer-search objective
evaluations return `-Inf` in the measured model workloads, recorded in
`registry/model/discrepancies.md` under `TASK-0014`) is not an
assumption of this design: every optimization decided here is exact for
all inputs, not only for that regime.

This record governs the whole bargaining-kernel optimization: B1, C1,
and the certified `-Inf` transfer-objective certificate (item 3 below)
are implemented together in this change; item 4 stays deferred.

## Decision

1. **B1 - identical duplicate solve reuse.** `bargain_transfer` computes
   the outside-option solve once and keeps `(hw_out, hm_out)`, computes
   `uw_out` and `um_out` with exactly the expressions `outside_options`
   uses, and reuses the solve as the status-quo labour equilibrium
   exactly when `theta0 === 0.0`, the strict bitwise guard (never
   `iszero`, so a signed zero `-0.0` keeps its own status-quo solve).
   Otherwise the status-quo solve runs as before. `mutual_best_response`
   is deterministic and pure, so identical arguments give bit-identical
   results and the reuse is exact. The public helper `outside_options`
   stays defined and behaviorally unchanged.
2. **C1 - chunk-task-owned scratch.** `set_theta!` allocates one
   `spouse_seen` buffer per `Threads.@threads :greedy` chunk body (one
   greedy task) and reuses it across the households of that chunk. The
   buffer is never indexed by `Threads.threadid()` and never shared
   across tasks; `norm_means` keeps its signature and semantics. The
   buffer is sizehinted once per chunk to the maximum vertex degree of
   the two graphs, the exact bound on its contents (one distinct spouse
   per same-sex neighbour), so no `norm_means` call grows it.
3. **Certified two-stage transfer objective (`TASK-0015`).** The
   transfer objective inside `bargain_transfer` gains a payoff-only
   `-Inf` certificate evaluated before `equilibrium_payoff`: a sampled
   transfer is pruned only when the sound upper bound
   `_payoff_upper_bound` puts one partner's computed utility strictly
   below that partner's outside option (strict comparison, the bound
   inflated by `OBJECTIVE_CERT_MARGIN`), the check fails open
   otherwise, and it is never applied on the committed-hours path. The
   bound is the per-spec material envelope `_material_envelope` over
   `x <= q*v`, `Q <= 2-v`, evaluated at the analytic maximizer and
   both interval endpoints `v == 0` and `v == d` (the endpoint maximum
   removes any dependence on maximizer mislocation, e.g. the CES `R`
   formula's `1/(1-beta)` conditioning as `beta -> 1`) times the norm
   lower bound `exp(-z)`. CES certifies only inside the safe band
   `beta >= CES_CERT_MIN_BETA`, where the outer power `S^(1/beta)`
   keeps its rounding amplification of the inner sum below the margin,
   and fails open below the band and on any non-finite or subnormal
   intermediate (in the root case `beta >= 1`, the inner sum `S`); the
   other specs have exponents `<= 1` and only contract rounding. Pruning is strictly
   sound (the pruned evaluations would return `-Inf` anyway), so the
   maximizer, tie-breaking, and committed outputs stay bit-identical.
4. **Deferred.** The objective-result memo and cached entity-to-vertex
   maps are deferred pending measured need.
5. **Rejected: CES `beta == 0.5` `sqrt`/square specialization.**
   `x^0.5` and `sqrt(x)` are not bit-identical in Julia (measured ~1%
   of values differ), so the specialization is an FP-affecting change
   and is rejected while exact output is required; it needs explicit
   user approval before it can be reconsidered as a recorded change.

## Consequences

- Bit-identical behavior was the acceptance criterion of the stages
  recorded here (B1, C1, certificate) and is a historical measurement
  valid for the pre-`MDR-0012` transfer search: at that time
  `test/test_bargaining_equivalence.jl` replayed
  `test/fixtures/bargaining_baseline.toml` (200 solver cases and 4
  trajectory runs) against the live solver chain and the frozen copy
  `test/reference_bargaining.jl`, comparing every `Float64` with
  `isequal`. Since `MDR-0012` the transfer search of `bargain_transfer`
  is the staged feasibility-discovery search and its outcomes changed
  deliberately: the current bitwise guarantees cover the unchanged
  objective chain (`mutual_best_response`, `outside_options`,
  `nash_product`, `equilibrium_payoff`, `individual_utility`) and the
  certificate of this record, while `bargain_transfer` results are no
  longer compared bit-identically to the frozen reference (a comparison
  baseline since `MDR-0012`, not a correctness oracle).
- B1 removes one `mutual_best_response` solve per household-tick
  whenever `theta0 === 0.0` (19 solves become 18); C1 removes the
  per-household scratch allocation (one buffer per chunk of
  `HOUSEHOLD_BARGAIN_CHUNK` households instead of one per household).
- The certified `-Inf` transfer-objective certificate (item 3) is
  implemented: `_objective_prunable`, `_payoff_upper_bound`, and
  `OBJECTIVE_CERT_MARGIN` in `src/systems/household_bargaining.jl` and
  the per-spec `_material_envelope` envelope with its `_envelope_peak`
  evaluation helper in `src/resources/utility_functions.jl`
  (fail-open fallback for unenveloped `UtilitySpec` subtypes). It is
  used only inside the payoff-only objective of `bargain_transfer`,
  never on the committed-hours path and never inside
  `outside_options`, `nash_product`, `equilibrium_payoff`, or
  `mutual_best_response`. `bargain_transfer` additionally skips the
  transfer search when either outside option is non-finite (every
  `nash_product` value is then `-Inf` and the search would fall back to
  the status quo anyway) and returns the status fallback directly.
  `TASK-0015` is closed.
- Floating-point justification of the certificate (summary; the full
  argument is in `benchmark/bargaining_kernel_report.md`): the bound
  upper-bounds the computed Float64 `individual_utility`, not the real
  formula. IEEE monotone rounding gives `x <= q*v` and `Q <= 2-v` for
  the computed values and `norm <= -z` exactly (the computed norm sum
  dominates the retained term `conformism * w_transfer * (theta -
  N_theta)^2`), and the material envelope maximizes the monotone
  material function at the analytic per-spec maximizer and both
  endpoints `v == 0` and `v == d`, so no bound depends on maximizer
  mislocation. The final bound is inflated by the total relative
  margin `OBJECTIVE_CERT_MARGIN = 1.0e-9`: a few ulps of `x`/`Q`/`z`
  rounding, `<= 1` ulp each documented for `^`, `sqrt`, and `exp`, and
  their combination. Per spec, only the CES outer power `S^(1/beta)`
  amplifies rounding: its condition number in the rounded inner sum
  `S` is `1/beta`, so the gap between the computed utility and the
  computed envelope is bounded by `(1/beta) * n_ops * eps` (`eps =
  2^-53`, `n_ops = 10` the combined inner-sum error budget of both
  evaluations, about 1.0e-12 at `beta = 1.0e-3` and about 1.0e-4 at
  `beta = 1.0e-12`); the other specs have exponents `<= 1` and only
  contract rounding. The safe band `beta >= CES_CERT_MIN_BETA =
  1.0e-3` keeps the amplification and the whole in-band budget more
  than three orders of magnitude below the margin, and CES fails open
  below it instead of certifying. Any non-finite or out-of-range
  input, `beta` outside the band, non-finite or subnormal envelope
  intermediate, or non-finite bound fails open to the full solve; the
  exact-zero `q == 0` cases are exact `-Inf` by IEEE monotonicity. In
  the CES root case `beta >= 1` the envelope additionally guards its
  inner sum `S` and fails open on a subnormal `S` (the root maps its
  unbounded subnormal quantization error up into the normal material
  range); for `beta < 1` a subnormal `S` maps below the `floatmin`
  floor of every certified bound and needs no guard. The comparison is
  strict, so the finite zero gain at the status-quo transfer is never
  pruned.
- Measured certificate evidence (instrumented throwaway solver copies,
  500 households per tick, 20 ticks, seed 1, all six workloads of
  `benchmark/bargaining_kernel.jl`): 96.6% of the 17 objective samples
  per household-tick certify on `ws_500` (100% on `heterogeneous`,
  where 0.27 household-ticks also take the non-finite-outside fast
  path), `mutual_best_response` solves per household-tick fall from
  19.0 to 1.57, and `individual_utility` evaluations from 656.1 to
  43.2 (706.6 to 37.6 on `heterogeneous`); the 17 requested objective
  samples per household-tick are unchanged, only their solves are
  pruned.
- Measured benchmark evidence (15 repetitions, 20 ticks, baseline
  commit `5c58565` vs final tree, AMD Ryzen 7 5825U, Julia 1.12.7):
  `set_theta!` kernel median on `ws_500` 0.3683 s to 0.0632 s at 1
  thread (82.8% faster) and 0.0702 s to 0.0136 s at 8 threads (80.6%
  faster); 68.7-85.8% faster on every workload at both thread counts,
  no regression; end-to-end `GenderNorms.run` 1.81-6.62x faster;
  kernel allocations per tick 1661 to 424 on `ws_500` at 1 thread (the
  post-stage-1 level; `_objective_prunable` allocates 0 bytes per
  decision). Full tables, evaluation counts, equivalence results, and
  the exactness argument are in `benchmark/bargaining_kernel_report.md`.
- Equivalence evidence (historical measurements of the stages recorded
  here, valid for the pre-`MDR-0012` transfer search; the current
  bitwise scope is the unchanged objective chain and the certificate,
  see above): `test/test_bargain_certificate.jl` (fixed-seed
  soundness fuzz: 1400 draws, 14000 certificate decisions, 2609
  certified prunes each confirmed against the frozen reference to
  compute exactly `-Inf`, `theta == 0.0` never certified against true
  outside options, live `bargain_transfer` bitwise equal to the frozen
  reference on every draw at measurement time; 1680 boundary and
  fallback parameter sets;
  margin-load-bearing boundary transfers found by bisection between
  two consecutive grid points with opposite decisions, asserted to
  flip across the bisected interval and checked at the flip and its
  neighbouring representable transfers; 1500 envelope draws checked
  against a 4001-point brute-force grid; 600 guarded bound-soundness
  draws (all four specs, both partner roles, CES `beta` from `1e-12`
  to `3.0`, `alpha` 0-1, wage pairs including `0`, `1e-8`, and 40:1,
  conformism up to `1e4`, transfers `-1` to `1`) checked against a
  101x101 hour grid with the below-band draws asserted to fail open,
  plus the CES `beta = 1e-12` counterexample regression;
  probe-counted fast-path skip) passes at 1 and 8 threads together with
  the unchanged equivalence oracle and `test/test_threading.jl`.
- The `ADR-0014` consequence "One scratch-vector allocation per agent
  and household iteration" is amended: `set_theta!` no longer allocates
  per household iteration (chunk-task-owned scratch, this record), while
  `calculate_norm_perception!` still allocates one scratch vector per
  agent iteration.
- The interval-exclusion certificate and the search storage of
  `ADR-0017` build on this record without changing it:
  `_objective_prunable`, `_payoff_upper_bound`, `_material_envelope`,
  and their guards and margins are unchanged, the pointwise certificate
  remains the decision of record for every evaluated sample, and the
  interval certificate certifies only where the pointwise one would
  (pointwise parity), so the measured evidence of this record stays
  valid for the objective chain.
- No model-behavior change and no ODD change, so no MDR is needed.
- `test/reference_bargaining.jl` and `test/fixtures/bargaining_baseline.toml`
  are frozen; retiring the oracle requires a record that retires them
  together with this one.

## References

- `MDR-0002` (labour solver semantics)
- `MDR-0005` (transfer search semantics of the measured stages)
- `MDR-0012` (supersedes `MDR-0005`; staged transfer search, deliberate
  `bargain_transfer` outcome change)
- `ADR-0007` (`set_theta!` query extraction)
- `ADR-0014` (chunked greedy tick loops)
- `TASK-0014` (zero-transfer regime finding)
- `TASK-0015` (certified `-Inf` objective certificate)
