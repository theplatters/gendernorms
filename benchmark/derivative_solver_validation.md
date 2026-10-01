# Derivative best-response validation (TASK-0023)

Validation evidence for the safeguarded derivative labour best
responses of `MDR-0017` (superseding `MDR-0002`) and their
specialized dispatch of `ADR-0022`: solution validation of the
derivative solve, solver-chain validated equivalence against the
frozen reference, the paired same-revision micro-benchmark, the
kernel-level before/after comparison, and the production route mix.
The implementation is in `src/resources/utility_functions.jl` and
`src/systems/household_bargaining.jl`; the battery is
`test/test_utility_solver.jl`, `test/test_bargaining_equivalence.jl`,
`test/test_household_bargaining.jl`, and `test/test_threading.jl`;
the micro-benchmark is `benchmark/derivative_solver_benchmark.jl`.
Gate verdict up front: the `TASK-0023` micro gate is MET (applicable
mix 3.42x of the legacy path, every applicable cell faster, inapplicable
cases bitwise), the kernel hard gate is MET and the `ws_500` one-thread
target of 1.15x is exceeded (measured 1.20x), but the closing-phase
aspiration of a >= 1.5x `set_theta!` kernel is NOT reachable: the
measured kernel gain is 1.04x to 1.20x, bounded by Amdahl because the
solver chain is only about a third of this kernel after the
`TASK-0021` transfer-search recovery. Section 7 states that one unmet
aspiration plainly and why. The numbers below stand as measured; no
measurement was repeated to make it pass (the one confirming rerun the
protocol allows for a noisy cell was spent on the eight-thread kernel
pair).

Environment: Julia 1.12.7, AMD Ryzen 7 5825U (16 hardware threads),
`JULIA_NUM_THREADS=1` and `8`, sequential runs on a lightly loaded
machine (idle desktop session), seed 1 everywhere. Baseline: git
worktree at commit `b6a6378` (the pre-change state of this work);
candidate: this working tree. Throwaway instrumentation drivers live
outside the repository in `/tmp/opencode/` (`count_driver.jl` in
instrumented copies of both trees).

## 1. Solution validation

All checks are assertions of `test/test_utility_solver.jl` unless
noted; the suite is green at 1 and 8 threads.

Two-tier accuracy contract (`MDR-0017`, `ADR-0022`): a tier-1 seed
certificate returns the seed `h_start` unchanged when the two
`+/- BEST_RESPONSE_TOL` sign probes enclose a derivative root (or the
one-sided domain-end rule holds), certifying the seed within
`BEST_RESPONSE_TOL` -- the NetLogo `current-delta` resolution -- of the
optimum; otherwise a tier-2 global bracketed safeguarded Newton solve
on `[0, 1]` returns the root certified to
`DERIVATIVE_RESPONSE_TOL = 1e-8`. Every ineligible or failed case runs
the seeded Brent expression of `MDR-0002` verbatim (bitwise). The two
tiers share one accuracy story: tier-1 is the model-resolution
certificate (a converged seed keeps its hours), tier-2 is the
solver-resolution global solve.

