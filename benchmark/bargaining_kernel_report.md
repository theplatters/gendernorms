# Bargaining kernel optimization report (ADR-0015)

Measured evidence for `registry/code/decisions/ADR-0015-bargaining-kernel-optimization.md`
items B1 (identical duplicate solve reuse), C1 (chunk-task-owned
scratch), and the certified `-Inf` transfer-objective certificate
(`TASK-0015`). Scope: the historical measurements of the `ADR-0015`
optimization stages (B1, C1, certificate), taken against the
pre-`MDR-0012` transfer search and valid for it. In that scope every
optimization is exact: outputs are bit-identical to the
pre-optimization reference (`test/reference_bargaining.jl`,
frozen at commit `5c58565`) and to the recorded fixtures, verified by
`test/test_bargaining_equivalence.jl` and `test/test_bargain_certificate.jl`.
Since `MDR-0012`, the transfer search of `bargain_transfer` is the
staged feasibility-discovery search and its outcomes changed
deliberately, so `bargain_transfer` results are no longer bit-identical
to the frozen reference; the current bitwise guarantees cover the
unchanged objective chain (`mutual_best_response`, `outside_options`,
`nash_product`, `equilibrium_payoff`, `individual_utility`) and the
certificate of this record. The certificate is an optimization of
`ADR-0015`, not a ported NetLogo behavior, so this report carries no
NetLogo or ODD citation; the solver semantics it preserves are pinned
by `MDR-0002` and `MDR-0005` (the
transfer search semantics are pinned by `MDR-0012` since it superseded
`MDR-0005`).

## Environment

- CPU: AMD Ryzen 7 5825U with Radeon Graphics, 16 hardware threads.
- Julia 1.12.7, `JULIA_NUM_THREADS=1` and `JULIA_NUM_THREADS=8`.
- Timings from `benchmark/bargaining_kernel.jl` (methodology
  `MDR-0011`/`ADR-0013`): 20 ticks, 15 repetitions, one fresh
  `create_world` per repetition from identical seeded initial states,
  sequential runs on an idle machine, one thread count and one variant
  at a time. Reported per run: the sum of the `set_theta!` times over
  the 20 ticks (kernel) as median and IQR over the 15 repetitions, the
  median allocation count per tick of the timed kernel sections, and
  the median end-to-end `GenderNorms.run` time of the same
  specification.
- Baseline: git worktree at commit `5c58565` (pre-optimization) with
  the current `benchmark/bargaining_kernel.jl` copied in. Candidate:
  this working tree (B1 + C1 + certificate).

## Workload configurations

All workloads: seed 1, CES utility with `beta` 0.5, package-default
utility weights, 500 agents per gender (500 households) unless noted,
20 ticks, no shocks scheduled.

| Workload | Network | Population | Extra |
| --- | --- | --- | --- |
| ws_500 | watts_strogatz, neighbors_per_side 2, rewiring 0.1 | 500/gender | representative workload |
| ws_100 | watts_strogatz, neighbors_per_side 2, rewiring 0.1 | 100/gender | - |
| homogeneous_mixing | homogeneous_mixing | 500/gender | - |
| no_network | none | 500/gender | - |
| homophily | homophily, m 2 | 500/gender | - |
| heterogeneous | watts_strogatz, neighbors_per_side 2, rewiring 0.1 | 500/gender | mean_wage men 2.0 / women 0.5, initial_conformism 50.0/50.0 |

## Runtime and allocations (baseline 5c58565 vs final)

Kernel and end-to-end medians in seconds over 15 repetitions; IQR is
the kernel interquartile range; allocs/tick is the median allocation
count of the timed `set_theta!` sections per tick.

| Workload | Threads | Kernel med before | Kernel med after | Faster | IQR before | IQR after | Allocs/tick before | Allocs/tick after | e2e med before | e2e med after | e2e faster |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ws_500 | 1 | 0.3683 | 0.0632 | 5.83x (82.8%) | 0.0009 | 0.0002 | 1661 | 424 | 0.3727 | 0.0675 | 5.52x |
| ws_500 | 8 | 0.0702 | 0.0136 | 5.17x (80.6%) | 0.0020 | 0.0004 | 1696 | 459 | 0.0759 | 0.0188 | 4.04x |
| ws_100 | 1 | 0.0738 | 0.0126 | 5.84x (82.9%) | 0.0010 | 0.0000 | 372 | 124 | 0.0749 | 0.0138 | 5.44x |
| ws_100 | 8 | 0.0174 | 0.0035 | 4.99x (80.0%) | 0.0002 | 0.0002 | 407 | 160 | 0.0195 | 0.0054 | 3.64x |
| homogeneous_mixing | 1 | 0.3658 | 0.0619 | 5.91x (83.1%) | 0.0015 | 0.0001 | 675 | 300 | 0.3687 | 0.0646 | 5.71x |
| homogeneous_mixing | 8 | 0.0749 | 0.0132 | 5.66x (82.3%) | 0.0047 | 0.0005 | 710 | 335 | 0.0810 | 0.0182 | 4.44x |
| no_network | 1 | 0.3704 | 0.0616 | 6.01x (83.4%) | 0.0043 | 0.0001 | 674 | 299 | 0.3735 | 0.0644 | 5.80x |
| no_network | 8 | 0.0757 | 0.0131 | 5.77x (82.7%) | 0.0010 | 0.0004 | 709 | 334 | 0.0821 | 0.0185 | 4.44x |
| homophily | 1 | 0.3718 | 0.0637 | 5.84x (82.9%) | 0.0019 | 0.0002 | 1589 | 424 | 0.3767 | 0.0686 | 5.49x |
| homophily | 8 | 0.0856 | 0.0268 | 3.19x (68.7%) | 0.0164 | 0.0264 | 1624 | 459 | 0.0919 | 0.0507 | 1.81x |
| heterogeneous | 1 | 0.3943 | 0.0562 | 7.02x (85.8%) | 0.0054 | 0.0001 | 1661 | 424 | 0.3998 | 0.0604 | 6.62x |
| heterogeneous | 8 | 0.0805 | 0.0121 | 6.66x (85.0%) | 0.0017 | 0.0004 | 1696 | 459 | 0.0855 | 0.0167 | 5.12x |

Observations:

- `set_theta!` is 68.7-85.8% faster on every workload at both thread
  counts; the representative `ws_500` is 82.8% (1 thread) and 80.6%
  (8 threads) faster.
- End-to-end `GenderNorms.run` is 1.81-6.62x faster; the run is
  kernel-dominated, so the end-to-end speedup tracks the kernel
  speedup minus the fixed setup and statistics cost.
- The `homophily` workload at 8 threads is the noisiest measurement
  (kernel IQR 0.0264 s around a 0.0268 s median, before and after);
  the run-to-run spread comes from the chunk scheduling of `ADR-0014`
  on the uneven per-household Brent iterations, not from the
  optimization (its 1-thread spread is 0.0002 s).
- Allocations per tick drop to exactly the post-stage-1 level of 424
  allocs/tick at 1 thread on `ws_500` (the certificate adds no
  allocation: `_objective_prunable` allocates 0 bytes per decision,
  asserted in `test/test_bargain_certificate.jl`). At 8 threads the
  per-tick counts (459) reflect per-chunk greedy-task bookkeeping of
  `ADR-0014` and are unchanged by the certificate.

## Evaluation counts per household and tick

Measured with instrumented throwaway copies of the solver chain in
`/tmp/opencode/gendernorms-count-base` (commit `5c58565`) and
`/tmp/opencode/gendernorms-count-final` (this tree), counters added
only in those copies, single-threaded, 500 households (100 for
`ws_100`) over 20 ticks, seed 1. A household-tick is one
`bargain_transfer` call.

| Workload | `individual_utility` before | after | `mutual_best_response` before | after | Objective samples before | after | Pruned | Executed | Certificate hit rate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ws_500 | 656.12 | 43.17 | 19.0 | 1.57 | 17.0 | 17.0 | 16.43 | 0.57 | 96.6% |
| ws_100 | 656.97 | 42.94 | 19.0 | 1.55 | 17.0 | 17.0 | 16.45 | 0.55 | 96.8% |
| homogeneous_mixing | 655.20 | 43.33 | 19.0 | 1.57 | 17.0 | 17.0 | 16.43 | 0.57 | 96.6% |
| no_network | 656.26 | 42.34 | 19.0 | 1.54 | 17.0 | 17.0 | 16.46 | 0.54 | 96.8% |
| homophily | 655.59 | 43.23 | 19.0 | 1.57 | 17.0 | 17.0 | 16.43 | 0.57 | 96.6% |
| heterogeneous | 706.60 | 37.61 | 19.0 | 1.0 | 17.0 | 16.73 | 16.73 | 0.0 | 100% |