- Analytic optima ("derivative best response finds closed-form
  optima"): closed-form optima of the `Multiplicative`,
  `MultiplicativeWeighted`, `Additive`, and `CES` objectives are
  recovered to `<= 2.0e-7` hours from every seed, including the
  boundary optima and the `CES` `beta == 0.5` sqrt/square form.
- Finite differences ("derivative formulas match finite
  differences"): the closed-form `g = d log(U)/dh` and
  `g' = d2 log(U)/dh2` of every regime of `MDR-0017` (including the
  `MultiplicativeWeighted` payer quirk and `CES` `beta == 1`) match
  central finite differences of the call-overload value.
- Sign-probe contract (`MDR-0017` sign form, `ADR-0022`): the
  derivative sign probes evaluate the division-free multiplied-through
  residual `den * g = num + n_prime * den` (products only, the norm
  slope multiplied through by the same positive denominator `den`),
  whose sign is the analytic sign of `g` exactly in exact arithmetic
  because `den > 0` throughout every eligible regime. The residual is
  a different rounding of `g` than the Newton loop's derivative, so a
  spurious sign flip would need the residual within rounding noise of
  zero (in which case the true root sits inside the probe window up to
  noise / `|g'|`). A BigFloat adversarial scan over every eligible
  spec and adversarial corner (3,835,040 draws, 6,162,489 probe signs,
  959,227 tier-1 certificates, 2,344,692 tier-2 certificates) found 0
  sign violations against the exact residual sign. The probe fails
  open with `NaN` (skipped, never fatal) on an unenveloped spec or a
  non-finite/subnormal denominator product.
- Own-response first-order condition (regime grid, see below): every
  accepted interior candidate satisfies `|g| <= 1.0e-4` at its
  result; boundary candidates carry their certified endpoint sign.
- Enclosure invariant (regime grid): every accepted candidate whose
  enclosure probes at `+/- DERIVATIVE_RESPONSE_TOL` are both
  evaluable satisfies `g(h - tol) >= 0 >= g(h + tol)`.
- Computed-utility non-degradation: the candidate value never falls
  below the legacy solve (or a `+/- 1e-6` probe) beyond 32 ulps at
  the comparison scale for the O(1)-conditioned specs. For `CES` the
  envelope is `CES_DERIVATIVE_LOSS_TOL = 1.0e-11` relative: the
  computed utility evaluates `S^(1/beta)` from the rounded inner sum,
  whose condition number `1 / beta` amplifies the inner-sum rounding
  of two compared evaluations to the relative gap `2.0e-16 / beta`
  (`(1 / beta) * n_ops * eps`, `n_ops = 10`, `eps = 2^-53`; about
  1.1e-12 at the floor). Measured sweep behind the floor (log grid of
  `beta` in `[1.0e-6, 1.0]`, 4000 random parameter draws per beta
  over roles, wages, transfer, spouse hours, conformism, `alpha`,
  weights, and seeds): worst relative loss of the derivative result
  versus the legacy result about `2.0e-16 / beta`, crossing the
  1.0e-11 envelope between `beta = 2.0e-5` (1.11e-11) and
  `beta = 2.5e-5` (9.4e-12), 1.5e-13 at `beta = 1.0e-3`, 2.1e-15
  above `beta = 0.1`. The floor `CES_DERIVATIVE_MIN_BETA = 1.0e-3`
  is taken at the `CES_CERT_MIN_BETA` decade, where the analytic
  bound and the measured worst loss sit an order of magnitude inside
  the envelope; the sub-floor band runs the bitwise fallback.
- Fallback bitwise identity ("derivative best response keeps the
  legacy solver for inapplicable cases" and "...below the CES beta
  floor"): every inapplicable case (unsupported specs, `alpha` or
  spouse hours out of range, negative conformism or norm weight,
  non-finite fields, the all-infeasible payer, the flat `alpha == 1`
  payer quirk, the `alpha == 0` unattainable-supremum corner) is
  `isequal` to the explicit legacy expression
  `maximize_1d(obj, 0.0, 1.0, h_start, BEST_RESPONSE_WINDOW,
  BEST_RESPONSE_TOL)` at every seed, including `NaN` and signed
  zeros. Reviewer repro (`CES` `beta = 1.0e-12`, `alpha = 0.5`,
  `wage_self = 1.0`, `wage_spouse = 2.0`, transfer 0.3, spouse hours
  0.05): the sub-floor computed utility is jagged at the 1e-4
  relative level and a certified analytic root used to return
  0.9899478346405225 at 0.9599999999999227 versus the legacy
  0.9900577470296925 at 0.9576275641403225; below the floor the case
  is inapplicable and bitwise legacy (`_derivative_applicable ==
  false`, asserted), and the whole measured sub-floor band
  (`beta` in 1e-12, 1e-6, 1e-5, 2e-5, 9.9e-4) stays bitwise legacy
  at every seed while the floor itself is the first applicable `CES`
  regime.
- Width-exit certificate ("derivative best response width exit
  certifies a sign bracket"): reviewer repro 2 (`MultiplicativeWeighted`
  payer, `alpha = 1e-12`, zero conformism, transfer `-0.3`, spouse
  hours 0.5, seed 0.3; the lower feasible end is open, `x(0) == 0`,
  so the left enclosure probe is skipped and returns `NaN`). The
  solved candidate measures `8.940696716308593e-9`, within
  `DERIVATIVE_RESPONSE_TOL = 1e-8` of an independently bisected root
  of `g` (`1.5e-12`, 100 bisection steps on the sign probe; distance
  `8.94e-9`), so the maintained sign bracket certifies a point the
  probe enclosure cannot. The noise-guard half of the certificate
  (both probes evaluable but not enclosing) is not constructible in
  the eligible regime: a spurious sign flip needs the multiplied-through
  residual within rounding noise of zero, which the BigFloat scan of
  the sign-probe contract found no case of, and the invariant is
  pinned structurally by the regime grid.
- Regime grid and quality invariant: 9 specs x 4 `alpha` x 2
  conformism x 4 theta x 3 spouse hours x 2 wages x 3 seeds
  (`checked > 1000` asserted) covering the full eligible beta range
  from the floor to 1.0; inapplicable cells bitwise, applicable cells
  feasible with finite positive value, FOC, enclosure, and the
  non-degradation envelopes above.
- Fast-path idempotence ("derivative best response settles a solved
  point"): re-solving at a returned point takes the fast path and
  returns it bitwise, which is what makes `mutual_best_response`
  settle on bitwise fixed points.
- Zero allocations and inference ("derivative best response
  allocates nothing and infers"): `@allocated` 0 and `@inferred`
  `Float64`/`Bool` returns for `best_response_1d`,
  `_derivative_best_response`, and the `mutual_best_response` pair
  across all specs, roles, and fallback routes.

## 2. Solver-chain validated equivalence

`test/test_bargaining_equivalence.jl` replays the 200 solver fixture
cases of `test/fixtures/bargaining_baseline.toml` (all four
`UtilitySpec`s, `CES` betas 0.2/0.5/1.5, zero wages, `alpha` 0/1,
bracket-endpoint transfers) against the frozen reference chain of
`test/reference_bargaining.jl`, and applies the `MDR-0017`
validated-equivalence tolerances where the specialized solver
applies. The envelopes below are the re-measured worst cases over the
200 fixture cases and a deterministic 3,456-case draw grid (all four
specs, both roles, `alpha` edges, theta edges, `h_spouse` edges,
conformism 0/10, unequal wages), each quantity's measured worst over
the subset in parentheses; every value sits inside its test tolerance
(the throwaway envelope driver reports 0 cases failing the `VE_*`
envelopes, whose constants it mirrors exactly):

| Quantity | Measured worst (fixture / grid) | Test tolerance |
| --- | --- | --- |
| solver hours per partner | 9.6e-5 / 3.5e-4 | `VE_HOURS_ATOL = 2.0e-3` (two `eps` sweep budgets) |
| outside-option utilities | 2.4e-4 / 2.6e-4 | `VE_UTIL_ATOL/RTOL = 1.0e-3` |
| gains | 1.8e-4 / 4.4e-4 | `VE_UTIL_ATOL/RTOL = 1.0e-3` |
| status Nash payoff | 1.8e-5 / 1.8e-4 | `VE_PAYOFF_ATOL/RTOL = 1.0e-4` / `1.0e-3` |
| feasible/non-finite flips | 0 / 9 | accepted by the 1e-4 zero-gain knife rule |
| unseeded-Brent maximizer payoff | 7.3e-5 | `VE_MAXIMIZER_PAYOFF_ATOL = 5.0e-4` |

The nine grid flips are all zero-gain knife-edge cases (the crossing
gain sits at the 1e-5 to 1e-10 scale): the live chain commits
`status = -Inf` (or a tiny positive) where the reference commits a
tiny positive (or `-Inf`) because one partner's gain rounds just
across zero. The payoff envelope accepts each because the finite side
is within `VE_PAYOFF_ATOL = 1e-4` of zero (the documented 1e-4
knife-edge rule); the fixture subset has 0 such flips and there are 0
one-sided non-finite value mismatches. New-solver-versus-legacy
computed-utility difference at the solved hours (the tier-1 window
asymmetry envelope): worst relative `|U(new) - U(legacy)|` 6.8e-7 on
the fixture and 1.1e-7 on the grid; `MDR-0017` records a 1.85e-4
outlier of the same quantity from a larger draw grid. All are far
inside `BEST_RESPONSE_VALUE_RTOL = 5.0e-4`.

The residual (frozen) arithmetic differences of the `CES`
`beta == 0.5` specialization are compared under the `MDR-0013` ulp
envelope `VE_ATOL = 1.0e-10` / `VE_RTOL = 1.0e-9`, which is that
envelope with a 100x margin. Own-utility non-degradation at the
solved hours is checked case by case.

## 3. Micro-benchmark (same-revision, paired)

`benchmark/derivative_solver_benchmark.jl`, median of 31 rounds x
201 calls per cell, 7 specs x 2 roles x 2 parameter sets x 4 seeds
(certified seed, warm start `+0.002`, far starts `0.05`/`0.95`),
both solver expressions callable in one build. Per-spec medians over
all roles and starts (ns per call). The recorded final run of
`TASK-0023` is the headline; the confirming run of this session is
shown alongside so the measurement spread is visible:

| Spec | Speedup (recorded final) | Speedup (confirming) |
| --- | --- | --- |
| multiplicative | 3.23x | 1.74x |
| mult_weighted | 3.01x | 3.0x |
| additive | 1.48x | 1.47x |
| ces_beta_0.5 | 1.46x | 1.43x |
| ces_beta_0.2 | 1.49x | 1.49x |
| ces_beta_0.9 | 2.84x | 2.85x |
| ces_beta_1.0 | 4.33x | 4.32x |
| applicable mix | 3.42x (legacy 408.8 / new 119.4 ns) | 3.20x (392.8 / 122.9 ns) |

Six of seven per-spec medians reproduce to within 0.03x and the
applicable mix to within 4%; the two run-to-run movers are the
multiplicative per-spec median (1.74x confirming against the recorded
3.23x) and the additive converged-seed floor cell (1.11x against
1.15x). Both are statistics of fast or bimodal cells (the
multiplicative time distribution straddles the tier-1/interior
boundary, so its median is unstable); both stay well clear of 1.0x,
so the "no applicable cell is slower" claim is unaffected.

Route fractions over the mix matrix: tier1 28.6%, interior 64.3%,
boundary 7.1%, fallback 0.0% (the width-exit noise guard never
fired; reproduced exactly by the confirming run). Both solver paths
allocate 0 bytes on every matrix cell and on the
`mutual_best_response` pair. Inapplicable cases (the
`CES_DERIVATIVE_MIN_BETA` sub-floor band and out-of-regime specs,
including the reviewer repro `beta = 1e-12`) are bitwise identical
to the legacy expression at parity within measurement noise (0.96x
to 1.0x this session).

Converged-seed (tier-1) cells, the fast path of the production
geometry, are faster than the legacy three-sample return on every
spec after the division-free sign probes and shared reciprocals
(speedup range across roles and parameter sets): multiplicative
1.86x to 18x, `mult_weighted` 9x to 11x, additive 1.15x to 7.26x,
`CES` `beta == 0.5` 1.26x to 7.56x, `beta == 0.2` 1.6x to 6.4x,
`beta == 0.9` 2.2x to 2.5x, `beta == 1.0` 2.6x to 3.4x. The slowest
applicable cell in the whole matrix is the additive converged-seed
cell (recorded 1.15x; the confirming run measured 1.11x to 1.17x on
that fast cell, always greater than 1.0x). Every applicable cell is
faster than the legacy path at the median; no supported spec bucket
is slower.

Variant note: a lazy-value variant (deferring the objective value
evaluation until the accept test) was measured and dropped -- it
regressed the interior cells by about +25 ns. The shared-reciprocal
form (`inv_m = 1 / m` reused across `g_mat` and `g_prime_mat`) is
kept.

The `mutual_best_response` alternation rows of the same benchmark
show the production geometry: near-fixed-point starts are 2.3x to
7.8x, `+0.01` perturbations 1.5x to 4.0x, and far starts 1.8x to
5.6x across the specs; the solved-hour pairs agree with the legacy
alternation to 1e-4 or better.

## 4. Kernel before/after (`benchmark/bargaining_kernel.jl`)

Methodology `MDR-0011`/`ADR-0013`: 20 ticks, 15 repetitions, one
fresh `create_world` per repetition from identical seeded initial
states, the timed section is exactly the `set_theta!` calls of the
`step_model!` tick order. Baseline = git worktree at `b6a6378` with
its own project; candidate = this tree; runs interleaved in time
(legacy, new, legacy, new) to bound session drift. Kernel medians of
each run in seconds; the summary is the median over the run medians.

| Workload | Threads | Kernel med before (runs) | Kernel med after (runs) | Speedup | IQR before/after | Alloc B per household-tick before/after | e2e med before/after |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ws_500 | 1 | 0.05619 (0.05579, 0.05659) | 0.04704 (0.04654, 0.04753) | 1.20x | 0.0025-0.0030 / 0.0019-0.0020 | 1661.6 / 1661.3 | 0.0597-0.0605 / 0.0516-0.0521 |
| ws_500 | 8 | 0.01414 (0.01443, 0.01414, 0.01367) | 0.01356 (0.01356, 0.01260, 0.01360) | 1.04x | 0.0016-0.0022 / 0.0012-0.0025 | 1669.0 / 1668.7 | 0.0192-0.0199 / 0.0179-0.0185 |
| heterogeneous | 1 | 0.05271 (0.05235, 0.05307) | 0.04502 (0.04503, 0.04500) | 1.17x | 0.0009-0.0022 / 0.0013-0.0016 | 1656.1 / 1656.1 | 0.0566-0.0573 / 0.0492-0.0493 |
| heterogeneous | 8 | 0.01405 (0.01405, 0.01430, 0.01351) | 0.01271 (0.01271, 0.01217, 0.01303) | 1.10x | 0.0011-0.0018 / 0.0016-0.0023 | 1663.5 / 1663.6 | 0.0183-0.0195 / 0.0171-0.0181 |

Every cell is faster than its baseline (the hard no-regression gate is
met with margin; the minimum cell speedup is 1.04x on the noisy
eight-thread `ws_500` and 1.20x on `ws_500` at one thread, exceeding
the 1.15x target). The allocations of the timed kernel section are
unchanged (the derivative path allocates nothing; the ~5.1 allocs per
household-tick are transfer-search bookkeeping). End-to-end
`GenderNorms.run` medians move with the kernel.

## 5. Production route mix and the gate anatomy

Throwaway instrumented copies of both trees (`/tmp/opencode/`,
counters added only there) run the `ws_500` kernel workload through
the exact tick order at 1 thread (500 households, 20 ticks, seed 1);
per-route solver time is measured with `time_ns()` accumulators and
corrected by a self-calibrated 20.0 ns per-accumulation overhead.

| Quantity (20 ticks, 500 households) | Legacy (`b6a6378`) | New (this tree) |
| --- | --- | --- |
| `best_response_1d` calls | 249,108 | 248,882 |
| `mutual_best_response` calls | 95,134 | 95,082 |
| alternation sweeps | 124,554 (1.309 per solve) | 124,441 (1.309 per solve) |
| certified/anchored seed returns | 163,737 (65.7%) at 32.9 ns | 179,981 (72.3%) at 23.1 ns |
| tier-2 interior (windowed search / global solve) | 85,371 (34.3%) at 191.4 ns | 68,384 (27.5%) at 117.4 ns |
| tier-2 boundary | - | 517 (0.2%) at 78.5 ns |
| fallback / non-finite | 0 | 0 |
| solver-chain total | 21.7 ms | 12.2 ms |
| kernel median (uninstrumented, section 4) | 56.2 ms | 47.0 ms |
| solver-chain share of kernel | 38.6% | 25.9% |

The two trees drive the same workload (identical call and sweep
counts to within 226 calls); only the per-call solver cost differs.
The solver chain is 21.7 ms to 12.2 ms, a 1.78x chain speedup (the
~1.5x figure was the pre-sign-probe chain; the division-free sign
probes and shared reciprocals improved it further). The route mix
changed as `MDR-0017` intends: tier-1 certification keeps 72.3% of
calls at their converged seed (up from the legacy 65.7% anchor,
because certification now provably accepts every seed within
`BEST_RESPONSE_TOL` of the optimum, not just those whose `+/-` probe
neighbours fail to improve), and the tier-2 global solve moves the
remaining 27.5% to the true optimum at 117.4 ns instead of the
legacy windowed search's 191.4 ns. This de-anchoring is the intended
model-behavior change of `MDR-0017`: a household at a discrete local
maximum is no longer pinned there.

Amdahl decomposition of the measured kernel gain: the solver chain is
38.6% of the legacy kernel and 25.9% of the new one (about a third),
and the 1.78x chain speedup bounds the kernel at
`1 / ((1 - 0.386) + 0.386 / 1.78) = 1.20x`, which is what `ws_500`
measures at one thread (1.195x). The >= 50% figure of the closing
phase is met at the solver level (applicable mix 3.42x, production
chain 1.78x), but because the chain is only about a third of this
kernel the kernel gain cannot exceed roughly 1.2x to 1.3x. The
1.5x kernel bar is therefore not reachable on `ws_500`: the task
premise that "labour solves dominate the bargaining kernel" (59
percent of the `MDR-0014` anatomy) predates the `TASK-0021` /
`TASK-0022` search driver, which shrank the kernel to about 47 ms
per 20 ticks and made its best-response mix near-equilibrium (1.309
sweeps per solve).

Model-level note: the tier-1 certificate keeps a converged seed within
the certified `BEST_RESPONSE_TOL` window exactly as the legacy anchor
did, but now certified rather than path-dependent; the tier-2 solve is
global on `[0, 1]` at `1e-8`, so it reaches the true optimum instead
of a window-local one. The equivalence envelopes of section 2 bound
the resulting hours/utility movement.

## 6. Determinism

- Repeat-run determinism: `test/test_run_pipeline.jl` ("identical
  seeds reproduce identical metrics").
- Cross-thread-count determinism: `test/test_threading.jl` ("full
  runs are bit-identical across thread counts") runs
  `test/threading_driver.jl` in fresh subprocesses at 1 and 4
  threads and asserts byte-identical output; the parallel world
  loops are asserted bitwise equal to the sequential reference at
  every thread count (`ADR-0014`). This is the `(4)` clause of the
  `MDR-0017` equivalence protocol (new versus new).
- The full suite is green at `JULIA_NUM_THREADS=1` and `8`.

## 7. Gate verdict

| Gate | Bar | Verdict |
| --- | --- | --- |
| applicable micro mix | >= 1.5x | MET (3.42x) |
| no applicable cell slower | >= 1.0x every cell | MET (min 1.15x recorded; 1.11x confirming, all > 1.0x) |
| inapplicable parity | bitwise | MET (bitwise) |
| kernel no-regression | >= 1.0x everywhere | MET (1.04x to 1.20x) |
| kernel target (`ws_500`, 1 thread) | >= 1.15x | MET (1.20x) |
| kernel aspiration | >= 1.5x | NOT REACHABLE (Amdahl; measured 1.04x to 1.20x) |

The `TASK-0023` registered performance gate (the paired micro gate)
is MET: the applicable mix median is 3.42x of the legacy path (the
bar was `<= 2/3` of it, i.e. >= 1.5x), every applicable cell is
faster at the median (min 1.15x), and inapplicable cases are bitwise
identical at parity. The kernel hard gate (no regression) is MET with
margin and the `ws_500` one-thread target of 1.15x is exceeded
(1.20x).

The one unmet aspiration is the closing-phase >= 1.5x `set_theta!`
kernel bar, and it is not borderline-reachable: the solver chain is
only about a third of this kernel after the `TASK-0021` transfer-search
recovery, so even the 3.42x applicable mix and the 1.78x production
chain bound the kernel at about 1.2x (Amdahl, section 5), and the
measured kernel is 1.04x to 1.20x across workloads and thread counts.
The task premise that labour solves dominate the bargaining kernel
predates `TASK-0021`/`TASK-0022`, which shrank the kernel and made
its best-response mix near-equilibrium. Honest assessment: the change
is a solution-quality and worst-case-solve-cost win that also happens
to make every kernel cell modestly faster (1.2x on the representative
workload at one thread); it is not a 1.5x kernel optimization, and no
plausible rerun makes it one.