- Per tick at 500 households this is 327,796 `individual_utility`
  evaluations and 9,500 labour solves before, 21,586 and 785 after on
  `ws_500` (15.2x fewer utility evaluations, 12.1x fewer solves).
- The 17 requested objective samples per household-tick are unchanged
  (the Brent search of `MDR-0005` samples the same points);
  the certificate replaces 96.6% of their full labour solves with the
  certified `-Inf`. The remaining 0.57 executed samples per
  household-tick are fail-open or non-certifying samples; they also
  return `-Inf` (zero-transfer regime of `TASK-0014`), so the search
  still falls back to the status quo.
- `heterogeneous` reaches a 100% hit rate and drops below 17 samples
  per household-tick: 0.27 of its household-ticks have non-finite
  outside options (hours at the zero corner) and take the
  non-finite-outside fast path of `ADR-0015`, which skips the search
  entirely.
- Attribution: B1 alone removes 1 of the 19 solves per household-tick
  (the status-quo solve reused when the clamped transfer is bitwise
  `+0.0`); the certificate removes the remaining 16.43 of the 17
  search solves.

## Equivalence results

Historical measurements of the `ADR-0015` optimization stages (B1,
C1, certificate), valid for the pre-`MDR-0012` transfer search; all
bit-identical (`isequal` on every `Float64`, NaN matches NaN,
`-0.0` does not match `0.0`) at measurement time; full suite green at
`JULIA_NUM_THREADS=1` and `JULIA_NUM_THREADS=8`:

- Solver fixtures: 200 recorded cases of
  `test/fixtures/bargaining_baseline.toml` replayed against the live
  solver chain and the frozen reference, including the 118 improving
  optima, the fallback and infeasible-status branches, boundary hours
  and transfers, extreme wage ratios (40:1), all four utility specs,
  and the `MultiplicativeWeighted` payer branch. Historical: this
  replay was taken under the `MultiplicativeWeighted` payer quirk
  surface; `MDR-0019` removed the quirk and re-synced the frozen
  oracle `test/reference_bargaining.jl` and the 42
  `multiplicative_weighted` rows of
  `test/fixtures/bargaining_baseline.toml` to the fixed spec.
- Trajectories: 4 recorded `create_world` + `GN.run` trajectory runs
  (metric series and per-tick phase snapshots) replayed bit-identical
  (kept as baseline data since `MDR-0012`; trajectory deltas belong to
  the follow-up validation package).
- Stage-1 tests, `test/test_threading.jl` (as-is, cross-thread-count
  determinism), and the full test suite pass unchanged.
- Certificate soundness fuzz (`test/test_bargain_certificate.jl`,
  fixed seeds): 1400 randomized draws over the guarded domain
  (transfers in `[-1, 1]` including 0 and the endpoints, hours 0-1
  including the extremes, wage pairs including 0 and 40:1, conformism
  0/10/50/1e4, `alpha` 0/0.1/0.5/0.9/1, all four specs, CES `beta`
  0.2/0.5/1.5 plus the `-0.5`/`0.0` fail-open paths, varied
  `N_h`/`N_theta`/`N_h_spouse`, zero-weight and zero-wage configs),
  14,000 certificate decisions: every one of the 2,609 certified
  prunes was confirmed against the frozen reference chain to compute
  the payoff exactly `-Inf`, `theta == 0.0` was never certified
  against true outside options (zero gains are feasible), and the live
  `bargain_transfer` result matched the frozen reference bitwise on
  every draw (pre-`MDR-0012` measurement; the `bargain_transfer`
  result contract is checked by the `MDR-0012` search contract now).
- Boundary and fallback cases (1680 parameter sets: zero wages, zero
  conformism, zero weights, `alpha` at 0 and 1, transfers at the
  bracket endpoints and beyond, CES `beta <= 0`) matched the reference
  bitwise.
- Margin-load-bearing cases: bisection between two consecutive grid
  points with opposite decisions down to transfers where the
  certified bound equals the outside option to within a few ulps (the
  decision flip across the bisected interval is asserted, in either
  orientation); at those transfers and their neighbours the pruned
  objective value equals the reference payoff.
- Envelope sanity: 1500 randomized envelope draws each checked
  against a 4001-point brute-force maximum of the real material
  function over `v` (plus the fail-open cases); the envelope never
  fell below the grid maximum.
- Bound soundness: 600 randomized guarded draws (all four specs and
  both partner roles, CES `beta` 1e-12/1e-6/1e-4/1e-3/0.2/0.5/1.0/
  1.5/3.0, `alpha` 0/0.1/0.5/0.9/1, wage pairs including 0, tiny
  1e-8, and 40:1, conformism 0/50/1e4, transfers -1/-0.3/0/0.3/1)
  each checked over a dense 101x101 `(h_self, h_spouse)` grid in
  `[0, 1]^2` including the feasible corners: the computed
  `individual_utility` never exceeded `_payoff_upper_bound * (1 +
  OBJECTIVE_CERT_MARGIN)` wherever the guards passed, and every CES
  draw below `CES_CERT_MIN_BETA` failed open.
- Small-beta counterexample regression: the review's CES `beta =
  1e-12` payer configuration (pre-fix bound 0.5440988918819328 below
  the computed utility 0.5442197195194871 at (598/1001, 0)) now fails
  open (`_objective_prunable` returns `false`, the bound is `NaN`)
  while `nash_product` at the feasible pair stays finite; the same
  configuration at `beta = 1e-3` certifies soundly against the dense
  grid.
- Non-finite-outside fast path: probe-counted runs show the live chain
  evaluating exactly the pre-search utilities when an outside option is
  non-finite (the search is skipped) while the frozen reference runs
  the full search on the all-non-finite objective, with bit-identical
  results.

Current scope after `MDR-0012`: the bitwise guarantees cover the
unchanged objective chain (`mutual_best_response`, `outside_options`,
`nash_product`, `equilibrium_payoff`, `individual_utility`) and the
certificate; `bargain_transfer` outcomes changed deliberately under
`MDR-0012` (the staged transfer search of `MDR-0012` supersedes the
pre-`MDR-0012` unseeded Brent search), so their bit-identity with the
frozen reference in the results above is a historical measurement of
the `ADR-0015` stages, valid for the pre-`MDR-0012` search, not a
current guarantee. The frozen reference is a comparison baseline since
`MDR-0012`, not a correctness oracle; the commit counts of both
searches over the 200 fixture cases are reported in the test log of
`test/test_bargaining_equivalence.jl`.

## Exactness argument

Why a pruned objective sample returns the exact `-Inf` that
`nash_product` would have returned, and why no unpruned output changes:

1. `nash_product` returns exactly `-Inf` unless both utility gains over
   the outside options are finite and non-negative. Certifying that
   one partner's computed utility at the sampled transfer is strictly
   below that partner's outside option at every feasible working-time
   pair is therefore sufficient to prune; one partner suffices.
2. The certificate upper-bounds the computed Float64
   `individual_utility`, not the real formula. The consumption bound
   follows from IEEE monotone rounding: the payer has `x` computed at
   most `wage_self * (1 - abs(theta)) * h_self` and the recipient at
   most `max(wage_self, abs(theta) * wage_spouse) * (h_self +
   h_spouse)`, with `Q <= 2 - v`; the norm exponent satisfies
   `norm <= -conformism * w_transfer * (theta - N_theta)^2` exactly in
   Float64 (dropping two non-negative squares; the computed sum
   dominates the retained term by monotonicity). The material envelope
   maximizes the monotone material function over `v` in `[0, d]` at
   the analytic per-spec maximizer and both interval endpoints `v == 0`
   and `v == d`, taking the largest of the three: the endpoint maximum
   is belt-and-braces, so the bound does not depend on the maximizer
   being located exactly (the CES `R` formula for `v*` is
   ill-conditioned in `1/(1-beta)` as `beta -> 1`) and can only rise
   compared to the maximizer alone (fewer or equal prunes).
3. Floating-point soundness and the per-spec amplification analysis:
   the Float64 envelope bound is inflated by the total relative margin
   `OBJECTIVE_CERT_MARGIN = 1.0e-9` before the strict comparison. The
   margin covers the rounding of the computed `x`, `Q`, and `z`
   against their analytic bounds (a few ulps), the documented `<= 1`
   ulp error each of `^`, `sqrt`, and `exp` in the runtime math
   library, and their combination in `material * exp`. Per spec, only
   the CES outer power `S^(1/beta)` amplifies rounding: its condition
   number in the rounded inner sum `S = alpha * x^beta + (1 - alpha) *
   Q^beta` is `1/beta`, so an ulp-level error in `S` becomes the
   relative gap `(1/beta) * n_ops * eps` between the computed utility
   and the computed envelope (`eps = 2^-53`, `n_ops = 10` the combined
   inner-sum error budget of the two evaluations: two inner powers,
   two weight multiplies, and one add each, `<= 1` ulp apiece); the
   other specs (Additive, Multiplicative, MultiplicativeWeighted) have
   exponents `<= 1` and only contract rounding, so their gap stays at
   the ulp level of the previous paragraph. The safe-band rule
   follows: CES certifies only for `beta >= CES_CERT_MIN_BETA =
   1.0e-3`, where the amplification is at most about 1.0e-12 and the
   whole in-band budget stays more than three orders of magnitude
   below the 1.0e-9 margin (about 4500 ulps); below the band the
   amplification drowns the margin (`~1.0e-4` at `beta = 1.0e-12`, a
   reproduced false-prune counterexample) and the certificate fails
   open. `beta >= 1` needs no upper bound because `1/beta <= 1`
   contracts rounding. In that root case the envelope additionally
   guards its inner sum `S` and fails open on a subnormal `S` (the
   root would map its unbounded subnormal quantization error up into
   the normal material range); for `beta < 1` a subnormal `S` maps
   below the `floatmin` floor of every certified bound instead and
   needs no guard.
4. Fail open on doubt: any non-finite or out-of-range input (transfers
   outside `[-1, 1]`, negative wages, weights, or conformism, `alpha`
   outside `[0, 1]`, CES `beta` outside the certified band
   `beta >= CES_CERT_MIN_BETA`, non-finite norms or outside
   options), any non-finite or subnormal envelope intermediate, and
   any non-finite bound abort the certificate and run the full solve.
   The CES `beta >= 1` root branch additionally fails open when its
   inner sum `S` is subnormal (exactly-zero `S`, from exact zero `x`
   or `Q`, is computed exactly and accepted): the root maps `S`'s
   unbounded subnormal quantization error up into the normal material
   range. For `0 < beta < 1` no such guard is needed, because a
   subnormal `S` maps down below the `floatmin` floor that the largest
   candidate must exceed to certify, so it can never dominate a
   certified bound. An `x^beta`-style intermediate that overflows or
   underflows to zero is covered by the same guards (overflow makes
   `S` or the candidate value non-finite; a dropped-underflow term
   contributes under `2^-1075` absolute, which is negligible against a
   normal `S` and mapped below the bound floor when the whole sum
   underflows). Unenveloped `UtilitySpec`
   subtypes fail open via the fallback `_material_envelope` method.
   The exact-zero cases (`q == 0`) are sound by IEEE monotonicity: the
   computed consumption is `<= 0.0` at any hours, so
   `individual_utility` returns exactly `-Inf`. Fail open is the
   default: every guard is a conservative abort to the full solve, so
   an uncertain case never certifies.
5. The comparison is strict (`bound * (1 + OBJECTIVE_CERT_MARGIN) <
   outside`), so a zero gain is never pruned: at the status-quo
   transfer the gains are exactly `0.0` and `nash_product` returns the
   finite `0.0`, which can beat a `-Inf` status payoff.
6. Pruning is applied only to the payoff-only objective inside
   `bargain_transfer`, never to the committed-hours path
   (`equilibrium_payoff` at the chosen maximizer), never inside
   `outside_options`, `nash_product`, `equilibrium_payoff`, or
   `mutual_best_response`. A pruned sample therefore returns exactly
   the value the search would have seen, so the Brent trajectory of
   `MDR-0005`, the maximizer, the tie-breaking, and the committed
   outputs are unchanged. The non-finite-outside fast path likewise
   returns exactly the status fallback the all-`-Inf` search would
   have fallen back to.

## Deviations

- None in behavior: no output changed, no fixture needed regeneration,
  and no test was relaxed. The frozen oracle
  `test/reference_bargaining.jl` and
  `test/fixtures/bargaining_baseline.toml` are untouched.
- The measurement instrumentation lives only in throwaway copies
  under `/tmp/opencode/`; the package itself has no counters.
- `homophily` at 8 threads is scheduling-noise dominated (see above);
  its median is still 68.7% faster than baseline and no workload
  regressed at either thread count.
